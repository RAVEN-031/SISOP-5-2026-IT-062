#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="${ROOT_DIR}/osboot"
ROOTFS_DIR="${OSBOOT_DIR}/multi-rootfs"
OUTPUT_FILE="${OSBOOT_DIR}/multi.gz"
CPIO_TOOL="${OSBOOT_DIR}/linux-${KERNEL_VERSION:-6.1.1}/usr/gen_init_cpio"

BUSYBOX_BIN="$(command -v busybox || true)"

if [ -z "${BUSYBOX_BIN}" ]; then
    echo "Error: busybox is required to build the multi-user filesystem." >&2
    exit 1
fi

if ! command -v cpio >/dev/null 2>&1; then
    echo "Error: cpio is required to build the initramfs image." >&2
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "Error: openssl is required to generate password hashes." >&2
    exit 1
fi

if [ ! -x "${CPIO_TOOL}" ]; then
    echo "Error: ${CPIO_TOOL} is required to preserve multi-user ownership." >&2
    echo "Run ./kernel.sh first so the kernel build tools are available." >&2
    exit 1
fi

hash_password() {
    local salt="$1"
    local password="$2"

    openssl passwd -6 -salt "${salt}" "${password}"
}

rm -rf "${ROOTFS_DIR}" "${OUTPUT_FILE}"

mkdir -p \
    "${ROOTFS_DIR}/bin" \
    "${ROOTFS_DIR}/dev" \
    "${ROOTFS_DIR}/proc" \
    "${ROOTFS_DIR}/sys" \
    "${ROOTFS_DIR}/etc" \
    "${ROOTFS_DIR}/tmp" \
    "${ROOTFS_DIR}/root" \
    "${ROOTFS_DIR}/packages/fuse" \
    "${ROOTFS_DIR}/home/henn" \
    "${ROOTFS_DIR}/home/hann" \
    "${ROOTFS_DIR}/home/viii" \
    "${ROOTFS_DIR}/home/kids"

chmod 755 "${ROOTFS_DIR}"
install -m 755 "${ROOT_DIR}/../hello_fuse" \
    "${ROOTFS_DIR}/packages/fuse/hello_fuse"
chmod 755 "${ROOTFS_DIR}/bin" "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" \
    "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/etc" "${ROOTFS_DIR}/home"
chmod 1777 "${ROOTFS_DIR}/tmp"
chmod 700 "${ROOTFS_DIR}/root"

install -m 755 "${BUSYBOX_BIN}" "${ROOTFS_DIR}/bin/busybox"

for applet in \
    sh ash init login getty setsid cttyhack su passwd \
    mount umount mkdir rmdir touch cat echo printf ls ps pwd clear dmesg \
    id whoami chmod chown chgrp sleep reboot poweroff true false test \
    ifconfig route udhcpc ping wget nslookup; do
    ln -s busybox "${ROOTFS_DIR}/bin/${applet}"
done

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

chmod 600 "${ROOTFS_DIR}/etc/shadow"

cat > "${ROOTFS_DIR}/etc/profile" <<'EOF_PROFILE'
export PATH=/bin
export HOME="${HOME:-/root}"
USER_NAME="$(whoami 2>/dev/null || echo root)"
export PS1="${USER_NAME}:\w\$ "

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

cat > "${ROOTFS_DIR}/etc/securetty" <<'EOF_SECURETTY'
console
tty
tty0
ttyS0
EOF_SECURETTY

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

cat > "${ROOTFS_DIR}/etc/inittab" <<'EOF_INITTAB'
::sysinit:/etc/init.d/rcS
::respawn:/bin/cttyhack /bin/login
::restart:/bin/init
::ctrlaltdel:/bin/reboot
::shutdown:/bin/umount -a -r
EOF_INITTAB

mkdir -p "${ROOTFS_DIR}/etc/init.d"
cat > "${ROOTFS_DIR}/etc/init.d/rcS" <<'EOF_RCS'
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
EOF_RCS
chmod +x "${ROOTFS_DIR}/etc/init.d/rcS"

cat > "${ROOTFS_DIR}/init" <<'EOF_INIT'
#!/bin/sh

exec /bin/init
EOF_INIT
chmod +x "${ROOTFS_DIR}/init"

CPIO_LIST="$(mktemp)"
trap 'rm -f "${CPIO_LIST}"' EXIT

cat > "${CPIO_LIST}" <<EOF_CPIO
dir / 0755 0 0
dir /bin 0755 0 0
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
nod /dev/tty 0666 0 0 c 5 0
dir /proc 0755 0 0
dir /sys 0755 0 0
dir /etc 0755 0 0
dir /etc/init.d 0755 0 0
dir /tmp 1777 0 0
dir /root 0700 0 0
dir /home 0755 0 0
dir /home/henn 0700 1000 1000
dir /home/hann 0770 1001 2001
dir /home/viii 0770 1002 2002
dir /home/kids 0770 1003 2003
file /init ${ROOTFS_DIR}/init 0755 0 0
file /bin/busybox ${ROOTFS_DIR}/bin/busybox 0755 0 0
file /bin/party ${ROOTFS_DIR}/bin/party 0755 0 0
file /etc/passwd ${ROOTFS_DIR}/etc/passwd 0644 0 0
file /etc/group ${ROOTFS_DIR}/etc/group 0644 0 0
file /etc/shadow ${ROOTFS_DIR}/etc/shadow 0600 0 0
file /etc/profile ${ROOTFS_DIR}/etc/profile 0644 0 0
file /etc/securetty ${ROOTFS_DIR}/etc/securetty 0644 0 0
file /etc/resolv.conf ${ROOTFS_DIR}/etc/resolv.conf 0644 0 0
file /etc/inittab ${ROOTFS_DIR}/etc/inittab 0644 0 0
file /etc/init.d/rcS ${ROOTFS_DIR}/etc/init.d/rcS 0755 0 0
dir /usr 0755 0 0
dir /usr/share 0755 0 0
dir /usr/share/udhcpc 0755 0 0
file /usr/share/udhcpc/default.script ${ROOTFS_DIR}/usr/share/udhcpc/default.script 0755 0 0
dir /packages 0755 0 0
dir /packages/fuse 0755 0 0
file /packages/fuse/hello_fuse ${ROOTFS_DIR}/packages/fuse/hello_fuse 0755 0 0
EOF_CPIO

for applet in \
    sh ash init login getty setsid cttyhack su passwd cp \
    mount umount mkdir rmdir touch cat echo printf ls ps pwd clear dmesg \
    id whoami chmod chown chgrp sleep reboot poweroff true false test \
    ifconfig route udhcpc ping wget nslookup; do
    echo "slink /bin/${applet} busybox 0777 0 0" >> "${CPIO_LIST}"
done

"${CPIO_TOOL}" "${CPIO_LIST}" | gzip -9 > "${OUTPUT_FILE}"

echo "Multi-user filesystem created at ${OUTPUT_FILE}"
