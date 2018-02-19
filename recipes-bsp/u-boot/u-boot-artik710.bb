# Samsung Artik 710 u-boot

require recipes-bsp/u-boot/u-boot.inc

DEPENDS += "bc-native dtc-native mksinglebootloader-tools secure-boot-artik710"

DESCRIPTION = "u-boot which includes support for the Samsung Artik boards."
LICENSE = "GPLv2+"
LIC_FILES_CHKSUM = "file://Licenses/gpl-2.0.txt;md5=b234ee4d69f5fce4486a80fdaf4a4263"

PROVIDES += "u-boot"

SRCREV_artik710 = "860b3724b5ebb8c4b58c1cbec62f4ed27254f1da"
SRC_URI[md5sum] = "77b9b443803c11a20871a3c90d7b0b09"

#SRC_URI_artik710 = " \
#    git://github.com/HiZLabs/u-boot-artik.git;protocol=https;branch=A710_os_3.0.0 \
#    file://0001-artik710_raptor.h-Set-CONFIG_ROOT_PART-to-2.patch \
#    file://0002-compiler-gcc6.h-Add-support-for-GCC6.patch \
#    file://0003-artik710_raptor.h-Boot-partition-is-a-fat-one.patch \
#    file://0004-artik710_raptor.h-Use-rootwait.patch \
#    "

SRC_URI_artik710 = " \
    git://github.com/SamsungARTIK/u-boot-artik.git;protocol=https;branch=A710_os_3.0.0 \
    "
S = "${WORKDIR}/git"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(artik710)"

# Setup uboot environment for each flasher/non-flasher images
do_compile_append() {
    # Copied from build-artik/build_uboot.sh
    ENV_FILE=`find ${B} -name "env_common.o"`
    echo "Extracting params from $ENV_FILE"
    cp $ENV_FILE copy_env_common.o
    echo " copying objects"
    ${OBJCOPY} -O binary --only-section=.rodata.default_environment copy_env_common.o

    echo " translating line endings"
    tr '\0' '\n' < copy_env_common.o | grep '=' > default_envs.txt
    cp default_envs.txt default_envs.txt.orig
    tools/mkenvimage -s 16384 -o params.bin default_envs.txt

    # Generate recovery param
    echo " generating recovery param"
    sed -i -e 's/rootdev=.*/rootdev=1/g' default_envs.txt
    sed -i -e 's/bootcmd=run .*/bootcmd=run recoveryboot/g' default_envs.txt
    tools/mkenvimage -s 16384 -o params_recovery.bin default_envs.txt

    # Generate mmcboot param
    echo " generating mmcboot param"
    cp default_envs.txt.orig default_envs.txt
    sed -i -e 's/bootcmd=run .*/bootcmd=run mmcboot/g' default_envs.txt
    tools/mkenvimage -s 16384 -o params_emmc.bin default_envs.txt

    # Generate sd-boot param
    echo " generating sd-boot param"
    cp default_envs.txt.orig default_envs.txt
    sed -i -e 's/rootdev=.*/rootdev=1/g' default_envs.txt
    tools/mkenvimage -s 16384 -o params_sd.bin default_envs.txt

    # generate FIP (Firmware Image Package) (fip-nonsecure.bin) from the uboot binary
    echo " generating FIP"
    tools/fip_create/fip_create --dump --bl33 u-boot.bin fip-nonsecure.bin
    # generate nexell image (fip-nonsecure.img) from the FIP binary
    echo " generating secure bin"
    tools/nexell/SECURE_BINGEN -c ${BASE_MACH} -t 3rdboot -n ${S}/tools/nexell/nsih/raptor-64.txt -i ${B}/fip-nonsecure.bin -o ${B}/fip-nonsecure.img -l ${FIP_LOAD_ADDR} -e 0x00000000
}

do_singlebootloader() {
    if [ "${BOOTLOADER_SINGLEIMAGE}" = "1" ]; then
        bbdebug 1 "Creating single bootloader image..."
        fip_create --dump --bl2 ${DEPLOY_DIR_IMAGE}/${BL2_BIN} --bl31 ${DEPLOY_DIR_IMAGE}/${BL31_BIN} --bl32 ${DEPLOY_DIR_IMAGE}/${BL32_BIN} --bl33 ${B}/u-boot.bin ${B}/fip.bin
        gen_singleimage.sh -o ${B} -e ${DEPLOY_DIR_IMAGE}/${LLOADER_BIN} -f ${B}/fip.bin

        echo "BOOT_BINGEN -c ${BASE_MACH} -t 3rdboot -n ${NSIH_EMMC} -i ${B}/singleimage.bin -o ${B}/singleimage-emmcboot.bin -l ${BL2_LOAD_ADDR} -e ${BL2_JUMP_ADDR}"
        BOOT_BINGEN -c ${BASE_MACH} -t 3rdboot -n ${DEPLOY_DIR_IMAGE}/${NSIH_EMMC} -i ${B}/singleimage.bin -o ${B}/singleimage-emmcboot.bin -l ${BL2_LOAD_ADDR} -e ${BL2_JUMP_ADDR}
        BOOT_BINGEN -c ${BASE_MACH} -t 3rdboot -n ${DEPLOY_DIR_IMAGE}/${NSIH_SD}   -i ${B}/singleimage.bin -o ${B}/singleimage-sdboot.bin   -l ${BL2_LOAD_ADDR} -e ${BL2_JUMP_ADDR}
    else
        bbdebug 1 "Creating single bootloader image not requested through machine configuration."
    fi
}

do_deploy_append () {
    install ${B}/params_emmc.bin ${B}/params_sd.bin ${B}/params_recovery.bin ${B}/fip-nonsecure.img ${DEPLOYDIR}
    if [ "${BOOTLOADER_SINGLEIMAGE}" = "1" ]; then
        install ${B}/singleimage-emmcboot.bin ${B}/singleimage-sdboot.bin ${DEPLOYDIR}
    fi
}

addtask singlebootloader before do_deploy after do_compile
