#!/bin/bash
# NetHunter kernel for Samsung MSM8974 devices build script by jcadduono
# This build script is for LineageOS only

################### BEFORE STARTING ################
#
# download a working toolchain and extract it somewhere and configure this
# file to point to the toolchain's root directory.
# I highly recommend using a Linaro GCC 4.9.x arm-linux-gnueabihf toolchain.
# Download it here:
# https://releases.linaro.org/components/toolchain/binaries/4.9.4-2017.01/arm-linux-gnueabihf/
#
# once you've set up the config section how you like it, you can simply run
# ./build.sh
#
################ DEVICES & VARIANTS ################
#
#### klte (Samsung Galaxy S5)
#
# xx      = kltexx,   klteacg,   klteatt,  kltecan,   kltelra,   kltetmo,  klteub,   klteusc,   kltevzw
#           SM-G900F, SM-G900R7, SM-G900A, SM-G900W8, SM-G900R6, SM-G900T, SM-G900M, SM-G900R4, SM-G900V
#
# spr     = kltespr,  kltedv
#           SM-G900P, SM-G900I
#
# duos    = klteduosxx, klteduosub
#           SM-G900FD,  SM-G900MD
#
# chn     = kltezn,    kltezm
#           SM-G9006V, SM-G9008V
#
# chnduo  = klteduoszn, klteduoszm, klteduosctc
#           SM-G9006W,  SM-G9008W,  SM-G9009W
#
# kdi     = kltekdi, kltedcm
#           SCL23,   SC-04F
#
# kor     = kltektt,  klteskt,  kltelgt
#           SM-G900K, SM-G900S, SM-G900L
#
###################### CONFIG ######################

# root directory of NetHunter Samsung MSM8974 git repo (default is this script's location)
RDIR=$(pwd)

[ "$VER" ] ||
# version number
VER=$(cat "$RDIR/VERSION")

# directory containing cross-compile arm toolchain
TOOLCHAIN=$HOME/build/toolchain/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf

CPU_THREADS=$(grep -c "processor" /proc/cpuinfo)
# amount of cpu threads to use in kernel make process
THREADS=$((CPU_THREADS + 1))

############## SCARY NO-TOUCHY STUFF ###############

ABORT() {
	[ "$1" ] && echo "Error: $*"
	exit 1
}

CONTINUE=false
export ARCH=arm
export CROSS_COMPILE=$TOOLCHAIN/bin/arm-linux-gnueabihf-

[ -x "${CROSS_COMPILE}gcc" ] ||
ABORT "Unable to find gcc cross-compiler at location: ${CROSS_COMPILE}gcc"

while [ $# != 0 ]; do
	if [ "$1" = "--continue" ] || [ "$1" == "-c" ]; then
		CONTINUE=true
	elif [ ! "$DEVICE" ]; then
		DEVICE=$1
	elif [ ! "$VARIANT" ]; then
		VARIANT=$1
	elif [ ! "$TARGET" ]; then
		TARGET=$1
	else
		echo "Too many arguments!"
		echo "Usage: ./build.sh [--continue] [device] [variant] [target defconfig]"
		ABORT
	fi
	shift
done

[ "$DEVICE" ] || DEVICE=klte
[ "$VARIANT" ] || VARIANT=xx
[ "$TARGET" ] || TARGET=nethunter
DEFCONFIG=${TARGET}_${DEVICE}_defconfig
VARIANT_DEFCONFIG=variant_${DEVICE}_${VARIANT}

[ -f "$RDIR/arch/$ARCH/configs/${DEFCONFIG}" ] ||
ABORT "Device config $DEFCONFIG not found in $ARCH configs!"

[ -f "$RDIR/arch/$ARCH/configs/$VARIANT_DEFCONFIG" ] ||
ABORT "Device variant/carrier $VARIANT_DEFCONFIG not found in $ARCH configs!"

export LOCALVERSION="$TARGET-$DEVICE-$VARIANT-$VER"

CLEAN_BUILD() {
	echo "Cleaning build..."
	rm -rf build
}

SETUP_BUILD() {
	echo "Creating kernel config for $LOCALVERSION..."
	mkdir -p build
	make -C "$RDIR" O=build "$DEFCONFIG" \
		VARIANT_DEFCONFIG="$VARIANT_DEFCONFIG" \
		|| ABORT "Failed to set up build!"
}

BUILD_KERNEL() {
	echo "Starting build for $LOCALVERSION..."
	while ! make -C "$RDIR" O=build -j"$THREADS" CONFIG_NO_ERROR_ON_MISMATCH=y; do
		read -rp "Build failed. Retry? " do_retry
		case $do_retry in
			Y|y) continue ;;
			*) return 1 ;;
		esac
	done
}

BUILD_DTB()
{
	echo "Generating dtb.img..."
	build/scripts/dtbtool/dtbtool -p build/scripts/dtc/ \
		-s 2048 -o "build/arch/$ARCH/boot/dtb.img" \
		"build/arch/$ARCH/boot/" \
		|| ABORT "Failed to generate dtb.img!"
}

INSTALL_MODULES() {
	grep -q 'CONFIG_MODULES=y' build/.config || return 0
	echo "Installing kernel modules to build/lib/modules..."
	while ! make -C "$RDIR" O=build \
			INSTALL_MOD_PATH="." \
			INSTALL_MOD_STRIP=1 \
			modules_install
	do
		read -rp "Build failed. Retry? " do_retry
		case $do_retry in
			Y|y) continue ;;
			*) return 1 ;;
		esac
	done
	rm build/lib/modules/*/build build/lib/modules/*/source
}

cd "$RDIR" || ABORT "Failed to enter $RDIR!"

if ! $CONTINUE; then
	CLEAN_BUILD
	SETUP_BUILD ||
	ABORT "Failed to set up build!"
fi

BUILD_KERNEL &&
BUILD_DTB &&
INSTALL_MODULES &&
echo "Finished building $LOCALVERSION!"
