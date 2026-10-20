# TBR - Deprecated Device Support (MF68E, M9S)

These files were removed from the main build but are kept here so the devices
can still be built. They support MiFi-style devices (MF68E, M9S) with displays,
battery monitoring and power button handling.

## How to enable

From the repository root:

```sh
./enable_tbr.sh
```

That copies everything into place; `./enable_tbr.sh --disable` removes it again.
Nothing tracked by git is edited, and the copied paths are gitignored, so the
working tree stays clean either way.

Then build as usual, with `diffconfig_m9s` or `diffconfig_mf68e`:

```sh
cd devenv
docker compose run --rm builder
cp /repo/diffconfig_m9s .config
make defconfig
make -j$(nproc)
```

In GitHub Actions, pick `m9s`, `mf68e` or `all+tbr` as the device in
`build.yml` - the workflow runs `enable_tbr.sh` for those jobs itself.

## Layout

| Path | Copied to | Contents |
| --- | --- | --- |
| `packages/` | `packages/` | `configs-mifi` (UCI defaults, LED hotplugs, battery monitoring, power button, prebuilt Tailscale APK), `ledcontrol` (sysfs LED helper the hotplug scripts call), `router-display` (GC9107 SPI display manager with boot/shutdown logos), `fbtft-gc9107` (framebuffer kernel module), `rootfs-resizer` |
| `patches/` | `msm89xx/patches/` | MF68E and M9S device trees plus the `fb_gc9107` fbtft driver. Each device tree patch registers its own dtb in the kernel's `qcom/Makefile`, so they apply cleanly next to the patches of the supported devices. |
| `image/devices-mifi.mk` | `msm89xx/image/` | `generic-mf68e` and `generic-m9s` device definitions, picked up by the `devices-*.mk` wildcard include in `msm8916.mk` |
| `diffconfig_m9s`, `diffconfig_mf68e` | repository root | Build configs for the two devices |

`reference/` is not used by the build: it holds the old `git apply` style
mac80211 patch (superseded by `apply_patches.sh`) and the `qcom-memshare`
kernel patch, kept for reference only.
