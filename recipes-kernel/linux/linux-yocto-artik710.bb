FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

LINUX_VERSION = "4.4.71"
SRC_URI = " \
    git://github.com/HiZLabs/linux-artik.git;protocol=https;branch=A710_os_3.0.0 \
    file://defconfig \
    "

#SRC_URI = " \
#    git://github.com/SamsungARTIK/linux-artik.git;protocol=https;branch=A710/v4.4 \
#    file://compile_mali_kernel_module_out_of_tree.patch \
#    file://DRM-nexell-Add-support-for-hdmi-1280x1024-60-resolut.patch \
#    "

SRCREV = "df6ad819cc8f74a52ba8219db283d2f96630012a"

inherit kernel
require recipes-kernel/linux/linux-yocto.inc

PV = "${LINUX_VERSION}+git${SRCPV}"

S = "${WORKDIR}/git"

# The defconfig was created with make_savedefconfig so not all the configs are in place
KCONFIG_MODE="--alldefconfig"

COMPATIBLE_MACHINE = "(artik710)"

kernel_do_install_prepend () {
	export INSTALL_MOD_STRIP="1"
}
