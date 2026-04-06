#!/bin/bash
# inject-autoexpand.sh - 为 ext4 固件注入自动扩容脚本
# 使用 debugfs 方法，无需 mount 权限

IMG="${1:-}"
[ -z "$IMG" ] && { echo "用法: $0 <ext4镜像文件>"; exit 1; }

# 检查文件是否存在
[ ! -f "$IMG" ] && { echo "错误: 文件不存在: $IMG"; exit 1; }

# 检查是否为 ext4 固件（跳过 rootfs 文件，因为没有分区表）
if [[ "$IMG" == *rootfs* ]]; then
    echo "跳过: rootfs 文件（无分区表）: $IMG"
    exit 0
fi

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
PART_SIZE=$(echo "$PART_INFO" | awk '{print $4}')

echo "rootfs 分区: 扇区 $START_SECTOR, 大小 $PART_SIZE"

# 提取 rootfs 分区为独立镜像
PART_IMG="${WORK_IMG}.part"
dd if="$WORK_IMG" of="$PART_IMG" bs=512 skip=$START_SECTOR count=$PART_SIZE 2>/dev/null

# 检查是否已经注入过
if debugfs "$PART_IMG" -R "ls /etc/uci-defaults" 2>/dev/null | grep -q "99-auto-expand"; then
    echo "已存在自动扩容脚本，跳过: $IMG"
    rm -f "$PART_IMG"
    [ "$TMP_CREATED" = true ] && rm -f "$TMP_IMG"
    exit 0
fi

# 创建自动扩容脚本
SCRIPT_FILE="/tmp/99-auto-expand.$$"
cat > "$SCRIPT_FILE" << 'INJECT_EOF'
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
opkg install parted e2fsprogs-resize2fs >/dev/null 2>&1
parted -s "$DISK" resizepart "$PART_NUM" 100% >/dev/null 2>&1
resize2fs "$ROOT_DEV" >/dev/null 2>&1

# 清理自身
rm -f "$0"
exit 0
INJECT_EOF

chmod +x "$SCRIPT_FILE"

# 使用 debugfs 注入脚本
echo "注入自动扩容脚本..."
debugfs -w "$PART_IMG" -R "write $SCRIPT_FILE /etc/uci-defaults/99-auto-expand" >/dev/null 2>&1
debugfs -w "$PART_IMG" -R "set_inode_field /etc/uci-defaults/99-auto-expand mode 0100755" >/dev/null 2>&1

# 将修改后的分区写回原镜像
echo "更新镜像..."
dd if="$PART_IMG" of="$WORK_IMG" bs=512 seek=$START_SECTOR conv=notrunc 2>/dev/null

# 清理临时文件
rm -f "$SCRIPT_FILE" "$PART_IMG"

# 重新压缩
if [[ "$IMG" == *.gz ]]; then
    echo "压缩: $IMG"
    rm -f "$IMG"
    gzip -9c "$WORK_IMG" > "$IMG"
    rm -f "$WORK_IMG"
fi

echo "✅ 完成: $IMG"
