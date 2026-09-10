#!/bin/bash

set -e

mkdir -p ${BINARIES_DIR}/rpi-firmware

# Default to 64-bit parameters
KERNEL_BOOT_CMD="booti"
KERNEL_IMAGE_TYPE="Image"
MKIMAGE_ARCH="arm64"

# 1. Check for 32-bit zImage or explicit buildroot options
if grep -q '^BR2_LINUX_KERNEL_ZIMAGE=y$' "${BR2_CONFIG}" || [ -f "${BINARIES_DIR}/zImage" ]; then
  KERNEL_BOOT_CMD="bootz"
  KERNEL_IMAGE_TYPE="zImage"
  MKIMAGE_ARCH="arm"
elif grep -q '^BR2_LINUX_KERNEL_UIMAGE=y$' "${BR2_CONFIG}"; then
  KERNEL_BOOT_CMD="bootm"
  KERNEL_IMAGE_TYPE="uImage"
  MKIMAGE_ARCH="arm"
fi

cp -f "${BINARIES_DIR}/${KERNEL_IMAGE_TYPE}" "${BINARIES_DIR}/rpi-firmware"

sed \
  -e "s|@KERNEL_BOOT_CMD@|${KERNEL_BOOT_CMD}|" \
  -e "s|@KERNEL_IMAGE_TYPE@|${KERNEL_IMAGE_TYPE}|" \
  "${BR2_EXTERNAL_AA_PROXY_OS_PATH}/board/rpi/boot.cmd.in" > "${BUILD_DIR}/boot.cmd"

# 2. Use $MKIMAGE_ARCH dynamically instead of hardcoded arm64
mkimage -A "${MKIMAGE_ARCH}" -T script -C none \
  -n "Boot script" \
  -d "${BUILD_DIR}/boot.cmd" \
  "${BINARIES_DIR}/rpi-firmware/boot.scr"

BOARD_DIR="$(dirname $0)"
BOARD_NAME="$(basename ${BOARD_DIR})"
GENIMAGE_CFG="${BOARD_DIR}/genimage-${BOARD_NAME}.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# generate genimage from template if a board specific variant doesn't exist
if [ ! -e "${GENIMAGE_CFG}" ]; then
    GENIMAGE_CFG="${BINARIES_DIR}/genimage.cfg"
    FILES=()

    for i in "${BINARIES_DIR}"/*.dtb "${BINARIES_DIR}"/rpi-firmware/*; do
        FILES+=( "${i#${BINARIES_DIR}/}" )
    done

    KERNEL=$(sed -n 's/^kernel=//p' "${BINARIES_DIR}/rpi-firmware/config.txt")
    FILES+=( "${KERNEL}" )

    BOOT_FILES=$(printf '\\t\\t\\t"%s",\\n' "${FILES[@]}")
    sed "s|#BOOT_FILES#|${BOOT_FILES}|" "${BOARD_DIR}/genimage.cfg.in" \
        > "${GENIMAGE_CFG}"
fi

trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
ROOTPATH_TMP="$(mktemp -d)"

rm -rf "${GENIMAGE_TMP}"

genimage \
    --rootpath "${ROOTPATH_TMP}"   \
    --tmppath "${GENIMAGE_TMP}"    \
    --inputpath "${BINARIES_DIR}"  \
    --outputpath "${BINARIES_DIR}" \
    --config "${GENIMAGE_CFG}"

swugenerator -o "${BINARIES_DIR}/update_image.swu" -a "${BINARIES_DIR}" -s "${BR2_EXTERNAL_AA_PROXY_OS_PATH}/board/rpi/sw-description" -e create
