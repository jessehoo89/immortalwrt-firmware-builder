#!/bin/bash
# inject-autoexpand.sh - 生成 OpenWrt 官方自动扩容脚本到 FILES 目录
# 用法: bash inject-autoexpand.sh <FILES目录>
# 说明: 所有固件类型(ext4/squashfs/rootfs)都会包含扩容脚本
#       官方脚本内置检查机制，不适用的固件类型会自动跳过

set -euo pipefail

FILES_DIR="${1:-}"

[ -z "$FILES_DIR" ] && { echo "用法: $0 <FILES目录>"; exit 1; }
[ ! -d "$FILES_DIR" ] && { echo "错误: FILES目录不存在: $FILES_DIR"; exit 1; }

UCI_DIR="$FILES_DIR/etc/uci-defaults"
mkdir -p "$UCI_DIR"

# 阶段1: 扩展分区表（首次启动执行后 reboot）
cat > "$UCI_DIR/70-rootpt-resize" << 'EOF'
#!/bin/sh
if [ ! -e /etc/rootpt-resize ] \
&& type parted > /dev/null \
&& lock -n /var/lock/root-resize
then
ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk -e \
'$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
ROOT_DISK="/dev/$(basename "${ROOT_BLK%/*}")"
ROOT_PART="${ROOT_BLK##*[^0-9]}"
parted -f -s "${ROOT_DISK}" \
resizepart "${ROOT_PART}" 100%
mount_root done
touch /etc/rootpt-resize

if [ -e /boot/cmdline.txt ]
then
NEW_UUID=`blkid ${ROOT_DISK}p${ROOT_PART} | sed -n 's/.*PARTUUID="\([^"]*\)".*/\1/p'`
sed -i "s/PARTUUID=[^ ]*/PARTUUID=${NEW_UUID}/" /boot/cmdline.txt
fi

reboot
fi
exit 1
EOF

# 阶段2: 扩展文件系统（重启后执行）
cat > "$UCI_DIR/80-rootfs-resize" << 'EOF'
#!/bin/sh
if [ ! -e /etc/rootfs-resize ] \
&& [ -e /etc/rootpt-resize ] \
&& type losetup > /dev/null \
&& type resize2fs > /dev/null \
&& lock -n /var/lock/root-resize
then
ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk -e \
'$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
ROOT_DEV="/dev/${ROOT_BLK##*/}"
LOOP_DEV="$(awk -e '$5=="/overlay"{print $9}' \
/proc/self/mountinfo)"
if [ -z "${LOOP_DEV}" ]
then
LOOP_DEV="$(losetup -f)"
losetup "${LOOP_DEV}" "${ROOT_DEV}"
fi
resize2fs -f "${LOOP_DEV}"
mount_root done
touch /etc/rootfs-resize
reboot
fi
exit 1
EOF

# 阶段3: 将扩容脚本加入 sysupgrade.conf，升级后保留
cat > "$UCI_DIR/99-expand-sysupgrade" << 'EOF'
#!/bin/sh
if ! grep -q "70-rootpt-resize" /etc/sysupgrade.conf 2>/dev/null; then
    echo "/etc/uci-defaults/70-rootpt-resize" >> /etc/sysupgrade.conf
    echo "/etc/uci-defaults/80-rootfs-resize" >> /etc/sysupgrade.conf
fi
rm -f "$0"
exit 0
EOF

chmod +x "$UCI_DIR/70-rootpt-resize" "$UCI_DIR/80-rootfs-resize" "$UCI_DIR/99-expand-sysupgrade"

echo "✅ 自动扩容脚本已生成到 $UCI_DIR"
