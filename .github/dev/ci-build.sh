#!/bin/bash
# ci-build.sh
# Builds one device in CI, so build.yml can give each of them a step of its own
# and the log says plainly which device is being built.
#
#   .github/dev/ci-build.sh <device>
#
# The overlay that owns the device config is applied with it, and the tree is
# undone first when that overlay is not the one the previous device used. The
# device built last is remembered in .ci-overlay next to the checkout, since
# every step runs in its own shell.
set -e

cd "$(dirname "$0")/../.."

device="$1"
if [ -z "$device" ]; then
    echo "Error: no device given"
    exit 1
fi

state=.ci-overlay

owner=$(ls -d openwrt-*/configs/diffconfig_"$device" | head -1)
owner="${owner%%/*}"

# the overlay this device needs on top of openwrt-base, if any
overlay=
[ "$owner" = "openwrt-base" ] || overlay="$owner"

# a different overlay means the tree has to be undone first; the first device
# of a run has nothing to undo
clean=
if [ -f "$state" ] && [ "$overlay" != "$(cat "$state")" ]; then
    clean=1
fi
echo "$overlay" > "$state"

echo "Building $device${overlay:+ ($overlay)}${clean:+ [clean]}"

export DEVICE="$device" OVERLAY="$overlay" CLEAN="$clean"

./build.sh make download -j8
find openwrt/dl -size -1024c -exec rm -f {} \; || true

# the tree is set up now, do not undo it again for the build itself
export CLEAN=

./build.sh make -j"$(nproc)" || ./build.sh make -j1 || ./build.sh make -j1 V=s
