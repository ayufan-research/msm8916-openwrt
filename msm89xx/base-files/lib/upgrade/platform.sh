. /lib/upgrade/emmc.sh

platform_check_image() {
	local board_dir
	board_dir=$(tar tf "$1" 2>/dev/null | grep -m 1 '^sysupgrade-.*/$') || return 1
	board_dir=${board_dir%/}
	tar tf "$1" "${board_dir}/kernel" >/dev/null 2>/dev/null || return 1
	tar tf "$1" "${board_dir}/root" >/dev/null 2>/dev/null || return 1
	return 0
}

msm8916_do_upgrade() {
	local tar_file="$1"
	local kernel_dev rootfs_dev rootfs_data_dev board_dir

	kernel_dev=$(find_mmc_part "boot")
	rootfs_dev=$(find_mmc_part "rootfs")
	rootfs_data_dev=$(find_mmc_part "rootfs_data")

	[ -n "$kernel_dev" ] || { echo "boot partition not found"; exit 1; }
	[ -n "$rootfs_dev" ] || { echo "rootfs partition not found"; exit 1; }

	board_dir=$(tar tf "$tar_file" | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	echo "Flashing kernel to $kernel_dev"
	tar xf "$tar_file" "${board_dir}/kernel" -O > "$kernel_dev"

	echo "Flashing rootfs to $rootfs_dev"
	tar xf "$tar_file" "${board_dir}/root" -O > "$rootfs_dev"

	if [ -z "$UPGRADE_BACKUP" ] && [ -n "$rootfs_data_dev" ]; then
		dd if=/dev/zero of="$rootfs_data_dev" bs=512 count=8
	fi

	sync
	umount -a
	reboot -f
}

platform_copy_config() {
	local rootfs_data_dev
	rootfs_data_dev=$(find_mmc_part "rootfs_data")
	[ -n "$rootfs_data_dev" ] || return

	mkfs.ext4 -F -L rootfs_data -O ^has_journal "$rootfs_data_dev" >/dev/null 2>&1
	mkdir -p /tmp/new_root
	mount -t ext4 "$rootfs_data_dev" /tmp/new_root && {
		cp "$UPGRADE_BACKUP" "/tmp/new_root/$BACKUP_FILE"
		umount /tmp/new_root
	}
}

platform_do_upgrade() {
	msm8916_do_upgrade "$1"
}
