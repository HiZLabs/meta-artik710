DESCRIPTION = "Samsung secure bootloader firmware for Artik 710"
SECTION = "bootloaders"
LICENSE = "GPLv2"

LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0;md5=801f80980d171dd6425610833a22dbe6"

FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"

# bl1 for SD and eMMC boot (a.k.a. AP Boot ROM: AP_BL1, in our case bl1-emmcboot.img and bl1-sdboot.img)
# bl2 for SD and eMMC boot (a.k.a. AP RAM Firmware: AP_BL2, in our case fip-loader-emmc.img and fip-loader-sd.img)
# bl31 + bl32 (a.k.a. EL3 Runtime Firmware or SoC AP firmware or EL3 monitor firmware: AP_BL31 + Secure-EL1 Payload (SP): AP_BL32, in our case the bundled image fip-secure.img consisting of the ATF + secure OS OPTEE)

SRC_URI_artik710 = "git://github.com/SamsungARTIK/boot-firmwares-artik710.git;protocol=https;branch=A710_os_3.0.0;rev=ba9ea293911faf41b4ca0d068240ba69830834c7"

inherit deploy

S = "${WORKDIR}/git"

do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_deploy () {
    install -d ${DEPLOYDIR}
    install -m 755 ${S}/*.img ${DEPLOYDIR}
    install -m 755 ${S}/*.txt ${DEPLOYDIR}
    install -m 755 ${S}/uInitrd ${DEPLOYDIR}
}

addtask deploy before do_build after do_compile

COMPATIBLE_MACHINE = "(artik710)"
PACKAGE_ARCH = "${MACHINE_ARCH}"
