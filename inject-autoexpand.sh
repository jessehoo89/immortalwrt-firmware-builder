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
if [ -f "$MNT_DIR/etc/uci-defaults/99-auto-expand" ]; then
    echo "已存在自动扩容脚本，跳过: $IMG"
    sudo umount "$MNT_DIR"
    rmdir "$MNT_DIR"
    [ "$TMP_CREATED" = true ] && rm -f "$TMP_IMG"
    exit 0
fi

# 注入自动扩容脚本
echo "注入自动扩容脚本..."
sudo mkdir -p "$MNT_DIR/etc/uci-defaults/"
sudo tee "$MNT_DIR/etc/uci-defaults/99-auto-expand" > /dev/null << 'INJECT_EOF'
#!/bin/sh
# 自动扩容脚本 - 首次启动时执行
# 使用 parted + partx + resize2fs 三阶段扩容

LOGTAG="auto-expand"

# 从 /proc/mounts 获取根设备（比 findmnt 可靠，基础系统可能无 findmnt）
ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts)

# 处理 /dev/root 符号链接（部分系统用 PARTUUID 挂载时出现）
case "$ROOT_DEV" in
    /dev/root) ROOT_DEV=$(readlink -f /dev/root 2>/dev/null || echo "") ;;
esac
[ -z "$ROOT_DEV" ] && { logger -t "$LOGTAG" "无法获取根设备"; exit 0; }

logger -t "$LOGTAG" "根设备: $ROOT_DEV"

ROOT_SIZE=$(df / | tail -1 | awk '{print $2}')

# 如果已经扩容过（大于1GB），跳过
if [ "$ROOT_SIZE" -gt 1000000 ]; then
    logger -t "$LOGTAG" "根分区已大于1GB(${ROOT_SIZE}KB)，跳过扩容"
    rm -f "$0"
    exit 0
fi
logger -t "$LOGTAG" "根分区大小: ${ROOT_SIZE}KB，需要扩容"

# 识别磁盘和分区号
case "$ROOT_DEV" in
    /dev/mmcblk*)
        DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//')
        PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*p//')
        ;;
    /dev/nvme*)
        DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//')
        PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*p//')
        ;;
    /dev/sd*|/dev/vd*|/dev/xvd*|/dev/loop*)
        DISK=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
        PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*[^0-9]//')
        ;;
    *)
        logger -t "$LOGTAG" "不支持的磁盘类型: $ROOT_DEV"
        exit 0 ;;
esac

[ -z "$DISK" ] && { logger -t "$LOGTAG" "无法识别磁盘"; exit 0; }
logger -t "$LOGTAG" "磁盘: $DISK, 分区: $PART_NUM"

# 阶段1: 用 parted 修改分区表（写入磁盘）
logger -t "$LOGTAG" "阶段1: parted 修改分区表..."
if parted -s "$DISK" resizepart "$PART_NUM" 100%; then
    logger -t "$LOGTAG" "parted 修改分区表成功"
else
    logger -t "$LOGTAG" "parted 修改分区表失败"
fi

# 阶段2: 用 partx 通知内核更新分区信息（解决根分区挂载中无法 BLKRRPART 的问题）
if command -v partx >/dev/null 2>&1; then
    logger -t "$LOGTAG" "阶段2: partx 更新内核分区信息..."
    if partx -u -n "$PART_NUM" "$DISK"; then
        logger -t "$LOGTAG" "partx 更新成功"
    else
        logger -t "$LOGTAG" "partx 更新失败"
    fi
else
    logger -t "$LOGTAG" "partx 不可用，跳过"
fi

# 阶段3: 扩容文件系统
logger -t "$LOGTAG" "阶段3: resize2fs 扩容文件系统..."
if resize2fs "$ROOT_DEV"; then
    logger -t "$LOGTAG" "resize2fs 扩容成功"
else
    logger -t "$LOGTAG" "resize2fs 扩容失败"
fi

# 清理自身
rm -f "$0"
exit 0
INJECT_EOF

sudo chmod +x "$MNT_DIR/etc/uci-defaults/99-auto-expand"

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
