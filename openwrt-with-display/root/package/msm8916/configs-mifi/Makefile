include $(TOPDIR)/rules.mk

PKG_NAME:=configs-mifi
PKG_VERSION:=1.0

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=Utilities
  CATEGORY:=Utilities
  TITLE:=Default Settings For MiFis
  DEPENDS:=+PACKAGE_luci:luci-proto-modemmanager +ledcontrol +kmod-button-hotplug
endef

# Optional description
define Package/$(PKG_NAME)/description
Tweaks and defaults for MiFis, including cleanup of problematic APK feeds and LuCI battery widget.
endef

define Build/Configure
endef

define Build/Compile
endef

# The defaults, the power button handler and the two LED hotplug scripts are
# not here: they are the mifi versions of paths the target base-files already
# fills, and two packages cannot own one path ("trying to overwrite ... owned
# by base-files"). They live in openwrt-with-display's own
# target/linux/msm89xx/base-files instead, which is copied over openwrt-base's
# and is part of the base-files package rather than a second owner of the path.
define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/root/
	$(INSTALL_BIN) ./files/luci-app-tailscale*.apk $(1)/root/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/admin_status/index
	$(INSTALL_DATA) ./files/battery.htm $(1)/usr/lib/lua/luci/view/admin_status/index/20_battery.htm

	$(INSTALL_DIR) $(1)/etc/hotplug.d/button
	$(INSTALL_DATA) ./files/hotplugs/50-battery-show $(1)/etc/hotplug.d/button/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/battery-monitor.init $(1)/etc/init.d/battery-monitor
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
set -e
FILE="/etc/apk/repositories.d/distfeeds.list"
ROOT="$${IPKG_INSTROOT:-/}"
TARGET_FILE="$$ROOT$$FILE"

if [ -f "$$TARGET_FILE" ]; then
    sed -i '\|/targets/msm89xx/msm8916/packages|d' "$$TARGET_FILE" || true
fi

exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
