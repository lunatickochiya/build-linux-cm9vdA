#!/bin/bash

WORKSPACE_PATH="${PWD}"
SCRIPT_NAME="${0##*/}"
# SCRIPT_PATH=`S=\`readlink "$0"\`; [ -z "$S" ] && S=$0; dirname $S`
SCRIPT_PATH="$(dirname $(readlink -f $0))"

source "${SCRIPT_PATH}/common.sh"

init() {
	ENV_FILE="${SCRIPT_PATH}/env/${SCRIPT_NAME}"
	source "${ENV_FILE}"

	# Common Variable
	export PATH="${PATH}:${TOOLCHAIN_PATH}/${TOOLCHAIN_NAME}/bin"
	if [ "${ARM_TOOLCHAIN_NAME}" != "" ]; then
		export PATH="$PATH:${TOOLCHAIN_PATH}/${ARM_TOOLCHAIN_NAME}/bin"
	fi
	if [ "${DT_TYPE}" != "mainline" ]; then 
		UBOOT_SRC="${WORKSPACE_PATH}/uboot-${DT_TYPE}"
	else
		UBOOT_SRC="${WORKSPACE_PATH}/uboot"
	fi

	BUILD_PATH="${WORKSPACE_PATH}/.build_uboot"
	BUILD_ARGS="-j$(nproc) O=${BUILD_PATH}"

	if [ "${ARCH_DEFCONFIG}" != "" ]; then
		DEFCONFIG="${ARCH_DEFCONFIG}"
	fi
	if [ "${BOARD_DEFCONFIG}" != "" ]; then
		DEFCONFIG="${BOARD_DEFCONFIG}"
	fi

	# if [ "${ATF_PLAT}" != "" ]; then
	# 	ATF_SRC="${WORKSPACE_PATH}/arm-trusted-firmware"
	# 	ATF_BIN=${ATF_SRC}/build/${ATF_PLAT}/release/bl31/bl31.elf
	# 	if [ -e "${ATF_BIN}" ]; then
	# 		export BL31=${ATF_BIN}
	# 	fi
	# fi

	if [ ! -e "${UBOOT_SRC}" ]; then
		echo "Please link the uboot source directory to '${UBOOT_SRC}'."
		exit 1
	fi

	cd "${UBOOT_SRC}"
	UBOOT_VERSION=$(make ubootversion)
}

build_info() {
	echo "================ Build Info ================"
	echo -e "BOARD_NAME:       ${BOARD_NAME}"
	echo -e "CPU_INFO:         ${CPU_INFO}"
	echo -e "ARCH:             ${ARCH}"
	echo -e "UBOOT_VERSION:    ${UBOOT_VERSION}"
	echo -e "DEFCONFIG:        ${DEFCONFIG}"
	echo -e "ATF_PLAT:         ${ATF_PLAT}"
	echo -e "ATF(BL31):        ${BL31}"
	if [ ! -z "${ROCKCHIP_TPL}" ]; then
		echo -e "ROCKCHIP_TPL:     ${ROCKCHIP_TPL}"
	fi
	echo -e "BUILD_ARGS:       ${BUILD_ARGS}"
	echo -e "CROSS_COMPILE:    ${CROSS_COMPILE}"
}

process() {
	echo "process"
}

build_atf() {
	if [ "${ATF_PLAT}" == "" ]; then
		echo "ATF_PLAT not set"
		return
	fi
	if [ ! -e "${ATF_SRC}" ]; then
		git clone https://github.com/ARM-software/arm-trusted-firmware.git "${ATF_SRC}"
	fi

	cd "${ATF_SRC}"
	unset BL31

	make clean
	make distclean
	git pull
	make CROSS_COMPILE=aarch64-linux-gnu- PLAT=${ATF_PLAT}
}

build_probe() {
	# link dts
	if [ "${DT_FILE}" != "" ] && [ "${DT_LINK}" == "1" ]; then
		DT_PATH="${SCRIPT_PATH}/boot/dts/${VENDOR}/${DT_TYPE}/"
		DT_PATH_LINK="${UBOOT_SRC}/arch/arm/dts/"
		DT_UPSTREAM_LINK="${UBOOT_SRC}/dts/upstream/src/${UPSTREAM_ARCH}/${VENDOR}/"
		check_path DTS "${DT_PATH}/${DT_FILE}.dts"
		ln -s -f "${DT_PATH}/${DT_FILE}.dts" "${DT_PATH_LINK}"
		if [ -d "${DT_UPSTREAM_LINK}" ]; then
			ln -s -f "${DT_PATH}/${DT_FILE}.dts" "${DT_UPSTREAM_LINK}"
		fi
		if [ "${DT_INC_FILE}" != "" ]; then
			check_path DTSI "${DT_PATH}/${DT_INC_FILE}.dtsi"
			ln -s -f "${DT_PATH}/${DT_INC_FILE}.dtsi" "${DT_PATH_LINK}"
			if [ -d "${DT_UPSTREAM_LINK}" ]; then
				ln -s -f "${DT_PATH}/${DT_INC_FILE}.dtsi" "${DT_UPSTREAM_LINK}"
			fi
		fi
		if [ -e "${DT_PATH}/${DT_FILE}-u-boot.dtsi" ]; then
			ln -s -f "${DT_PATH}/${DT_FILE}-u-boot.dtsi" "${DT_PATH_LINK}"
			if [ -d "${DT_UPSTREAM_LINK}" ]; then
				ln -s -f "${DT_PATH}/${DT_FILE}-u-boot.dtsi" "${DT_UPSTREAM_LINK}"
			fi
		fi
	fi

	# link defconfig
	if [ "${BOARD_DEFCONFIG}" != "" ]; then
		DEFCONFIG_PATH="${SCRIPT_PATH}/u-boot/${VENDOR}/u-boot-${UBOOT_VERSION}/${BOARD_DEFCONFIG}"
		check_path "BOARD_DEFCONFIG" "${DEFCONFIG_PATH}"
		ln -s -f "${DEFCONFIG_PATH}" "${UBOOT_SRC}/configs/"
	fi
}

show_menu() {
	cd "${UBOOT_SRC}"
	echo "================ Menu Option ================"
	# echo -e "\t[0]. Build ATF(arm64 only)"
	echo -e "\t[1]. Use Default Config(Specified in env)"
	echo -e "\t[2]. Menu Config"
	echo -e "\t[3]. Build U-boot"
	echo -e "\t[4]. Process"
	echo -e "\t[5]. Clean"

	read -p "Please Select: >> " OPT
	case ${OPT} in
	"1")
		build_probe
		make ${DEFCONFIG} ${BUILD_ARGS}
		;;
	"2")
		make menuconfig ${BUILD_ARGS}
		;;
	"3")
		TIME="Total Time: %E\tExit:%x" time make ${BUILD_ARGS}
		;;
	"4")
		process
		;;
	"5")
		make clean ${BUILD_ARGS}
		;;
	"atf")
		# Hide Option
		build_atf
		;;
	"mrproper")
		# Hide Option
		make mrproper
		;;
	"0")
		# Hide Option
		echo "apt install flex bison time bc kmod u-boot-tools libncurses5-dev libgmp-dev libmpc-dev libssl-dev python3-pyelftools libgnutls28-dev uuid-dev swig"
		;;
	*)
		echo "Not Support Option: [${OPT}]"
		;;
	esac
}

main() {
	init
	build_info
	show_menu
}

main
