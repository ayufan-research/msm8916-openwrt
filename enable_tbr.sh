#!/bin/bash
# enable_tbr.sh
# Drops the deprecated MiFi-style device support (MF68E, M9S) from TBR/ into
# the build tree, so those devices can be built again without hand-editing any
# tracked file. Run it before the msm89xx/packages directories are moved into
# the OpenWrt tree. See TBR/readme.md.
#
# Usage:
#   ./enable_tbr.sh            # copy TBR bits into place
#   ./enable_tbr.sh --disable  # remove them again
set -e

cd "$(dirname "$0")"

for dir in TBR/packages TBR/patches TBR/image packages msm89xx/patches msm89xx/image; do
    if [ ! -d "$dir" ]; then
        echo "Error: $dir not found - run this from the repository before the"
        echo "       msm89xx/packages directories are moved into the OpenWrt tree"
        exit 1
    fi
done

TBR_PACKAGES=$(cd TBR/packages && ls -d */ | tr -d /)
TBR_PATCHES=$(cd TBR/patches && ls *.patch)
TBR_DEVICES=$(cd TBR/image && ls *.mk)
TBR_DIFFCONFIGS=$(cd TBR && ls diffconfig_*)

if [ "$1" = "--disable" ]; then
    echo "Removing TBR device support from the build tree..."
    for pkg in $TBR_PACKAGES; do rm -rf "packages/$pkg"; done
    for patch in $TBR_PATCHES; do rm -f "msm89xx/patches/$patch"; done
    for mk in $TBR_DEVICES; do rm -f "msm89xx/image/$mk"; done
    for cfg in $TBR_DIFFCONFIGS; do rm -f "$cfg"; done
    echo "TBR device support removed"
    exit 0
fi

if [ -n "$1" ]; then
    echo "Error: unknown argument '$1' (expected nothing or --disable)"
    exit 1
fi

echo "Enabling TBR device support (MF68E, M9S)..."

# Packages: configs, display manager and its kernel module
for pkg in $TBR_PACKAGES; do
    rm -rf "packages/$pkg"
    cp -a "TBR/packages/$pkg" packages/
    echo "  package  packages/$pkg"
done

# Kernel patches: device trees, each registering its own dtb in the qcom Makefile
for patch in $TBR_PATCHES; do
    cp -a "TBR/patches/$patch" msm89xx/patches/
    echo "  patch    msm89xx/patches/$patch"
done

# Device definitions: picked up by the devices-*.mk wildcard in msm8916.mk
for mk in $TBR_DEVICES; do
    cp -a "TBR/image/$mk" msm89xx/image/
    echo "  devices  msm89xx/image/$mk"
done

# Build configs, next to the ones of the supported devices
for cfg in $TBR_DIFFCONFIGS; do
    cp -a "TBR/$cfg" "./$cfg"
    echo "  config   ./$cfg"
done

echo "TBR device support enabled - build with diffconfig_m9s or diffconfig_mf68e"
