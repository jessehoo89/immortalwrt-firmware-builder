#!/bin/bash
# inject-autoexpand.sh - 为 ext4 固件注入自动扩容脚本

IMG="${1:-}"
[ -z "$IMG" ] && { echo "用法: $0 <ext4镜像文件>"; exit 1; }

# 检查文件是否存在
[ ! -f "$IMG" ] && { echo "错误: 文件不存在: $IMG"; exit 1; }

# 跳过 rootfs 文件（由 inject-dhcp.sh 处理）
if [[ "$IMG" == *rootfs* ]]; then
    echo "跳过: rootfs 文件（由 inject-dhcp.sh 处理）: $IMG"
    exit 0
fi

# 跳过非 ext4 固件
if [[ "$IMG" != *ext4* ]]; then
    echo "跳过: 非 ext4 固件: $IMG"
    exit 0
fi

echo "处理: $IMG"

# 解压（如果是.gz）
WORK_IMG="$IMG"
TMP_CREATED=false
if [[ "$IMG" == *.gz ]]; then
    echo "解压..."
    TMP_IMG="${IMG%.gz}.tmp"
    gunzip -c "$IMG" > "$TMP_IMG" 2>/dev/null || true
    if [ ! -s "$TMP_IMG" ]; then
        echo "解压失败: $IMG"
        rm -f "$TMP_IMG"
        exit 1
    fi
    WORK_IMG="$TMP_IMG"
    TMP_CREATED=true
fi

# 分析分区信息
echo "分析分区..."
PART_INFO=$(fdisk -l "$WORK_IMG" 2>/dev/null | grep "Linux" | grep -v "swap" | tail -1)
if [ -z "$PART_INFO" ]; then
    echo "警告: 无法识别分区信息，跳过: $IMG"
    [ "$TMP_CREATED" = true ] && rm -f "$TMP_IMG"
    exit 0
fi

START_SECTOR=$(echo "$PART_INFO" | awk '{print $2}')
SECTOR_SIZE=512
OFFSET=$((START_SECTOR * SECTOR_SIZE))

echo "rootfs 偏移: $OFFSET 字节 (扇区: $START_SECTOR)"

# 挂载
MNT_DIR=$(mktemp -d)
if ! sudo mount -o loop,offset=$OFFSET "$WORK_IMG" "$MNT_DIR" 2>/dev/null; then
    echo "挂载失败: $IMG"
    [ "$TMP_CREATED" = true ] && rm -f "$TMP_IMG"
    rmdir "$MNT_DIR" 2>/dev/null
    exit 1
fi

# 检查是否已经注入过
if [ -f "$MNT_DIR/etc/uci-defaults/70-rootpt-resize" ]; then
    echo "已存在自动扩容脚本，跳过: $IMG"
    sudo umount "$MNT_DIR"
    rmdir "$MNT_DIR"
    [ "$TMP_CREATED" = true ] && rm -f "$TMP_IMG"
    exit 0
fi

# 注入官方 OpenWrt 自动扩容脚本
echo "注入自动扩容脚本..."
sudo mkdir -p "$MNT_DIR/etc/uci-defaults/"

# 阶段1: 扩展分区表
sudo tee "$MNT_DIR/etc/uci-defaults/70-rootpt-resize" > /dev/null << 'INJECT_EOF'
#!/bin/sh
# OpenWrt 官方扩容脚本 - 阶段1: 扩展分区表
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
INJECT_EOF

# 阶段2: 扩展文件系统
sudo tee "$MNT_DIR/etc/uci-defaults/80-rootfs-resize" > /dev/null << 'INJECT_EOF'
#!/bin/sh
# OpenWrt 官方扩容脚本 - 阶段2: 扩展文件系统
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
INJECT_EOF

# 添加到 sysupgrade.conf 保留扩容脚本
if ! grep -q "70-rootpt-resize" "$MNT_DIR/etc/sysupgrade.conf" 2>/dev/null; then
    echo "/etc/uci-defaults/70-rootpt-resize" | sudo tee -a "$MNT_DIR/etc/sysupgrade.conf" > /dev/null
    echo "/etc/uci-defaults/80-rootfs-resize" | sudo tee -a "$MNT_DIR/etc/sysupgrade.conf" > /dev/null
fi

sudo chmod +x "$MNT_DIR/etc/uci-defaults/70-rootpt-resize"
sudo chmod +x "$MNT_DIR/etc/uci-defaults/80-rootfs-resize"

# 卸载
sudo umount "$MNT_DIR"
rmdir "$MNT_DIR"

# 重新压缩（如果是.gz）
if [ "$TMP_CREATED" = true ]; then
    echo "重新压缩..."
    gzip -9c "$TMP_IMG" > "$IMG"
    rm -f "$TMP_IMG"
fi

echo "✅ 完成: $IMG"
