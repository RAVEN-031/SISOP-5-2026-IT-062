# SISOP-5-2026-IT-062

## Laporan

### Soal 1 - Farewell Party

#### 1. Struktur folder

<img width="595" height="190" alt="image" src="https://github.com/user-attachments/assets/1d58d3d2-952b-4e9a-a690-4b7381b08074" />

#### 2. Kernel Compiler Script

Script mendownload kernel.

```bash
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
```

Lalu meng-compile dan membuat config minimum

```bash
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
echo "Kernel image created at ${OSBOOT_DIR}/bzImage
```

Lalu digunakan `make menuconfig` untuk setting config yang masih diperlukan

#### 3. Single filesystem

Script `single.sh` melakukan setup untuk filesystem dan busybox

```bash
mkdir -p \
    "${ROOTFS_DIR}/bin" \
    "${ROOTFS_DIR}/dev" \
    "${ROOTFS_DIR}/proc" \
    "${ROOTFS_DIR}/sys" \
    "${ROOTFS_DIR}/etc" \
    "${ROOTFS_DIR}/tmp" \
    "${ROOTFS_DIR}/root" \
    "${ROOTFS_DIR}/packages/fuse"

chmod 755 "${ROOTFS_DIR}"
install -m 755 "${ROOT_DIR}/../hello_fuse" \
    "${ROOTFS_DIR}/packages/fuse/hello_fuse"
chmod 755 "${ROOTFS_DIR}/bin" "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" \
    "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/etc" "${ROOTFS_DIR}/root"
chmod 1777 "${ROOTFS_DIR}/tmp"

install -m 755 "${BUSYBOX_BIN}" "${ROOTFS_DIR}/bin/busybox"

for applet in sh mount umount mkdir cat echo ls ps pwd clear dmesg sleep reboot poweroff cp \
    ifconfig route udhcpc ping wget nslookup; do
    ln -s busybox "${ROOTFS_DIR}/bin/${applet}"
done
```

Terdapat satu user yang dapat mengakses semuanya.

#### 4. Multi filesystem

Script melakukan setup untuk semua user sesuai dengan ketentuan.

```bash
cat > "${ROOTFS_DIR}/etc/passwd" <<'EOF_PASSWD'
root:x:0:0:root:/root:/bin/sh
henn:x:1000:1000:henn:/home/henn:/bin/sh
hann:x:1001:1001:hann:/home/hann:/bin/sh
viii:x:1002:1002:viii:/home/viii:/bin/sh
kids:x:1003:1003:kids:/home/kids:/bin/sh
EOF_PASSWD

cat > "${ROOTFS_DIR}/etc/group" <<'EOF_GROUP'
root:x:0:
henn:x:1000:henn
hann:x:1001:hann
viii:x:1002:viii
kids:x:1003:kids
hannhome:x:2001:henn,hann
viiihome:x:2002:henn,hann,viii
kidshome:x:2003:henn,hann,viii,kids
EOF_GROUP

cat > "${ROOTFS_DIR}/etc/shadow" <<EOF_SHADOW
root:$(hash_password rootpass root123):20410:0:99999:7:::
henn:$(hash_password hennpass henn123):20410:0:99999:7:::
hann:$(hash_password hannpass hann123):20410:0:99999:7:::
viii:$(hash_password viiipass viii123):20410:0:99999:7:::
kids:$(hash_password kidspass kids123):20410:0:99999:7:::
EOF_SHADOW
```

Dan juga accessnya

```bash
dir /home/henn 0700 1000 1000
dir /home/hann 0770 1001 2001
dir /home/viii 0770 1002 2002
dir /home/kids 0770 1003 2003
```

#### 5. Iso script

Script `iso.sh` menyiapkan disk image yang siap dijalankan dari `bzimage`, `single.gz`, dan `multi.gz`

```bash
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
```

#### 6. Qemu script

Script `qemu.sh` menerima satu argumen yang digunakan untuk menjalankan jenis filesystem

```bash
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
```

#### 7. Backup script

Backup script memasukkan file-file yang diperlukan dan menyimpannya dengan format yang terdapat timestampnya.

```bash
(
    cd "${OSBOOT_DIR}"
    zip -9 -q "${OUTPUT_FILE}" "${FILES[@]}"
)
```

#### 8. Internet access

Untuk internet access, yang pertama adalah mengaktifkan beberapa setting di dalam config yang memungkinkan akses internet.

Lalu qemu.sh memiliki argumen yang menjalankan qemu dengan emulasi NIC Intel e10000

```bash
COMMON_ARGS=(
    -m 256M
    -no-reboot
    -nic user,model=e1000
)
```

Dalam bagian init di script `multi.sh` terdapat bagian setup yang memungkinkan koneksi internet

```bash
ifconfig lo up 2>/dev/null || true
for netdev in eth0 ens3 enp0s3; do
    ifconfig "$netdev" up 2>/dev/null || continue
    udhcpc -i "$netdev" -n -q -T 2 -t 3 -s /usr/share/udhcpc/default.script 2>/dev/null && break
done
```

Script juga setup DNS yang memungkinkan `wget` untuk bekerja

```bash
cat > "${ROOTFS_DIR}/etc/resolv.conf" <<'EOF_RESOLV'
nameserver 10.0.2.3
nameserver 8.8.8.8
EOF_RESOLV
```

#### 9. Package manager

Untuk package manager, menggunakan script sederhana yang mensimulasikan package manager. Script ini memindahkan binary file yang sudah dipackage ke dalam `multi.gz` ke dalam `/bin/` yang termasuk ke dalam `PATH`.

```bash
cat > "${ROOTFS_DIR}/bin/party" <<'EOF_PARTY'
#!/bin/sh

usage() {
    echo "usage: party install <package>"
    echo "packages: hello, example, fuse"
}

install_hello() {
    cat > /bin/hello <<'EOF_HELLO'
#!/bin/sh
echo "Hello from party package manager!"
EOF_HELLO
    chmod +x /bin/hello
    echo "installed: hello"
}

install_example() {
    mkdir -p /tmp/party
    wget --no-check-certificate -O /tmp/party/example.html http://example.com
    echo "installed: example -> /tmp/party/example.html"
}

install_fuse() {
    cp /packages/fuse/hello_fuse /bin/hello_fuse
    chmod 755 /bin/hello_fuse
    echo "installed: fuse"
}

case "$1" in
    install)
        case "$2" in
            hello)
                install_hello
                ;;
            example)
                install_example
                ;;
            fuse)
                install_fuse
                ;;
            ""|-h|--help)
                usage
                exit 1
                ;;
            *)
                echo "package not found: $2" >&2
                usage >&2
                exit 1
                ;;
        esac
        ;;
    list)
        echo "hello"
        echo "example"
        echo "fuse"
        ;;
    -h|--help|"")
        usage
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac
EOF_PARTY

chmod +x "${ROOTFS_DIR}/bin/party"
```

#### 10. Fuse

Program fuse yang dipackage kedalam `multi.sh` dapat dijalankan untuk melakukan mounting.

<img width="727" height="399" alt="image" src="https://github.com/user-attachments/assets/29905443-0d6e-46e5-8536-ac794d1eae59" />


