![OpenWrt logo](https://raw.githubusercontent.com/openwrt/openwrt/refs/heads/main/include/logo.png)

Modern OpenWrt build targeting MSM8916 devices with full modem, USB gadget, and WiFi support.

## Table of Contents

- [About OpenWrt](#about-openwrt)
- [Supported Devices](#supported-devices)
- [Features](#features)
- [Repository Layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Building](#building)
- [Installation](#installation)
  - [Flashing from OEM Firmware](#flashing-from-oem-firmware)
  - [Accessing Boot Modes](#accessing-boot-modes)
- [Troubleshooting](#troubleshooting)
  - [No Network / Modem Stuck at Searching](#no-network--modem-stuck-at-searching)
- [Roadmap](#roadmap)
- [Credits](#credits)

---

## About OpenWrt

OpenWrt Project is a Linux operating system targeting embedded devices. Instead of trying to create a single, static firmware, OpenWrt provides a fully writable filesystem with package management. This frees you from the application selection and configuration provided by the vendor and allows you to customize the device through the use of packages to suit any application.

## Supported Devices

All devices use the Qualcomm MSM8916 SoC with 384 MB RAM and 4 GB eMMC.

- **UZ801v3** (`yiming-uz801v3`) -- USB dongle form factor.
- **UF02** (`generic-uf02`) -- USB dongle form factor, most likely with only asian bands. Can be somewhat changed via QPST and the `qcn` file from UZ801.

MF68E and M9S are no longer part of the default build. Their support lives in [openwrt-with-display](openwrt-with-display/readme.md), which is applied automatically when you build for `m9s` or `mf68e`.

## Features

### Working Components
- **Modem**: Fully functional with cellular connectivity
  - Rx/Tx statistics reported by the `qcom_bam_dmux` driver (patch `902`), so they show up in `ip -s link` and LuCI
- **WiFi**: Complete wireless support
- **USB Gadget Modes**: NCM, RNDIS, Mass Storage, ACM Shell
  - Configure via [UCI](packages/uci-usb-gadget/readme.md) or LuCI app
- **VPN Ready**: TUN driver and WireGuard pre-installed
- **LED Control**: Managed via `hotplug.d` scripts (sysfs-based, no extra packages)

### Storage & Recovery
- **SquashFS Root**: Compressed root filesystem
- **OverlayFS**: ext4 overlay partition for user data (formatted automatically via preinit)
- **Factory Reset**: `firstboot` mechanism enabled

### Additional Packages
- **Tailscale**: LuCI app available as standalone package (APK and IPK)

## Repository Layout

The repository holds OpenWrt tree overlays plus the patches that go on top of
the OpenWrt checkout. `.github/dev/setup.sh` copies and applies them, nothing
is built in place:

```
openwrt-base/                always applied
  root/                      copied into the OpenWrt checkout as-is
    target/linux/msm89xx/    the target: Makefile, kernel config and patches,
                             base-files, image recipes
    package/msm8916/         our packages
  patches/                   applied with patch -p1 in the checkout
  configs/                   diffconfig per device
openwrt-with-display/        the same three, for MF68E and M9S
.github/dev/Dockerfile       the build environment, declared once
.github/dev/setup.sh         copy the overlays, apply the patches, install a config
build.sh                     build the image and build OpenWrt in it (CI too)
```

An overlay owns its device configs, and the overlay follows the config:
`setup.sh --config m9s` finds `openwrt-with-display/configs/diffconfig_m9s` and
applies `openwrt-with-display` with it. Adding a device means a device tree
patch under `.../msm89xx/patches/`, a `Device/...` definition in `image/msm8916.mk`
(or a drop-in `image/devices-*.mk`), and a `configs/diffconfig_<device>` in the
overlay it belongs to.

## Prerequisites

- Docker installed on your system
- Basic knowledge of Linux command line
- For flashing: [edl tool](https://github.com/bkerler/edl)

## Building

### GitHub Actions (release builds)

`build.yml` defaults to the newest **OpenWrt 25.12.x** tag. Trigger it manually
from the Actions tab:

- **Build firmware**: `build.yml` — pick a device (`all` builds every config, including the ones [with a display](openwrt-with-display/readme.md)), an OpenWrt branch, tag or tag pattern (`v25.12.*` by default), and extra packages to build into the image; the image builder and the SDK are built too unless you turn them off
- **Release**: tick *Publish a GitHub release* and `build.yml` publishes one archive per device once the builds pass. The tag names what it is - the OpenWrt version plus the commit that built it, `v25.12.6-abb94ec` - with an optional suffix of your own and a *prerelease* checkbox

It builds every selected config in one job through `build.sh`, so the toolchain
is built once and CI and local builds share one container image. It uploads the
flashable images, the sysupgrade image, the package feed built with them, and
the image builder and SDK.

### Local (snapshot builds)

`build.sh` builds the container image, clones OpenWrt into `./openwrt`, applies
the overlays, installs the feeds and the device config, then builds. The
checkout stays on the host, so downloads and build artifacts survive between
runs. It needs a device, as `--device` or `$DEVICE`; `./build.sh --help` prints
the options and the devices the overlays carry.

```
./build.sh --device uz801             # build the images (OpenWrt main/snapshot)
./build.sh --device uz801 --shell     # shell in the tree instead of building
./build.sh -d uz801 make menuconfig   # or any other command, run in the tree
```

Other devices, and other OpenWrt versions:

```
./build.sh -d uf02
./build.sh -d m9s                                  # pulls in openwrt-with-display
OPENWRT_VERSION=v25.12.6 ./build.sh -d uz801
OPENWRT_VERSION='v25.12.*' ./build.sh -d uz801     # newest 25.12.x tag
```

Building a second device reuses the tree: the config is swapped, `make
defconfig` re-run, and the toolchain and staging directory stay, so only the
kernel and the images are rebuilt.

```
./build.sh -d uz801
./build.sh -d uf02             # same toolchain
./build.sh -d m9s --clean      # other overlay, undo first
```

`--clean` undoes the overlays in the checkout (the copied files are deleted and
the patched ones restored from git) and cleans the kernel so its patches are
re-applied; `dl/`, `.ccache/` and the build directories are left alone. It is
needed when the set of overlays changes, which is why `build.yml` passes it at
the point where it moves on to the devices with a display.

`build.sh` re-applies the overlays on every invocation, so changes under
`openwrt-base/` or `openwrt-with-display/` are picked up. An edited `.config`
survives as long as the device stays the same (`--force-config` replaces it).
Run `.github/dev/setup.sh --config <device> openwrt` by hand if you drive
`make` yourself.

> **Supported versions:** OpenWrt 25.12.x and current snapshots (kernel 6.12). OpenWrt 24.10.x (kernel 6.6) compiles but does not boot — the Makefile supports it via `KERNEL_FOR_24` (currently commented out) if someone wants to investigate further.

## Installation

### Flashing from OEM Firmware

1. **Install EDL tool**: https://github.com/bkerler/edl
2. **Enter EDL mode**:
   - **UZ801v3**: See [PostmarketOS wiki guide](https://wiki.postmarketos.org/wiki/Zhihe_series_LTE_dongles_(generic-zhihe)#How_to_enter_flash_mode)

3. **Backup original firmware**:
   ```
   edl rf backup.bin
   ```

4. **Flash OpenWrt**:
   ```
   ./openwrt-msm89xx-msm8916-*-flash.sh
   ```

   > The script flashes entirely via EDL (no fastboot step). It automatically backs up radio partitions, writes the new GPT, firmware, boot and rootfs, and restores the backed-up partitions.

### Accessing Boot Modes

#### UZ801v3
- **Fastboot mode**: Insert device while holding the button
- **EDL mode**: Boot to fastboot first, then execute: `fastboot oem reboot-edl`

#### UF02
- **Fastboot mode**:
  - From OEM: `adb reboot bootloader`.
  - From OpenWrt: Enter `edl` and erase boot partition (`edl e boot`).
- **EDL mode**:
  - From OEM: `adb reboot bootloader`, flash `lk2nd` aboot. Reboot pressing the button.
  - From OpenWrt: Insert device while holding the button.

## Troubleshooting

### No Network / Modem Stuck at Searching

The modem requires region-specific MCFG configuration files.

#### Extract MCFG from Your Firmware

1. **Dump modem partition**:
   ```
   edl r modem modem.bin
   ```

2. **Mount and navigate**:
   ```
   # Mount modem.bin (it's a standard Linux image)
   cd image/modem_pr/mcfg/configs/mcfg_sw/generic/
   ```

3. **Select your region**:
   - `APAC` - Asia Pacific
   - `CHINA` - China
   - `COMMON` - Generic/fallback
   - `EU` - Europe
   - `NA` - North America
   - `SA` - South America
   - `SEA` - South East Asia

4. **Locate your carrier's MCFG**: Navigate to your telco's folder and find `mcfg_sw.mbn`. If your carrier isn't listed, use a generic configuration from the `common` folder.

#### Apply the Configuration

**Transfer to device** (capitalization matters!):
   ```
   scp -O mcfg_sw.mbn root@192.168.1.1:/lib/firmware/MCFG_SW.MBN
   # ... and reboot the device ...
   ```

## Roadmap

- [ ] Custom package server for msm89xx/msm8916
  - Note: Target-specific modules may require building from source via `make menuconfig`
  - The target-specific APK feed is automatically removed on first boot (msm89xx is not on downloads.openwrt.org)
- [ ] Investigate `lpac` for eSIM support
- [x] Memory expansion: `kmod-zram` + `zram-swap` enabled on all devices

## Credits

- **[@ghosthgy](https://github.com/ghosthgy/openwrt-msm8916)** - Initial project foundation
- **[@lkiuyu](https://github.com/lkiuyu/immortalwrt)** - MSM8916 support, patches, and OpenStick feeds
- **[@Mio-sha512](https://github.com/Mio-sha512/OpenStick-Builder)** - USB gadget and firmware loader concepts
- **[@AlienWolfX](https://github.com/AlienWolfX/UZ801-USB_MODEM/wiki/Troubleshooting)** - Carrier policy troubleshooting guide
- **[@gw826943555](https://github.com/gw826943555/luci-app-tailscale) & [@asvow](https://github.com/asvow)** - Tailscale LuCI application
