#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="${ROOT_DIR}/osboot"
ROOTFS_DIR="${OSBOOT_DIR}/single-rootfs"
OUTPUT_FILE="${OSBOOT_DIR}/single.gz"

BUSYBOX_BIN="$(command -v busybox || true)"

if [ -z "${BUSYBOX_BIN}" ]; then
    echo "Error: busybox is required to build the single-user filesystem." >&2
    exit 1
fi

if ! command -v cpio >/dev/null 2>&1; then
    echo "Error: cpio is required to build the initramfs image." >&2
    exit 1
fi

rm -rf "${ROOTFS_DIR}" "${OUTPUT_FILE}"

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

cat > "${ROOTFS_DIR}/etc/passwd" <<'EOF_PASSWD'
root:x:0:0:root:/root:/bin/sh
EOF_PASSWD

cat > "${ROOTFS_DIR}/etc/group" <<'EOF_GROUP'
root:x:0:
EOF_GROUP

cat > "${ROOTFS_DIR}/etc/profile" <<'EOF_PROFILE'
export PATH=/bin
export HOME="${HOME:-/root}"

USER_NAME="$(whoami 2>/dev/null || echo root)"
export PS1="${USER_NAME}:\w# "

clear
cat <<'EOF_BANNER'
 _____                         _ _   ____            _
|  ___|_ _ _ __ _____      __ | | | |  _ \ __ _ _ __| |_ _   _
| |_ / _` | '__/ _ \ \ /\ / / | | | | |_) / _` | '__| __| | | |
|  _| (_| | | |  __/\ V  V /  |_| | |  __/ (_| | |  | |_| |_| |
|_|  \__,_|_|  \___| \_/\_/   (_) | |_|   \__,_|_|   \__|\__, |
                                                          |___/
EOF_BANNER

echo "Welcome, ${USER_NAME}."
EOF_PROFILE

mkdir -p "${ROOTFS_DIR}/usr/share/udhcpc"

cat > "${ROOTFS_DIR}/etc/resolv.conf" <<'EOF_RESOLV'
nameserver 10.0.2.3
nameserver 8.8.8.8
EOF_RESOLV

cat > "${ROOTFS_DIR}/usr/share/udhcpc/default.script" <<'EOF_UDHCPC'
#!/bin/sh

case "$1" in
    bound|renew)
        ifconfig "$interface" "$ip" netmask "${subnet:-255.255.255.0}" broadcast "${broadcast:-+}"
        [ -n "$router" ] && route add default gw ${router%% *} dev "$interface" 2>/dev/null
        {
            for dns_server in $dns; do
                echo "nameserver $dns_server"
            done
            echo "nameserver 10.0.2.3"
            echo "nameserver 8.8.8.8"
        } > /etc/resolv.conf
        ;;
esac
EOF_UDHCPC

chmod +x "${ROOTFS_DIR}/usr/share/udhcpc/default.script"

cat > "${ROOTFS_DIR}/bin/party" <<'EOF_PARTY'
#!/bin/sh

usage() {
    echo "usage: party install <package>"
    echo "packages: hello, example"
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
    chmod +x /bin/hello_fuse
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

cat > "${ROOTFS_DIR}/init" <<'EOF_INIT'
#!/bin/sh

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
ifconfig lo up 2>/dev/null || true
for netdev in eth0 ens3 enp0s3; do
    ifconfig "$netdev" up 2>/dev/null || continue
    udhcpc -i "$netdev" -n -q -T 2 -t 3 -s /usr/share/udhcpc/default.script 2>/dev/null && break
done
mknod /dev/fuse c 10 229 2>/dev/null || true
chmod 666 /dev/fuse
export HOME=/root
export USER=root
. /etc/profile

exec /bin/sh
EOF_INIT

chmod +x "${ROOTFS_DIR}/init"

(
    cd "${ROOTFS_DIR}"
    find . -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null | gzip -9 > "${OUTPUT_FILE}"
)

echo "Single-user filesystem created at ${OUTPUT_FILE}"
