#!/bin/bash

WORKSPACE_PATH=${PWD}
KERNEL_SRC="${WORKSPACE_PATH}/linux"

SCRIPT_NAME=${0##*/}
# SCRIPT_PATH=`S=\`readlink "$0"\`; [ -z "$S" ] && S=$0; dirname $S`
SCRIPT_PATH=$(dirname $(readlink -f $0))
source ${SCRIPT_PATH}/common.sh

init() {
	# Check kernel source
	if [ ! -e "${KERNEL_SRC}" ]; then
		echo "Please link the kernel source directory to 'linux'."
		exit 1
	fi

	# Source env
	ENV_FILE="${SCRIPT_PATH}/env/${SCRIPT_NAME}"
	source ${ENV_FILE}

	if [ "${NO_CROSS_COMPILE}" == "1" ]; then
		# No use cross compile toolchain on same platform
		if ([ "${HOST_ARCH}" == "aarch64" ] && [ "${ARCH}" == "arm64" ]) || ([ "${HOST_ARCH:0:3}" == "arm" ] && [ "${ARCH}" == "arm" ]); then
			unset CROSS_COMPILE
		fi
	fi

	# Common Variable
	export PATH=${TOOLCHAIN_PATH}/${TOOLCHAIN_NAME}/bin:${PATH}
	export INSTALL_MOD_PATH="${WORKSPACE_PATH}/install"
	export INSTALL_HDR_PATH=${INSTALL_MOD_PATH}

	BUILD_PATH=${WORKSPACE_PATH}/.build
	BUILD_ARGS="-j$(nproc) O=${BUILD_PATH}"

	cd ${KERNEL_SRC}
	KERNEL_VERSION=$(make kernelversion)
	cd ${WORKSPACE_PATH}
}

check_env() {
	# Check Env
	if [ "${ARCH}" != "arm64" ] && [ "$ARCH" != "arm" ]; then
		echo "Invalid arch: ${ARCH}"
		exit 1
	fi

	if [ "${ARCH}" == "arm64" ]; then
		check_var VENDOR "${VENDOR}"
	fi
	# if [ "$ARCH" == "arm" ]; then

	# fi
	check_var DT_PATH "${DT_PATH}"
}

build_info() {
	echo "================ Build Info ================"
	echo -e "BOARD_NAME:       ${BOARD_NAME}"
	echo -e "CPU_INFO:         ${CPU_INFO}"
	echo -e "DT_FILE:          ${DT_FILE}"
	echo -e "ARCH:             ${ARCH}"
	echo -e "KERNEL_VERSION:   ${KERNEL_VERSION}"
	echo -e "DEFCONFIG:        ${DEFCONFIG}"
	echo -e "BUILD_ARGS:       ${BUILD_ARGS}"
	echo -e "CROSS_COMPILE:    ${CROSS_COMPILE}"
	echo -e "INSTALL_MOD_PATH: ${INSTALL_MOD_PATH}"
	echo -e "INSTALL_HDR_PATH: ${INSTALL_HDR_PATH}"
}

build_kernel() {
	cd ${KERNEL_SRC}
	case $1 in
	"kernel")
		TIME="Total Time: %E\tExit:%x" time make ${KERNEL_TARGET} ${BUILD_ARGS}
		;;
	"modules")
		TIME="Total Time: %E\tExit:%x" time make modules ${BUILD_ARGS}
		;;
	"dtbs")
		if [ "${DT_FILE}" != "" ]; then
			TIME="Total Time: %E\tExit:%x" time make dtbs ${BUILD_ARGS}
		fi
		;;
	*)
		echo "Invalid Parmameter: [$1]"
		;;
	esac
	return $?
}

install_kernel() {
	cd "${KERNEL_SRC}"
	rm -rf ${INSTALL_MOD_PATH}
	# Install Modules
	TIME="Total Time: %E\tExit:%x" time make modules_install ${BUILD_ARGS}

	if [ "$ARCH" == "arm64" ]; then
		# Generate uImage
		mkimage -A "${ARCH}" -O linux -T kernel -C none -a 0x1080000 -e 0x1080000 -n linux-next -d "${BUILD_PATH}/arch/${ARCH}/boot/Image" "${INSTALL_MOD_PATH}/uImage"
	elif [ "$ARCH" == "arm" ]; then
		# Copy zImage
		cp -f "${BUILD_PATH}/arch/${ARCH}/boot/${KERNEL_TARGET}" "${INSTALL_MOD_PATH}"
	fi

	# Copy dts/dtb
	if [ "${DT_FILE}" != "" ]; then
		if [ "$ARCH" == "arm64" ]; then
			local _DT_PATH="arch/${ARCH}/boot/dts/${VENDOR}"
		elif [ "$ARCH" == "arm" ]; then
			local _DT_PATH="arch/${ARCH}/boot/dts/"
		fi

		cp -f "${KERNEL_SRC}/${_DT_PATH}/${DT_FILE}.dts" "${INSTALL_MOD_PATH}"
		cp -f "${BUILD_PATH}/${_DT_PATH}/${DT_FILE}.dtb" "${INSTALL_MOD_PATH}"
	fi

	cd "${WORKSPACE_PATH}"
	# Copy .config
	cp -f "${BUILD_PATH}/.config" "${INSTALL_MOD_PATH}/config"
}

install_headers() {
	cd "${KERNEL_SRC}"
	# Install Headers
	TIME="Total Time: %E\tExit:%x" time make headers_install ${BUILD_ARGS} INSTALL_HDR_PATH=${INSTALL_HDR_PATH}
}

archive_kernel() {
	local pack_info
	# Input log
	read -p "Input Package Log:" pack_info
	echo "${pack_info}" >"${INSTALL_MOD_PATH}/info"

	# Package
	#cd $KDIR
	local PACK_NAME="linux_${PACK_NAME}_${KERNEL_VERSION}_$(date +%Y%m%d_%H%M).tar.xz"
	cd "${INSTALL_MOD_PATH}"
	TIME="Total Time: %E\tExit:%x" time tar cJfp "../${PACK_NAME}" *
	echo "Package To ${PACK_NAME}"
}

create_deb() {
	local deb_name=${DT_FILE}-kernel
	local deb_version=${KERNEL_VERSION}-$(date +%Y%m%d%H%M)
	cd "${WORKSPACE_PATH}"

	rm -rf deb/${deb_name}
	mkdir -p deb/${deb_name}
	cd deb/${deb_name}

	mkdir -p DEBIAN
	mkdir -p boot
	cp -dpr ${INSTALL_MOD_PATH}/lib ./
	cp ${INSTALL_MOD_PATH}/${DT_FILE}.dtb ./boot/dtb.img
	cp ${INSTALL_MOD_PATH}/uImage ./boot

	cat <<EOF >DEBIAN/control
Package: ${deb_name}
Version: ${deb_version}
Architecture: ${ARCH}
Maintainer: test
Installed-Size: $(du -ks | cut -f 1)
Section: test
Priority: optional
Description: kernel for ${BOARD_NAME}

EOF
	# 	cat <<EOF >DEBIAN/postinst

	# EOF
	# 	chmod 775 DEBIAN/postinst
	cd ..
	dpkg -b ${deb_name} ${deb_name}_${KERNEL_VERSION}_${ARCH}.deb
}

show_menu() {
	cd "${KERNEL_SRC}"

	echo "================ Menu Option ================"
	echo -e "\t[1]. Use Default Config"
	echo -e "\t[2]. Menu Config"
	echo -e "\t[3]. Build All"
	echo -e "\t[31] ├─Build Kernel"
	echo -e "\t[32] ├─Build Modules"
	echo -e "\t[33] └─Build DTB"
	echo -e "\t[4]. Install All"
	echo -e "\t[41] ├─Install Kernel And Modules"
	echo -e "\t[42] └─Install Headers"
	echo -e "\t[5]. Archive Kernel"
	echo -e "\t[6]. Clean"

	read -p "Please Select: >> " OPT
	case ${OPT} in
	"1")
		cd ${KERNEL_SRC}
		if [ "${DEFCONFIG}" != "" ]; then
			make ${DEFCONFIG} ${BUILD_ARGS}
		else
			make defconfig ${BUILD_ARGS}
		fi
		;;
	"2")
		cd ${KERNEL_SRC}
		make menuconfig ${BUILD_ARGS}
		;;
	"3")
		build_kernel kernel
		if [ $? != 0 ]; then
			exit -1
		fi
		build_kernel modules
		if [ $? != 0 ]; then
			exit -1
		fi
		build_kernel dtbs
		;;
	"31")
		build_kernel kernel
		;;
	"32")
		build_kernel modules
		;;
	"33")
		build_kernel dtbs
		;;
	"4")
		install_kernel
		install_headers
		;;
	"41")
		install_kernel
		;;
	"42")
		install_headers
		;;
	"5")
		archive_kernel
		;;
	"6")
		cd ${KERNEL_SRC}
		make clean ${BUILD_ARGS}
		rm ${INSTALL_MOD_PATH}/* -rf
		;;
	"mrproper")
		cd ${KERNEL_SRC}
		# Hide Option
		make mrproper
		;;
	"0")
		# Hide Option
		echo "apt install flex bison time bc kmod u-boot-tools libncurses5-dev libgmp-dev libmpc-dev libssl-dev"
		;;
	*)
		echo "Not Support Option: [${OPT}]"
		;;
	esac
}

build_probe() {
	# link dts
	if [ "${DT_FILE}" != "" ]; then
		DT_PATH="${SCRIPT_PATH}/boot/dts/${VENDOR}/mainline/${DT_FILE}"
		if [ "$ARCH" == "arm64" ]; then
			DT_PATH_LINK="${KERNEL_SRC}/arch/${ARCH}/boot/dts/${VENDOR}/"
		elif [ "$ARCH" == "arm" ]; then
			DT_PATH_LINK="${KERNEL_SRC}/arch/${ARCH}/boot/dts/"
		fi
		check_path DTS "${DT_PATH}.dts"
		ln -s -f "${DT_PATH}.dts" ${DT_PATH_LINK}
		# add dtb to Makefile
		grep -q ${DT_FILE} ${DT_PATH_LINK}/Makefile
		if [ $? -ne 0 ]; then
			echo "dtb-y += ${DT_FILE}.dtb" >>${DT_PATH_LINK}/Makefile
		fi
	fi

	# link defconfig
	if [ "${DEFCONFIG}" != "" ]; then
		DEFCONFIG_PATH="${SCRIPT_PATH}/boot/configs/${DEFCONFIG}"
		check_path "DEFCONFIG" "${DEFCONFIG_PATH}"
		ln -s -f ${DEFCONFIG_PATH} "${KERNEL_SRC}/arch/${ARCH}/configs/"
	fi
}

main() {
	init
	build_info
	build_probe
	show_menu
}

main
