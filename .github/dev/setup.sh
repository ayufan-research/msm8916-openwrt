#!/bin/bash
# setup.sh
# Copies this repository's overlays into an OpenWrt checkout and applies the
# patches that belong on top of it. An overlay is laid out as:
#
#   <overlay>/root/        -> <openwrt>/            (target and packages)
#   <overlay>/patches/     -> patch -p1 in <openwrt>
#   <overlay>/configs/     -> <openwrt>/.config     (diffconfig per device)
#
# openwrt-base is always applied. --config names a device config, and the
# overlay that owns it is applied too, so a config from openwrt-with-display
# pulls in that overlay by itself. --overlay applies one regardless.
#
# The installed config is remembered in <openwrt>/.msm89xx-config, so asking
# for another one replaces .config while re-running the same one keeps it (and
# any menuconfig edits). --force-config replaces it either way.
#
# --clean reverts the checkout to its own state first - the files the overlays
# copied are deleted and the patched files are restored from git - so a tree
# that was set up for another overlay can be reused. dl/, .ccache/, .config and
# the build directories are left alone.
#
# Usage:
#   .github/dev/setup.sh [--config <device>] [--overlay <name>] [--force-config]
#                        [--clean] [openwrt-dir]
#
# openwrt-dir defaults to openwrt and is relative to the repository root.
# $EXTRA_CONFIG is appended to the installed .config.
set -e

cd "$(dirname "$0")/../.."

OVERLAYS="openwrt-base openwrt-with-display"

CONFIG=
EXTRA_OVERLAYS=
FORCE_CONFIG="${FORCE_CONFIG:-}"
CLEAN="${CLEAN:-}"
OPENWRT=

while [ $# -gt 0 ]; do
    case "$1" in
        --config|-c)
            CONFIG="$2"
            shift
            ;;
        --config=*) CONFIG="${1#--config=}" ;;
        --overlay|-o)
            EXTRA_OVERLAYS="$EXTRA_OVERLAYS $2"
            shift
            ;;
        --overlay=*) EXTRA_OVERLAYS="$EXTRA_OVERLAYS ${1#--overlay=}" ;;
        --force-config) FORCE_CONFIG=1 ;;
        --clean) CLEAN=1 ;;
        -h|--help)
            sed -n '2,28p' "$0" | sed 's|^# \?||'
            exit 0
            ;;
        -*)
            echo "Error: unknown option '$1'"
            exit 1
            ;;
        *)
            OPENWRT="$1"
            ;;
    esac
    shift
done

OPENWRT="${OPENWRT:-openwrt}"

if [ ! -f "$OPENWRT/rules.mk" ]; then
    echo "Error: $OPENWRT is not an OpenWrt checkout"
    exit 1
fi

# the overlay that carries this device config, if any
config_overlay() {
    local overlay

    for overlay in $OVERLAYS; do
        if [ -f "$overlay/configs/diffconfig_$1" ]; then
            echo "$overlay"
            return 0
        fi
    done

    return 1
}

list_configs() {
    local overlay

    for overlay in $OVERLAYS; do
        ls "$overlay/configs/" 2>/dev/null | sed "s|^diffconfig_|  |;s|$|  ($overlay)|"
    done
}

apply_patch() {
    local patch="$1"

    # already applied if it reverses cleanly
    if patch -p1 -R -f -s --dry-run -d "$OPENWRT" < "$patch" >/dev/null 2>&1; then
        echo "  patch (applied) $patch"
        return
    fi

    echo "  patch           $patch"
    patch -p1 --fuzz=0 --no-backup-if-mismatch -s -d "$OPENWRT" < "$patch"
}

# undo an overlay: drop the files it copied, prune the directories that held
# them, and leave everything else (dl, .ccache, build dirs, .config) in place
clean_overlay() {
    local name="$1"
    local rel

    [ -d "$name/root" ] || return 0

    (cd "$name/root" && find . \( -type f -o -type l \) -printf '%P\n') \
        | while read -r rel; do
            rm -f "$OPENWRT/$rel"
        done

    (cd "$name/root" && find . -type d -printf '%P\n') | sort -r \
        | while read -r rel; do
            [ -n "$rel" ] || continue
            rmdir "$OPENWRT/$rel" 2>/dev/null || true
        done

    echo "  clean           $name/root files removed from $OPENWRT"
}

overlay() {
    local name="$1"
    local patch

    if [ -d "$name/root" ]; then
        cp -a "$name/root/." "$OPENWRT/"
        echo "  copy            $name/root -> $OPENWRT"
    fi

    for patch in "$name"/patches/*.patch; do
        [ -e "$patch" ] || continue
        apply_patch "$patch"
    done
}

# openwrt-base, plus whatever the requested config needs
selected="openwrt-base"

if [ -n "$CONFIG" ]; then
    owner=$(config_overlay "$CONFIG") || {
        echo "Error: no configs/diffconfig_$CONFIG in any overlay - available:"
        list_configs
        exit 1
    }

    [ "$owner" = "openwrt-base" ] || selected="$selected $owner"
fi

for name in $EXTRA_OVERLAYS; do
    if [ ! -d "$name" ]; then
        echo "Error: no overlay '$name' - available: $OVERLAYS"
        exit 1
    fi

    case " $selected " in
        *" $name "*) ;;
        *) selected="$selected $name" ;;
    esac
done

echo "Setting up $OPENWRT ($selected)..."

if [ -n "$CLEAN" ]; then
    for name in $OVERLAYS; do
        clean_overlay "$name"
    done

    if [ -d "$OPENWRT/.git" ]; then
        git -C "$OPENWRT" checkout -- .
        echo "  clean           patched files restored from git"
    else
        echo "  clean           $OPENWRT is not a git checkout, patched files kept"
    fi
fi

for name in $selected; do
    overlay "$name"
done

if [ -n "$CONFIG" ]; then
    diffconfig="$owner/configs/diffconfig_$CONFIG"
    installed=$(cat "$OPENWRT/.msm89xx-config" 2>/dev/null || true)

    if [ -f "$OPENWRT/.config" ] && [ "$installed" = "$CONFIG" ] && [ -z "$FORCE_CONFIG" ]; then
        echo "  config (kept)   $OPENWRT/.config is already $CONFIG"
    else
        {
            cat "$diffconfig"
            [ -n "$EXTRA_CONFIG" ] && printf '%s\n' "$EXTRA_CONFIG"
        } > "$OPENWRT/.config"
        echo "$CONFIG" > "$OPENWRT/.msm89xx-config"
        echo "  config          $diffconfig -> $OPENWRT/.config"
    fi
fi

echo "Done"
