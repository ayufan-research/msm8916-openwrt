# openwrt-with-display - MF68E and M9S

These files are no longer part of the default build, but they still work. They
support MiFi-style devices (MF68E, M9S) with displays, battery monitoring and
power button handling.

## How to use

This directory is an overlay on top of `openwrt-base`, laid out the same way:
`root/` is copied into the OpenWrt checkout, `patches/` (currently empty) would
be applied on top of it, `configs/` holds the device configs. Because the
configs live here, asking for one of them applies this overlay:

```sh
.github/dev/setup.sh --config m9s openwrt
```

`--overlay` applies it regardless of the config. Or let `build.sh` do all of
it:

```sh
./build.sh --device m9s
```

In GitHub Actions, pick `m9s` or `mf68e` as the device in `build.yml`; nothing
else is needed, the config brings the overlay along.

## Contents

| Path | Contents |
| --- | --- |
| `root/package/msm8916/` | `configs-mifi` (battery monitoring and its LuCI widget, prebuilt Tailscale APK), `ledcontrol` (sysfs LED helper the hotplug scripts call), `router-display` (GC9107 SPI display manager with boot/shutdown logos), `fbtft-gc9107` (framebuffer kernel module), `rootfs-resizer` |
| `root/target/linux/msm89xx/base-files/` | The mifi versions of four paths: `99-default-config` (the UCI defaults, which enable WiFi on top of what `openwrt-base` sets), `etc/rc.button/power` (double-press to power off) and the two LED hotplug scripts, which drive the bi-colour LEDs through `ledcontrol` where `openwrt-base` writes single-colour sysfs LEDs directly. They are base-files rather than package files because `openwrt-base` already fills three of those paths from its own base-files, and two packages cannot own one path. This overlay is copied over `openwrt-base`, so its versions win; a dongle build re-copies `openwrt-base` and gets the originals back. |
| `root/target/linux/msm89xx/patches/` | MF68E and M9S device trees plus the `fb_gc9107` fbtft driver. Each device tree patch registers its own dtb in the kernel's `qcom/Makefile`, so it applies cleanly next to the patches of the supported devices. |
| `root/target/linux/msm89xx/image/devices-mifi.mk` | `generic-mf68e` and `generic-m9s` device definitions, picked up by the `devices-*.mk` wildcard include in `msm8916.mk` |
| `reference/` | Not used by the build: the old `git apply` style mac80211 patch (superseded by `openwrt-base/patches/`) and the `qcom-memshare` kernel patch, kept for reference only. |

| `configs/` | `diffconfig_m9s` and `diffconfig_mf68e` |
