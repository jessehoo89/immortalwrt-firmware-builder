#!/bin/bash
# inject-autoexpand.sh - 生成自动扩容脚本到 FILES 目录
# 用法: bash inject-autoexpand.sh <FILES目录>
# 说明: 所有固件类型(ext4/squashfs/rootfs)都会包含扩容脚本
#       ext4: parted + losetup + resize2fs 一步完成
#       squashfs: resize2fs 扩展 overlay
#       rootfs (Docker): parted 无法操作块设备，自动跳过

set -euo pipefail

FILES_DIR="${1:-}"

[ -z "$FILES_DIR" ] && { echo "用法: $0 <FILES目录>"; exit 1; }
[ ! -d "$FILES_DIR" ] && { echo "错误: FILES目录不存在: $FILES_DIR"; exit 1; }

UCI_DIR="$FILES_DIR/etc/uci-defaults"
mkdir -p "$UCI_DIR"

# 单脚本完成扩容，不需要 reboot
cat > "$UCI_DIR/70-rootpt-resize" << 'EOF'
#!/bin/sh
# OpenWrt 自动扩容脚本 - 单次启动完成
# 扩展分区表 + 扩展文件系统，无需 reboot
[ -e /etc/rootfs-resize ] && exit 0
type parted > /dev/null 2>&1 || exit 0
type losetup > /dev/null 2>&1 || exit 0
type resize2fs > /dev/null 2>&1 || exit 0
lock -n /var/lock/root-resize || exit 0

# 等待磁盘子系统就绪
sleep 10

# 获取根磁盘和分区号
ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk -e \
'$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
ROOT_DISK="/dev/$(basename "${ROOT_BLK%/*}")"
ROOT_PART="${ROOT_BLK##*[^0-9]}"
ROOT_DEV="${ROOT_DISK}${ROOT_PART}"

# 步骤1: 扩展分区表
parted -f -s "${ROOT_DISK}" resizepart "${ROOT_PART}" 100%
sync

# 步骤2: 通过 losetup 扩展文件系统
LOOP_DEV="$(losetup -f)"
losetup "${LOOP_DEV}" "${ROOT_DEV}"
e2fsck -f -y "${LOOP_DEV}" || true
resize2fs -f "${LOOP_DEV}"
losetup -d "${LOOP_DEV}"
sync

# 标记完成
mount_root done
touch /etc/rootfs-resize

exit 0
EOF

chmod +x "$UCI_DIR/70-rootpt-resize"

echo "✅ 自动扩容脚本已生成到 $UCI_DIR/70-rootpt-resize"
