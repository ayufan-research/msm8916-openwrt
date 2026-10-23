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
#
# An OpenWrt build prints tens of thousands of lines and the run page will not
# render that, so every phase is wrapped in a workflow group: the step then
# shows one collapsed line per phase and the output is there when it is opened.
# The whole log is kept in logs/<device>.log for build.yml to upload, the
# failing lines are repeated at the end where they are easy to find, and the
# first of them is raised as an annotation so the run page names the breakage
# without the log being opened at all.
set -eo pipefail

cd "$(dirname "$0")/../.."

device="$1"
if [ -z "$device" ]; then
    echo "::error title=ci-build::no device given"
    exit 1
fi

state=.ci-overlay
logdir=logs
logfile="$logdir/$device.log"
mkdir -p "$logdir"
: > "$logfile"

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

summary() {
    [ -n "$GITHUB_STEP_SUMMARY" ] || return 0
    printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
}

mins() { echo "$(( $1 / 60 ))m $(( $1 % 60 ))s"; }

# one phase of the build: its output goes to the log file and into a collapsed
# group, and the line after the group says how it went without being folded away
run() {
    local label="$1"
    shift

    local start=$SECONDS rc=0
    echo "::group::$label"
    "$@" 2>&1 | tee -a "$logfile" || rc=$?
    echo "::endgroup::"

    if [ "$rc" -eq 0 ]; then
        echo "--> $label: ok ($(mins $((SECONDS - start))))"
    else
        echo "--> $label: FAILED with $rc ($(mins $((SECONDS - start))))"
    fi
    return "$rc"
}

# the lines worth looking at out of a log nobody can read in full
errors() {
    grep -aE '^(make(\[[0-9]+\])?: \*\*\*|ERROR:|Error:|[^ ]+: error:|.*\] Error [0-9]+)' \
        "$logfile" | grep -av 'Error 1 (ignored)' | tail -n 25
}

# a workflow annotation is one line and % \r \n carry meaning in it
annotate() {
    printf '::error title=Build failed: %s::%s\n' "$device" \
        "$(printf '%s' "$1" | tr -d '\r' | tr '\n' ' ' | sed 's|%|%25|g' | cut -c1-500)"
}

echo "Device:  $device"
echo "Overlay: ${overlay:-openwrt-base only}"
echo "Clean:   $([ -n "$clean" ] && echo 'yes, the overlay changed' || echo no)"
echo "Log:     $logfile"

export DEVICE="$device" OVERLAY="$overlay" CLEAN="$clean"

started=$SECONDS
rc=0

run "Download the sources" ./build.sh make download -j8 || rc=$?
find openwrt/dl -size -1024c -exec rm -f {} \; 2>/dev/null || true

# the tree is set up now, do not undo it again for the build itself
export CLEAN=

if [ "$rc" -eq 0 ]; then
    run "Build $device with -j$(nproc)" ./build.sh make -j"$(nproc)" || rc=$?

    # A parallel build that fails may just have lost a race (tools/liblzo has),
    # so it is worth one serial retry - and with V=s, because the second
    # failure is the one that has to be diagnosed. Only what the first pass left
    # undone is rebuilt, so the verbose log stays about the breakage.
    if [ "$rc" -ne 0 ]; then
        echo "::warning title=Retrying $device::the parallel build failed with $rc, retrying with -j1 V=s"
        rc=0
        run "Retry $device with -j1 V=s" ./build.sh make -j1 V=s || rc=$?
    fi
fi

elapsed=$((SECONDS - started))

if [ "$rc" -ne 0 ]; then
    found=$(errors || true)

    echo "::group::Why $device failed"
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
    else
        echo "No error line recognised, the last 200 lines of the log:"
        tail -n 200 "$logfile"
    fi
    echo "::endgroup::"

    # outside the group as well, so it is the last thing the step prints
    echo
    echo "$device FAILED after $(mins "$elapsed"); the full log is in the $device-build-log artifact"
    printf '%s\n' "$found" | tail -n 5

    annotate "${found:-see the $device-build-log artifact}"
    summary "| \`$device\` | ${overlay:-base} | failed | $(mins "$elapsed") |"
    exit "$rc"
fi

profile=$(sed -n 's|^CONFIG_TARGET_PROFILE="DEVICE_\(.*\)"$|\1|p' openwrt/.config)

echo "::group::Images built for $device"
images=$(ls -lh openwrt/bin/targets/*/*/*"$profile"* 2>/dev/null || true)
printf '%s\n' "${images:-none found for profile ${profile:-<unknown>}}"
echo "::endgroup::"

count=$(ls openwrt/bin/targets/*/*/*"$profile"* 2>/dev/null | wc -l)
echo
echo "$device built in $(mins "$elapsed") as $profile, $count files"
summary "| \`$device\` | ${overlay:-base} | $profile, $count files | $(mins "$elapsed") |"
