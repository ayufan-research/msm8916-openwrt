#!/bin/bash
# build.sh
# Builds the container image from .github/dev/Dockerfile and builds OpenWrt in
# it. The checkout lives in ./openwrt on the host, so downloads and build
# artifacts survive between runs. CI uses this too, so local and release
# builds share one environment.
#
# Usage:
#   ./build.sh [options] [command ...]
#
#   ./build.sh --device uz801              # build the images
#   ./build.sh --device uz801 --shell      # shell in the OpenWrt tree instead
#   ./build.sh -d m9s make menuconfig      # pulls in openwrt-with-display
#
# Options:
#   -d, --device <device>  device config to install; required unless $DEVICE is
#                          set. The overlay that owns it is applied with it, so
#                          m9s and mf68e pull in openwrt-with-display by
#                          themselves
#   -o, --overlay <name>   extra overlay to apply, whatever the device; repeat
#                          the option for more than one
#       --force-config     reinstall the device config even if it is the
#                          current one
#       --clean            undo the overlays in the checkout and apply them
#                          again, and clean the kernel so its patches are
#                          re-applied
#   -s, --shell            open a shell in the tree instead of building
#   -h, --help             print this help
#
# With no command it runs make -j<cpus>. Everything after the first non-option
# argument is a command to run in the tree instead; -- ends the options if that
# command itself starts with a dash.
#
# Environment (the options above take precedence):
#   DEVICE            as --device
#   OVERLAY           as --overlay, space-separated
#   FORCE_CONFIG=1    as --force-config
#   CLEAN=1           as --clean
#   OPENWRT_VERSION   branch, tag, or tag pattern to clone (default v25.12.*);
#                     a pattern resolves to the newest matching tag. The
#                     msm89xx target pins kernel 6.12, which OpenWrt main no
#                     longer carries, so main does not build as it stands
#   OPENWRT_DIR       checkout directory (default openwrt)
#   EXTRA_CONFIG      extra .config lines, appended before make defconfig
#
# Building several devices in one tree is a matter of calling it per device:
# the config is swapped, make defconfig re-run, and the toolchain stays. Pass
# --clean when the overlays change between devices.
set -e

cd "$(dirname "$0")"

IMAGE="${IMAGE:-msm8916-openwrt-dev}"
OPENWRT_VERSION="${OPENWRT_VERSION:-v25.12.*}"
OPENWRT_DIR="${OPENWRT_DIR:-openwrt}"
DEVICE="${DEVICE:-}"
OVERLAY="${OVERLAY:-}"
FORCE_CONFIG="${FORCE_CONFIG:-}"
CLEAN="${CLEAN:-}"
SHELL_ONLY=

# the device configs the overlays carry, as --device accepts them
known_devices() {
    ls openwrt-*/configs/diffconfig_* 2>/dev/null \
        | sed 's|.*/diffconfig_||' | sort -u | tr '\n' ' '
}

while [ $# -gt 0 ]; do
    case "$1" in
        --device|-d)
            DEVICE="$2"
            shift
            ;;
        --device=*) DEVICE="${1#--device=}" ;;
        --overlay|-o)
            OVERLAY="$OVERLAY $2"
            shift
            ;;
        --overlay=*) OVERLAY="$OVERLAY ${1#--overlay=}" ;;
        --force-config) FORCE_CONFIG=1 ;;
        --clean) CLEAN=1 ;;
        --shell|-s) SHELL_ONLY=1 ;;
        -h|--help)
            sed -n '2,48p' "$0" | sed 's|^# \?||'
            echo
            echo "Devices: $(known_devices)"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: unknown option '$1'"
            exit 1
            ;;
        *) break ;;
    esac
    shift
done

if [ -z "$DEVICE" ]; then
    echo "Error: no device given; pass --device <device> or set \$DEVICE"
    echo "Devices: $(known_devices)"
    exit 1
fi

if [ -n "$SHELL_ONLY" ]; then
    if [ $# -gt 0 ]; then
        echo "Error: --shell takes no command (got '$*')"
        exit 1
    fi
    set -- bash
elif [ $# -eq 0 ]; then
    set -- make -j"$(nproc)"
fi

export FORCE_CONFIG

# build through ccache (CONFIG_CCACHE needs CONFIG_DEVEL); OpenWrt keeps it in
# <openwrt>/.ccache
EXTRA_CONFIG="$(printf 'CONFIG_DEVEL=y\nCONFIG_CCACHE=y\n%s' "${EXTRA_CONFIG:-}")"
export EXTRA_CONFIG

case "$OPENWRT_DIR" in
    /*|../*|*/../*)
        echo "Error: OPENWRT_DIR must be inside the repository (it is mounted as /repo)"
        exit 1
        ;;
esac

in_docker() {
    local tty=()
    [ -t 0 ] && [ -z "$NO_TTY" ] && tty=(--interactive --tty)

    docker run --rm "${tty[@]}" \
        --volume "$PWD:/repo" \
        --workdir /repo \
        --user "$(id -u):$(id -g)" \
        --env HOME=/home/builder \
        --env EXTRA_CONFIG \
        --env FORCE_CONFIG \
        "$IMAGE" "$@"
}

echo "==> Building $IMAGE"
docker build --tag "$IMAGE" --file .github/dev/Dockerfile .

if [ ! -d "$OPENWRT_DIR/.git" ]; then
    case "$OPENWRT_VERSION" in
        *'*'*|*'?'*)
            resolved=$(NO_TTY=1 in_docker git ls-remote --tags \
                https://git.openwrt.org/openwrt/openwrt.git "$OPENWRT_VERSION" \
                | sed 's|.*refs/tags/||' | grep -v '\^{}$' | sort -V | tail -1)
            if [ -z "$resolved" ]; then
                echo "Error: no OpenWrt tag matches $OPENWRT_VERSION"
                exit 1
            fi
            echo "==> Resolved $OPENWRT_VERSION -> $resolved"
            OPENWRT_VERSION="$resolved"
            ;;
    esac

    # fetch instead of clone: dl/ and .ccache/ may already be there, restored
    # from a cache
    echo "==> Fetching OpenWrt $OPENWRT_VERSION into $OPENWRT_DIR"
    in_docker bash -c "
        mkdir -p '$OPENWRT_DIR'
        cd '$OPENWRT_DIR'
        git init -q
        git remote add origin https://git.openwrt.org/openwrt/openwrt.git
        git fetch --depth=1 origin '$OPENWRT_VERSION'
        git checkout -q FETCH_HEAD
    "
fi

# setup.sh installs the config when it is missing or belongs to another device,
# and then it has to be expanded again
NEED_DEFCONFIG=
[ -f "$OPENWRT_DIR/.config" ] || NEED_DEFCONFIG=1
[ "$(cat "$OPENWRT_DIR/.msm89xx-config" 2>/dev/null)" = "$DEVICE" ] || NEED_DEFCONFIG=1
[ -z "$FORCE_CONFIG" ] || NEED_DEFCONFIG=1

overlay_args=()
for name in $OVERLAY; do
    overlay_args+=(--overlay "$name")
done

echo "==> Applying overlays for $DEVICE"
in_docker .github/dev/setup.sh --config "$DEVICE" "${overlay_args[@]}" \
    ${CLEAN:+--clean} "$OPENWRT_DIR"

if [ ! -d "$OPENWRT_DIR/feeds/luci" ]; then
    echo "==> Installing feeds"
    in_docker bash -c "
        cd '$OPENWRT_DIR'
        rm -rf tmp
        ./scripts/feeds update -a
        ./scripts/feeds install -a

        # LuCI getFeatures crashes when odhcpd is absent (may be fixed already)
        luci=feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci
        if [ -f \"\$luci\" ] && grep -q 'result\.odhcpd = false;' \"\$luci\"; then
            sed -i 's/result\.odhcpd = false;/result.odhcpd = {};/' \"\$luci\"
        fi
    "
fi

# setup.sh copies the overlays with cp -a, so a file it has just installed can
# be older than the metadata make cached in tmp/ and make then keeps that cache.
# The devices an overlay adds (m9s, mf68e, from image/devices-*.mk) are missing
# from it, defconfig drops the device the config asks for and settles on the
# target's default one, and the build then makes a uz801 image and calls it m9s.
# Drop the cache whenever the overlays or the config changed.
if [ -n "$NEED_DEFCONFIG" ] || [ -n "$CLEAN" ]; then
    echo "==> Dropping the cached metadata"
    rm -rf "$OPENWRT_DIR/tmp"
fi

if [ -n "$NEED_DEFCONFIG" ]; then
    echo "==> make defconfig"
    in_docker bash -c "cd '$OPENWRT_DIR' && make defconfig"
fi

# The kernel is patched when it is prepared, so the patches the overlays just
# changed only take effect once its build directory is gone. This has to run
# after make defconfig, not before: setup.sh installs the device config as the
# bare diffconfig, and every make target except defconfig takes .config as it
# finds it and runs menuconfig to fill in the rest, which cannot work with no
# terminal ("Error opening terminal: unknown"). Only --clean with a change of
# overlay reaches this, which is why it took a device with a display to show up.
if [ -n "$CLEAN" ] && [ -f "$OPENWRT_DIR/.config" ]; then
    echo "==> make target/linux/clean"
    in_docker bash -c "cd '$OPENWRT_DIR' && make target/linux/clean"
fi

# A broken target Makefile does not fail the build: the metadata scan writes an
# empty .targetinfo entry, CONFIG_TARGET_msm89xx never becomes a real symbol,
# make defconfig drops it and falls back to OpenWrt's own default target, and
# the build then happily produces an image for a device nobody asked for and
# exits 0. The same goes for a .msm89xx-config stamp that no longer describes
# .config. Check what we are about to build before spending hours on it.
board=$(sed -n 's|^CONFIG_TARGET_BOARD="\(.*\)"$|\1|p' "$OPENWRT_DIR/.config")
profile=$(sed -n 's|^CONFIG_TARGET_PROFILE="DEVICE_\(.*\)"$|\1|p' "$OPENWRT_DIR/.config")
expected=$(sed -n 's|^CONFIG_TARGET_msm89xx_msm8916_DEVICE_\(.*\)=y$|\1|p' \
    openwrt-*/configs/diffconfig_"$DEVICE")

if [ "$board" != "msm89xx" ]; then
    echo "Error: .config targets '$board', not msm89xx"
    echo "       the target did not survive make defconfig - check that"
    echo "       $OPENWRT_DIR/target/linux/generic/ carries the kernel version"
    echo "       target/linux/msm89xx/Makefile pins (currently 6.12)"
    exit 1
fi

if [ -n "$expected" ] && [ "$profile" != "$expected" ]; then
    echo "Error: .config builds '$profile', but $DEVICE is '$expected'"
    echo "       re-run with --force-config to reinstall the device config"
    exit 1
fi

echo "==> Building $board profile $profile"

echo "==> $* (in $OPENWRT_DIR)"
in_docker bash -c 'cd "$1" && shift && exec "$@"' bash "$OPENWRT_DIR" "$@"
