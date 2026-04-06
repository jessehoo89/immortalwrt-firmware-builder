#!/bin/bash
# inject-autoexpand.sh - 为 ext4 固件注入自动扩容脚本

set -e

IMG="${1:-}"
[ -z "$IMG" ] && { echo "用法: $0 <ext4镜像文件>"; exit 1; }

# 检查文件是否存在
[ ! -f "$IMG" ] && { echo "错误: 文件不存在: $IMG"; exit 1; }

# 检查是否为 ext4 固件
if [[ "$IMG" != *ext4* ]]; then
    echo "跳过: 非 ext4 固件: $IMG"
    exit 0
fi

echo "处理: $IMG"

# 解压（如果是.gz）
WORK_IMG="$IMG"
if [[ "$IMG" == *.gz ]]; then
    echo "解压..."
    gunzip -k "$IMG"
    WORK_IMG="${IMG%.gz}"
fi

# 查找 rootfs 分区偏移
echo "分析分区..."
PART_INFO=$(fdisk -l "$WORK_IMG" 2>/dev/null | grep "Linux filesystem" | tail -1)
if [ -z "$PART_INFO" ]; then
    echo "警告: 无法识别分区信息，跳过: $IMG"
    # 清理解压的文件
    [[ "$IMG" == *.gz && -f "$WORK_IMG" ]] && rm -f "$WORK_IMG"
    exit 0
fi

START_SECTOR=$(echo "$PART_INFO" | awk '{print $2}')
SECTOR_SIZE=512
OFFSET=$((START_SECTOR * SECTOR_SIZE))

echo "rootfs 偏移: $OFFSET 字节"

# 挂载
MNT_DIR=$(mktemp -d)
mount -o loop,offset=$OFFSET "$WORK_IMG" "$MNT_DIR" || { 
    echo "挂载失败: $IMG"
    # 清理解压的文件
    [[ "$IMG" == *.gz && -f "$WORK_IMG" ]] && rm -f "$WORK_IMG"
    rmdir "$MNT_DIR" 2>/dev/null
    exit 1
}

# 注入自动扩容脚本
echo "注入自动扩容脚本..."
mkdir -p "$MNT_DIR/etc/uci-defaults/"
cat > "$MNT_DIR/etc/uci-defaults/99-auto-expand" << 'EOF'
#!/bin/sh
# 自动扩容脚本 - 首次启动时执行

ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_SIZE=$(df / | tail -1 | awk '{print $2}')

# 如果已经扩容过（大于1GB），跳过
[ "$ROOT_SIZE" -gt 1000000 ] && { rm -f "$0"; exit 0; }

# 识别磁盘和分区号
case "$ROOT_DEV" in
    /dev/mmcblk*p*|/dev/nvme*n*p*)
        DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//')
        PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*p//' | sed 's/[^0-9]//')
        ;;
    /dev/sd*|/dev/vd*|/dev/xvd*)
        DISK=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
        PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*[^0-9]//')
        ;;
    *) exit 1 ;;
esac

# 安装必要工具并扩容
opkg update >/dev/null 2>&1
opkg install parted resize2fs >/dev/null 2>&1
parted -s "$DISK" resizepart "$PART_NUM" 100% >/dev/null 2>&1
resize2fs "$ROOT_DEV" >/dev/null 2>&1

# 清理自身
rm -f "$0"
exit 0
EOF

chmod +x "$MNT_DIR/etc/uci-defaults/99-auto-expand"

# 卸载
umount "$MNT_DIR"
rmdir "$MNT_DIR"

# 重新压缩
if [[ "$IMG" == *.gz ]]; then
    echo "压缩: $IMG"
    rm -f "$IMG"
    gzip -9c "$WORK_IMG" > "$IMG"
    rm -f "$WORK_IMG"
fi

echo "✅ 完成: $IMG"
