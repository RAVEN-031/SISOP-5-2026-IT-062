#!/bin/bash

set -euo pipefail

KERNEL_VERSION="6.1.1"
KERNEL_ARCHIVE="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_DIR="linux-${KERNEL_VERSION}"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_ARCHIVE}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="${ROOT_DIR}/osboot"
CONFIG_FILE="${ROOT_DIR}/config"

mkdir -p "${OSBOOT_DIR}"

cd "${OSBOOT_DIR}"

if [ ! -f "${KERNEL_ARCHIVE}" ]; then
    echo "Downloading Linux kernel ${KERNEL_VERSION}..."
    if command -v wget >/dev/null 2>&1; then
        wget "${KERNEL_URL}"
    elif command -v curl >/dev/null 2>&1; then
        curl -LO "${KERNEL_URL}"
    else
        echo "Error: wget or curl is required to download the kernel." >&2
        exit 1
    fi
fi

if [ ! -d "${KERNEL_DIR}" ]; then
    echo "Extracting ${KERNEL_ARCHIVE}..."
    tar -xf "${KERNEL_ARCHIVE}"
fi

cd "${KERNEL_DIR}"

if ! grep -q "REALMODE_CFLAGS += -std=gnu11" arch/x86/Makefile; then
    echo "Patching realmode CFLAGS for newer GCC..."
    sed -i '/REALMODE_CFLAGS += $(CLANG_FLAGS)/a REALMODE_CFLAGS += -std=gnu11' arch/x86/Makefile
fi

if ! grep -q "KBUILD_CFLAGS += -std=gnu11" arch/x86/boot/compressed/Makefile; then
    echo "Patching compressed boot CFLAGS for newer GCC..."
    sed -i '/KBUILD_CFLAGS += -fno-strict-aliasing -fPIE/a KBUILD_CFLAGS += -std=gnu11' arch/x86/boot/compressed/Makefile
fi

if [ -s "${CONFIG_FILE}" ]; then
    echo "Using existing kernel config from ${CONFIG_FILE}..."
    cp "${CONFIG_FILE}" .config
    make olddefconfig
else
    echo "No config found yet, using tinyconfig as a baseline..."
    make tinyconfig
fi

echo "Building Linux kernel ${KERNEL_VERSION}..."
make -j"$(nproc)"

cp arch/x86/boot/bzImage "${OSBOOT_DIR}/bzImage"
echo "Kernel image created at ${OSBOOT_DIR}/bzImage"
