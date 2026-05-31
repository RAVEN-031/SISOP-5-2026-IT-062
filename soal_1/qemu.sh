#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="${ROOT_DIR}/osboot"

KERNEL_IMAGE="${OSBOOT_DIR}/bzImage"
SINGLE_INITRD="${OSBOOT_DIR}/single.gz"
MULTI_INITRD="${OSBOOT_DIR}/multi.gz"
ISO_IMAGE="${OSBOOT_DIR}/farewell.iso"

usage() {
    cat <<EOF
Usage: $0 [--single|--multi|--all]

  --single   Boot single-user filesystem directly
  --multi    Boot multi-user filesystem directly
  --all      Boot farewell.iso and choose from GRUB
EOF
}

require_file() {
    local file="$1"

    if [ ! -f "${file}" ]; then
        echo "Error: ${file} is missing." >&2
        exit 1
    fi
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "Error: qemu-system-x86_64 is required to boot the OS." >&2
    exit 1
fi

if [ "$#" -ne 1 ]; then
    usage >&2
    exit 1
fi

COMMON_ARGS=(
    -m 256M
    -no-reboot
    -nic user,model=e1000
)

case "$1" in
    --single)
        require_file "${KERNEL_IMAGE}"
        require_file "${SINGLE_INITRD}"
        qemu-system-x86_64 \
            "${COMMON_ARGS[@]}" \
            -kernel "${KERNEL_IMAGE}" \
            -initrd "${SINGLE_INITRD}" \
            -append "loglevel=7"
        ;;
    --multi)
        require_file "${KERNEL_IMAGE}"
        require_file "${MULTI_INITRD}"
        qemu-system-x86_64 \
            "${COMMON_ARGS[@]}" \
            -kernel "${KERNEL_IMAGE}" \
            -initrd "${MULTI_INITRD}" \
            -append "loglevel=7"
        ;;
    --all)
        require_file "${ISO_IMAGE}"
        qemu-system-x86_64 \
            "${COMMON_ARGS[@]}" \
            -boot d \
            -cdrom "${ISO_IMAGE}"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac
