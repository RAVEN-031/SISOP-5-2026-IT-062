#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="${ROOT_DIR}/osboot"
ISO_ROOT="${OSBOOT_DIR}/iso-root"
BOOT_DIR="${ISO_ROOT}/boot"
GRUB_DIR="${BOOT_DIR}/grub"
OUTPUT_FILE="${OSBOOT_DIR}/farewell.iso"

KERNEL_IMAGE="${OSBOOT_DIR}/bzImage"
SINGLE_INITRD="${OSBOOT_DIR}/single.gz"
MULTI_INITRD="${OSBOOT_DIR}/multi.gz"

for required_file in "${KERNEL_IMAGE}" "${SINGLE_INITRD}" "${MULTI_INITRD}"; do
    if [ ! -f "${required_file}" ]; then
        echo "Error: ${required_file} is missing." >&2
        exit 1
    fi
done

if ! command -v grub-mkrescue >/dev/null 2>&1; then
    echo "Error: grub-mkrescue is required to build the bootable ISO." >&2
    exit 1
fi

if ! command -v xorriso >/dev/null 2>&1; then
    echo "Error: xorriso is required by grub-mkrescue." >&2
    exit 1
fi

rm -rf "${ISO_ROOT}" "${OUTPUT_FILE}"
mkdir -p "${GRUB_DIR}"

cp "${KERNEL_IMAGE}" "${BOOT_DIR}/bzImage"
cp "${SINGLE_INITRD}" "${BOOT_DIR}/single.gz"
cp "${MULTI_INITRD}" "${BOOT_DIR}/multi.gz"

cat > "${GRUB_DIR}/grub.cfg" <<'EOF_GRUB'
set timeout=10
set default=0

menuentry "Farewell Party - single filesystem" {
    linux /boot/bzImage loglevel=7
    initrd /boot/single.gz
}

menuentry "Farewell Party - multi filesystem" {
    linux /boot/bzImage loglevel=7
    initrd /boot/multi.gz
}
EOF_GRUB

grub-mkrescue -o "${OUTPUT_FILE}" "${ISO_ROOT}"

echo "Bootable ISO created at ${OUTPUT_FILE}"
