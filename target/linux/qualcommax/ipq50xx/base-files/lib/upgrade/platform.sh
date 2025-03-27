PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1

RAMFS_COPY_BIN='dumpimage fw_printenv fw_setenv head'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock'

platform_check_image() {
	return 0;
}

glinet_validate_firmware() {
	local type='67'
	local ubi_magic='55 42 49 23'
	local img_magic='d0 0d fe ed'
	local sys_magic='73 79 73 75'

	# ubi type firmware
	local is_ubi=$( hexdump -C -n 4 "$1" | grep "$ubi_magic" | wc -c )
	if [ ${is_ubi} == ${type} ]; then
		echo "ubi"
		return
	fi
	# img type firmware
	local is_fit=$( hexdump -C -n 4 "$1" | grep "$img_magic" | wc -c )
	if [ ${is_fit} == ${type} ]; then
		echo "fit"
		return
	fi
	# sysupgrade-tar type firmware
	local is_sys=$( hexdump -C -n 4 "$1" | grep "$sys_magic" | wc -c )
	if [ ${is_sys} == ${type} ]; then
		echo "sys"
		return
	fi
	# Invalid firmware
	echo "error"
}

glinet_do_fit_upgrade() {
	echo -n "fit: Extract [ FIT IMAGE ] -x-x-> [ ubi.bin ] ... "
	local ubi=/tmp/ubi.bin
	local part=$(dumpimage -l /tmp/firmware.bin | grep -o "Image [0-9] (ubi)" | cut -f2 -d" ")

	local ubibin=$( dumpimage -T flat_dt -p ${part} -o "$ubi"  $1 )
	if [ -s "$ubi" ]; then
		echo "[ OK ]"
		local ubiMd5=$(cat $ubi | md5sum | cut -f1 -d" ")
		local ubi_size=$( cat "$ubi" | wc -c )
		echo -n "fit-copy: [ ubi.bin ] -c-c-> [ firmware.bin ] ... "
		mv "$ubi" "$1"
		local firmMd5=$(cat $1 | md5sum | cut -f1 -d" ")
		local firm_size=$( cat $1 | wc -c )
		if [ ${firm_size} -eq ${ubi_size} ] && [ "$ubiMd5" = "$firmMd5" ]; then
			echo "[ OK ]"
			echo "fit-copy: Copied "$firm_size" / "$ubi_size" bytes into firmware.bin"
			echo "fit-copy: MD5 CHECK: [ OK ]"
			echo "$ubiMd5 <=> $firmMd5"
			echo "fit: Successfully Extracted UBI from FIT IMAGE"
			echo "fit: Proceeding with sysupgrade .."
			nand_do_upgrade "$1"
			return
		fi
		echo "[ FAILED ] !!"
		echo "fit-copy: Copied "$firm_size" / "$ubi_size" bytes into firmware.bin"
		echo "ERROR: Failed to Copy UBI into firmware.bin !!"
		echo "fit: Terminating sysupgrade .."
		exit 1
	fi
	echo "[ FAILED ] !!"
	echo "fit-extract: Failed to Create Temp File ubi.bin !!"
	echo "ERROR: Failed to Extract UBI from FIT IMAGE !!"
	echo "fit: Terminating sysupgrade .."
	exit 1
}

glinet_do_ubi_upgrade() {
	echo -n "ubi: Removing Metadata Trailer from the UBI Volume ... "

	local metadata=$(fwtool -q -t -i /dev/null "$1")
	if [ -s $1 ]; then
		echo "[ OK ]"
		echo "ubi-meta: Successfully Removed Metadata from UBI Volume"
		echo "ubi: Proceeding with sysupgrade .."
		nand_do_upgrade "$1"
		return
	fi
	echo "[ FAILED ] !!"
	echo "ubi-meta: Cannot remove Metadata, the Files is Empty !!"
	echo "ERROR: Failed to Remove Metadata Trailer from UBI Volume !!"
	echo "ubi: Terminating sysupgrade .."
	exit 1
}

platform_do_upgrade() {
	case "$(board_name)" in
	glinet,gl-b3000)
		CI_UBIPART="rootfs"
		echo -n "Validating Firmware ... "
		case $(glinet_validate_firmware $1) in
		ubi)
			echo "[ OK ]"
			echo "ubi-main: Firmware is Valid: ubi"
			echo "ubi-main: Upgrading Firmware via [ UBI BIN ]"
			glinet_do_ubi_upgrade $1
			;;
		fit)
			echo "[ OK ]"
			echo "fit-main: Firmware is Valid: fit"
			echo "fit-main: Upgrading Firmware via [ FIT IMAGE ]"
			glinet_do_fit_upgrade $1
			;;
		sys)
			echo "[ OK ]"
			echo "sys-main: Firmware is Valid: sysupgrade-tar"
			echo "sys-main: Upgrading Firmware via [ SYSUPGRADE-TAR ]"
			nand_do_upgrade $1
			;;
		*)
			echo "[ FAILED ] !!"
			echo "main: Firmware Validation Failed !!"
			echo "main: Terminating sysupgrade .."
			exit 1
			;;
		esac
		;;
	jdcloud,re-cs-03)
		CI_KERNPART="0:HLOS"
		CI_ROOTPART="rootfs"
		emmc_do_upgrade "$1"
		;;
	linksys,mx2000|\
	linksys,mx5500)
		boot_part="$(fw_printenv -n boot_part)"
		if [ "$boot_part" -eq "1" ]; then
			fw_setenv boot_part 2
			CI_KERNPART="alt_kernel"
			CI_UBIPART="alt_rootfs"
		else
			fw_setenv boot_part 1
			CI_UBIPART="rootfs"
		fi
		fw_setenv boot_part_ready 3
		fw_setenv auto_recovery yes
		nand_do_upgrade "$1"
		;;
	*)
		default_do_upgrade "$1"
		;;
	esac
}

platform_copy_config() {
	case "$(board_name)" in
	jdcloud,re-cs-03)
		emmc_copy_config
		;;
	esac
	return 0;
}
