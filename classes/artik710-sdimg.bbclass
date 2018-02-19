inherit image_types logging

#
# Create an image that can by written onto a SD card using dd.
#

# Set initramfs extension
KERNEL_INITRAMFS ?= ""

do_image[depends] = " \
			parted-native:do_populate_sysroot \
			mtools-native:do_populate_sysroot \
			dosfstools-native:do_populate_sysroot \
			e2fsprogs-native:do_populate_sysroot \
			virtual/kernel:do_deploy \
			u-boot:do_deploy \
			"


SKIP_BOOT_SIZE = "4"
BOOT_SIZE = "32"
MODULE_SIZE = "32"


# bl1 for SD and eMMC boot (a.k.a. AP Boot ROM: AP_BL1, in our case bl1-emmcboot.img and bl1-sdboot.img)
# bl2 for SD and eMMC boot (a.k.a. AP RAM Firmware: AP_BL2, in our case fip-loader-emmc.img and fip-loader-sd.img)
# bl31 + bl32 (a.k.a. EL3 Runtime Firmware or SoC AP firmware or EL3 monitor firmware: AP_BL31 + Secure-EL1 Payload (SP): AP_BL32, in our case the bundled image fip-secure.img consisting of the ATF + secure OS OPTEE)
# bl33 (a.k.a. AP Normal World Firmware: AP_BL33, in our case the uboot binary transformed to a FIP - Firmware Image Package - and then into a nexell image using SECURE_BINGEN)
BL1_EMMC = "bl1-emmcboot.img"
BL1_SD = "bl1-sdboot.img"
BL2_EMMC = "fip-loader-emmc.img"
BL2_SD = "fip-loader-sd.img"
BL31 = "fip-secure.img"
BL33 = "fip-nonsecure.img"
PARTMAP = "partmap_emmc_ota.txt"

# Offsets for generating the final image
BL1_OFFSET = "1"
BL2_OFFSET = "129"
TZSW_OFFSET = "769"
UBOOT_OFFSET = "3841"
UBOOT_PARAMS_OFFSET = "5889"


# U-Boot
UBOOT_SUFFIX ?= "bin"
UBOOT_SYMLINK ?= "u-boot-${MACHINE}.${UBOOT_SUFFIX}"

# SD card image name
SDIMG_EXT ?= "artik710-sd.img"
SDIMG = "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.${SDIMG_EXT}"
EASY_FIND_SDIMG = "${DEPLOY_DIR_IMAGE}/${IMAGE_BASENAME}.${SDIMG_EXT}"

IMAGE_CMD_artik710-sdimg () {
	rm -f ${DEPLOY_DIR_IMAGE}/*.${SDIMG_EXT}
	ln -rsf ${SDIMG} ${EASY_FIND_SDIMG}
	
	bbdebug 1 "Creating ext4 Boot image"
	rm -f ${WORKDIR}/boot.img
	rm -rf ${WORKDIR}/boot
	
	# stage up the boot partition
	install -d ${WORKDIR}/boot
	install ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} ${WORKDIR}/boot
	if test -n "${KERNEL_DEVICETREE}"; then
		for DT in ${KERNEL_DEVICETREE}
		do
			DTFN=$(basename ${DT})
			install ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${DTFN} ${WORKDIR}/boot/${DTFN}
		done
	fi
	echo "${IMAGE_NAME}-${IMAGEDATESTAMP}" > ${WORKDIR}/boot/image-version-info
	install ${DEPLOY_DIR_IMAGE}/uInitrd ${WORKDIR}/boot
	
	# Make boot image
	BOOT_SIZE_BLOCKS=$(expr ${BOOT_SIZE} \* 256)
	bbdebug 1 " BOOT_SIZE_BLOCKS=${BOOT_SIZE_BLOCKS}"
	mkfs.ext4 -L "boot" -b 4096 -d ${WORKDIR}/boot ${WORKDIR}/boot.img ${BOOT_SIZE_BLOCKS}
	
	bbdebug 1 "Creating ext4 Modules image"
	rm -f ${WORKDIR}/modules.img
	rm -rf ${WORKDIR}/modules

	# Stage up the modules partition
	install -d ${WORKDIR}/modules
	tar zxf ${DEPLOY_DIR_IMAGE}/modules-${MACHINE}.tgz -C ${WORKDIR}/modules

	MODULES_SIZE_BLOCKS=$(expr ${MODULE_SIZE} \* 1024 / 4)
	bbdebug 1 " MODULE_SIZE_BLOCKS=${MODULES_SIZE_BLOCKS}"
	mkfs.ext4 -L "modules" -b 4096 -d ${WORKDIR}/modules/lib/modules ${WORKDIR}/modules.img ${MODULES_SIZE_BLOCKS}

	# Set up fuse fs workdir
	install -d ${WORKDIR}/rootfs_sd

	# Set up fstab
	bbdebug 1 "Setting up fstab in rootfs"
	rm -f ${WORKDIR}/rootfs.tar.gz
	install -d ${WORKDIR}/rootfs_sd

	echo '/dev/mmcblk0p7  /             ext4    errors=remount-ro,noatime,nodiratime    0   1' >  ${IMAGE_ROOTFS}/etc/fstab
	echo '/dev/mmcblk0p2  /boot         ext4    defaults,ro                             0   0' >> ${IMAGE_ROOTFS}/etc/fstab
	echo '/dev/mmcblk0p5  /lib/modules  ext4    defaults,ro                             0   0' >> ${IMAGE_ROOTFS}/etc/fstab		
	touch ${IMAGE_ROOTFS}/.need_sd_resize

	OLD_DIR=${PWD}	
	cd ${IMAGE_ROOTFS}
	tar czf ${WORKDIR}/rootfs_sd/rootfs.tar.gz ./*
	cd ${OLD_DIR}

	# Create sdfuse rootfs
	bbdebug 1 "Copying images into fuse rootfs and creating image"
	install ${DEPLOY_DIR_IMAGE}/bl1-emmcboot.img \
		${DEPLOY_DIR_IMAGE}/fip-loader-emmc.img \
		${DEPLOY_DIR_IMAGE}/fip-secure.img \
		${DEPLOY_DIR_IMAGE}/fip-nonsecure.img \
		${DEPLOY_DIR_IMAGE}/flag.img \
		${WORKDIR}/boot.img \
		${WORKDIR}/modules.img \
		${WORKDIR}/rootfs_sd
	install ${DEPLOY_DIR_IMAGE}/${PARTMAP} ${WORKDIR}/rootfs_sd/partmap_emmc.txt
	install ${DEPLOY_DIR_IMAGE}/params_emmc.bin ${WORKDIR}/rootfs_sd/params.bin

	SD_ROOTFS_SIZE_KB=$(du -bks ${WORKDIR}/rootfs_sd | awk '{print $1}')
	bbdebug 1 " SD_ROOTFS_SIZE_KB=${SD_ROOTFS_SIZE_KB}"
	SD_ROOTFS_SIZE_BLOCKS=$(expr ${SD_ROOTFS_SIZE_KB} / 4)
	bbdebug 1 " SD_ROOTFS_SIZE_BLOCKS=${SD_ROOTFS_SIZE_BLOCKS}"
	SD_ROOTFS_SIZE_SECTOR=$(expr ${SD_ROOTFS_SIZE_KB} \* 2)
	bbdebug 1 " SD_ROOTFS_SIZE_SECTOR=${SD_ROOTFS_SIZE_SECTOR}"
	mkfs.ext3 -L "rootfs" -b 4096 -d ${WORKDIR}/rootfs_sd ${WORKDIR}/rootfs.img ${SD_ROOTFS_SIZE_BLOCKS}

	bbdebug 1 "Calculating partitions"

	BOOT_SIZE_SECTOR=$(expr ${BOOT_SIZE} \* 2048)
	bbdebug 1 " BOOT_SIZE_SECTOR=${BOOT_SIZE_SECTOR}"
	MODULE_SIZE_SECTOR=$(expr ${MODULE_SIZE} \* 2048)
	bbdebug 1 " MODULE_SIZE_SECTOR=${MODULE_SIZE_SECTOR}"

	#Partition For Non-OTA
	BOOT_START_SECTOR=$(expr ${SKIP_BOOT_SIZE} \* 2048)
	bbdebug 1  " BOOT_START_SECTOR=${BOOT_START_SECTOR}"
	BOOT_END_SECTOR=$(expr $BOOT_START_SECTOR + $BOOT_SIZE_SECTOR - 1)
	bbdebug 1 " BOOT_END_SECTOR=${BOOT_END_SECTOR}"
	MODULES_START_OFFSET=$(expr ${BOOT_SIZE} + ${SKIP_BOOT_SIZE})
	bbdebug 1 " MODULES_START_OFFSET=${MODULES_START_OFFSET}"
	MODULES_START_SECTOR=$(expr $BOOT_END_SECTOR + 1)
	bbdebug 1 " MODULES_START_SECTOR=${MODULES_START_SECTOR}"
	MODULES_END_SECTOR=$(expr $MODULES_START_SECTOR + $MODULE_SIZE_SECTOR - 1)
	bbdebug 1 " MODULE_END_SECTOR=${MODULE_END_SECTOR}"
	ROOTFS_START_SECTOR=$(expr $MODULES_END_SECTOR + 1)
	bbdebug 1 " ROOTFS_START_SECTOR=${ROOTFS_START_SECTOR}"
	SDIMG_SIZE_SECTOR=$(expr ${ROOTFS_START_SECTOR} \+ ${SD_ROOTFS_SIZE_KB} \* 2)
	bbdebug 1 " SDIMG_SIZE_SECTOR=${SDIMG_SIZE_SECTOR}"
	SDIMG_SIZE_KB=$(expr ${SDIMG_SIZE_SECTOR} / 2)
	bbdebug 1 " SDIMG_SIZE_KB=${SDIMG_SIZE_KB}"

	#Partition For OTA
	#EXT_PART_PAD=2048
	#FLAG_START_SECTOR_OTA=$(expr ${SKIP_BOOT_SIZE} \* 2048)
	#bbdebug 1 " FLAG_START_SECTOR_OTA=${FLAG_START_SECTOR_OTA}"
	#FLAG_SIZE_SECTOR=$(expr 128 \* 2)
	#bbdebug 1 " FLAG_SIZE_SECTOR=${FLAG_SIZE_SECTOR}"
	#FLAG_END_SECTOR_OTA=$(expr $FLAG_START_SECTOR_OTA + $FLAG_SIZE_SECTOR - 1)
	#bbdebug 1 " FLAG_END_SECTOR_OTA=${FLAG_END_SECTOR_OTA}"
	#BOOT_START_SECTOR_OTA=$(expr $FLAG_END_SECTOR_OTA + 1)
	#bbdebug 1 " BOOT_START_SECTOR_OTA=${BOOT_START_SECTOR_OTA}"
	#BOOT_END_SECTOR_OTA=$(expr $BOOT_START_SECTOR_OTA + $BOOT_SIZE_SECTOR - 1)
	#bbdebug 1 " BOOT_END_SECTOR_OTA=${BOOT_END_SECTOR_OTA}"
	#BOOT0_START_SECTOR_OTA=$(expr $BOOT_END_SECTOR_OTA + 1)
	#bbdebug 1 " BOOT0_START_SECTOR_OTA=${BOOT0_START_SECTOR_OTA}"
	#BOOT0_END_SECTOR_OTA=$(expr $BOOT0_START_SECTOR_OTA + $BOOT_SIZE_SECTOR - 1)
	#bbdebug 1 " BOOT0_END_SECTOR_OTA=${BOOT0_END_SECTOR_OTA}"
	#EXT_START_SECTOR_OTA=$(expr $BOOT0_END_SECTOR_OTA + 1)
	#bbdebug 1 " EXT_START_SECTOR_OTA=${EXT_START_SECTOR_OTA}"
	#MODULES_START_SECTOR_OTA=$(expr $EXT_START_SECTOR_OTA + $EXT_PART_PAD)
	#bbdebug 1 " MODULES_START_SECTOR_OTA=${MODULES_START_SECTOR_OTA}"
	#MODULES_END_SECTOR_OTA=$(expr $MODULES_START_SECTOR_OTA + $MODULE_SIZE_SECTOR - 1)
	#bbdebug 1 " MODULES_END_SECTOR_OTA=${MODULES_END_SECTOR_OTA}"
	#MODULES0_START_SECTOR_OTA=$(expr $MODULES_END_SECTOR_OTA + $EXT_PART_PAD + 1)
	#bbdebug 1 " MODULES0_START_SECTOR_OTA=${MODULES0_START_SECTOR_OTA}"
	#MODULES0_END_SECTOR_OTA=$(expr $MODULES0_START_SECTOR_OTA + $MODULE_SIZE_SECTOR - 1)
	#bbdebug 1 " MODULES0_END_SECTOR_OTA=${MODULES0_END_SECTOR_OTA}"
	#ROOTFS_START_SECTOR_OTA=$(expr $MODULES0_END_SECTOR_OTA + $EXT_PART_PAD + 1)
	#bbdebug 1 " ROOTFS_START_SECTOR_OTA=${ROOTFS_START_SECTOR_OTA}"
	#SDIMG_SIZE_SECTOR=$(expr ${ROOTFS_START_SECTOR_OTA} \+ ${SD_ROOTFS_SIZE_KB} \* 2)
	#bbdebug 1 " SDIMG_SIZE_SECTOR=${SDIMG_SIZE_SECTOR}"
	#SDIMG_SIZE_KB=$(expr ${SDIMG_SIZE_SECTOR} / 2)
	#bbdebug 1 " SDIMG_SIZE_KB=${SDIMG_SIZE_KB}"

	# Initialize sdcard image file
	bbdebug 1 "Zeroing image"
	dd if=/dev/zero of=${SDIMG} bs=512 count=0 seek=${SDIMG_SIZE_SECTOR}

	# Create partition table
	bbdebug 1 "Creating partition table"
	parted -s ${SDIMG} mklabel msdos

	##Create flag partition
	#bbdebug 1 " Creating flag partition ${FLAG_START_SECTOR_OTA} - ${FLAG_END_SECTOR_OTA}"
	#parted -s ${SDIMG} unit s mkpart primary ext2 ${FLAG_START_SECTOR_OTA} ${FLAG_END_SECTOR_OTA}

	# Create boot partition and mark it as bootable
	bbdebug 1 "Creating boot partition: ${BOOT_START_SECTOR} - ${BOOT_END_SECTOR}"
	parted -s ${SDIMG} unit s mkpart primary ext2 ${BOOT_START_SECTOR} ${BOOT_END_SECTOR}
	parted -s ${SDIMG} set 1 boot on

	##Create boot ota partition
	#bbdebug 1 " Creating ota boot partition: ${BOOT0_START_SECTOR_OTA} - ${BOOT0_END_SECTOR_OTA}"
	#parted -s ${SDIMG} unit s mkpart primary ext2 ${BOOT0_START_SECTOR_OTA} ${BOOT0_END_SECTOR_OTA}

	##Create extended partition
	#bbdebug 1 " Creating extended partition: ${EXT_START_SECTOR_OTA} - end"
	#parted -s ${SDIMG} -- unit s mkpart extended ${EXT_START_SECTOR_OTA} -1

	# Create modules partition
	bbdebug 1 "Creating modules partition: ${MODULES_START_SECTOR} - ${MODULES_END_SECTOR}"
	parted -s ${SDIMG} unit s mkpart primary ext2 ${MODULES_START_SECTOR} ${MODULES_END_SECTOR}

	## Create ota modules partition
	#bbdebug 1 "Creating ota modules partition: ${MODULES0_START_SECTOR_OTA} - ${MODULES0_END_SECTOR_OTA}"
	#parted -s ${SDIMG} unit s mkpart logical ext2 ${MODULES0_START_SECTOR_OTA} ${MODULES0_END_SECTOR_OTA}

	# Create rootfs partition to the end of disk
	bbdebug 1 "Creating RootFS partition: ${ROOTFS_START_SECTOR} - end"
	parted -s ${SDIMG} -- unit s mkpart primary ext2 ${ROOTFS_START_SECTOR} -1

	parted ${SDIMG} print

	ROOTFS_END_SECTOR=$(parted -s ${SDIMG} unit s print all | grep -e ' 3 ' | sed 's/[ \t]\+/ /g' | sed 's/^[ \t]\+//g' | cut -d" " -f3 | sed 's/s//g')
	ROOTFS_SIZE_BYTES=$(expr \( ${ROOTFS_END_SECTOR} \- ${ROOTFS_START_SECTOR} \) \* 512)
	bbdebug 1 " rootfs actual end sector: ${ROOTFS_END_SECTOR_OTA}, size ${ROOTFS_SIZE_BYTES} bytes"

	# Burn non-partition images
	bbdebug 1 "Burning non-partition images"
	dd if=${DEPLOY_DIR_IMAGE}/${BL1_SD} of=${SDIMG} bs=512 seek=${BL1_OFFSET} conv=notrunc 
	dd if=${DEPLOY_DIR_IMAGE}/${BL2_SD} of=${SDIMG} bs=512 seek=${BL2_OFFSET} conv=notrunc 
	dd if=${DEPLOY_DIR_IMAGE}/${BL31} of=${SDIMG} bs=512 seek=${TZSW_OFFSET} conv=notrunc 
	dd if=${DEPLOY_DIR_IMAGE}/${BL33} of=${SDIMG} bs=512 seek=${UBOOT_OFFSET} conv=notrunc 
	dd if=${DEPLOY_DIR_IMAGE}/params_recovery.bin of=${SDIMG} bs=512 seek=${UBOOT_PARAMS_OFFSET} conv=notrunc 

	# Burn Partitions
	bbdebug 1 "Burning partition images"
	#dd if=${DEPLOY_DIR_IMAGE}/flag.img of=${SDIMG} bs=512 conv=notrunc seek=${FLAG_START_SECTOR_OTA} 
	dd if=${WORKDIR}/boot.img of=${SDIMG} conv=notrunc seek=${BOOT_START_SECTOR} bs=512 count=${BOOT_SIZE_SECTOR} 
	#dd if=${WORKDIR}/boot.img of=${SDIMG} conv=notrunc seek=${BOOT0_START_SECTOR_OTA} bs=512 count=${BOOT_SIZE_SECTOR} 
	dd if=${WORKDIR}/modules.img of=${SDIMG} conv=notrunc seek=${MODULES_START_SECTOR} bs=512 count=${MODULE_SIZE_SECTOR} 
	#dd if=${WORKDIR}/modules.img of=${SDIMG} conv=notrunc seek=${MODULES0_START_SECTOR_OTA} bs=512 count=${MODULE_SIZE_SECTOR} 
	dd if=${WORKDIR}/rootfs.img of=${SDIMG} conv=notrunc seek=${ROOTFS_START_SECTOR} bs=512 
}
