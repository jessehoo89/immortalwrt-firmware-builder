#!/bin/bash
# inject-autoexpand.sh - 为 ext4 固件注入自动扩容脚本
# 修复：针对 fstab 缺失导致 overlay 未正确设置的问题，采用三重保障机制

IMG="${1:-}"
[ -z "$IMG" ] && { echo "用法：$0 <ext4 镜像文件>"; exit 1; }

# 检查文件是否存在
[ ! -f "$IMG" ] && { echo "错误：文件不存在：$IMG"; exit 1; }

# 跳过 rootfs 文件（由 inject-dhcp.sh 处理）
if [[ "$IMG" == *rootfs* ]]; then
    echo "跳过：rootfs 文件（由 inject-dhcp.sh 处理）: $IMG"
    exit 0
fi

# 跳过非 ext4 固件
if [[ "$IMG" != *ext4* ]]; then
    echo "跳过：非 ext4 固件：$IMG"
    exit 0
fi

echo "处理：$IMG"

# 解压（如果是.gz）
WORK_IMG="$IMG"
TMP_CREATED=false
if [[ "$IMG" == *.gz ]]; then
    echo "解压..."
    TMP_IMG="${IMG%.gz}.tmp"
    gunzip -c "$IMG" > "$TMP_IMG" 2>/dev/null || true
    if [ ! -s "$TMP_IMG" ]; then
        echo "解压失败：$IMG"
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
    echo "警告：无法识别分区信息，跳过：$IMG"
    [ "$TMP_CREATED" = true ] && rm -f "$TMP_IMG"
    exit 0
fi

START_SECTOR=$(echo "$PART_INFO" | awk '{print $2}')
SECTOR_SIZE=512
OFFSET=$((START_SECTOR * SECTOR_SIZE))

echo "rootfs 偏移：$OFFSET 字节 (扇区：$START_SECTOR)"

# 挂载
MNT_DIR=$(mktemp -d)
if ! sudo mount -o loop,offset=$OFFSET "$WORK_IMG" "$MNT_DIR" 2>/dev/null; then
    echo "挂载失败：$IMG"
    [ "$TMP_CREATED" = true ] && rm -f "$TMP_IMG"
    rmdir "$MNT_DIR" 2>/dev/null
    exit 1
fi

# 检查是否已经注入过（检查任意一个脚本是否存在）
if [ -f "$MNT_DIR/etc/uci-defaults/99-auto-expand" ] || \
   [ -f "$MNT_DIR/etc/rc.d/S99auto-expand" ] || \
   [ -f "$MNT_DIR/etc/init.d/auto-expand-boot" ]; then
    echo "已存在自动扩容脚本，跳过：$IMG"
    sudo umount "$MNT_DIR"
    rmdir "$MNT_DIR"
    [ "$TMP_CREATED" = true ] && rm -f "$TMP_IMG"
    exit 0
fi

# 注入自动扩容脚本（三重保障机制）
echo "注入自动扩容脚本..."

# ============================================
# 方案 1: /etc/uci-defaults/99-auto-expand (标准方式)
# ============================================
sudo mkdir -p "$MNT_DIR/etc/uci-defaults/"
sudo tee "$MNT_DIR/etc/uci-defaults/99-auto-expand" > /dev/null << 'INJECT_EOF'
#!/bin/sh
# 自动扩容脚本 - 标准 uci-defaults 方式
# 注意：此脚本可能在 overlay 未正确设置时不执行

LOGTAG="auto-expand"

# 检查是否已经执行过（通过标记文件）
if [ -f "/tmp/.auto-expand-done" ]; then
    exit 0
fi

# 从 /proc/mounts 获取根设备
ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts)

# 处理 /dev/root 符号链接
case "$ROOT_DEV" in
    /dev/root) ROOT_DEV=$(readlink -f /dev/root 2>/dev/null || echo "") ;;
esac
[ -z "$ROOT_DEV" ] && { logger -t "$LOGTAG" "无法获取根设备"; exit 0; }

logger -t "$LOGTAG" "根设备：$ROOT_DEV"

ROOT_SIZE=$(df / | tail -1 | awk '{print $2}')

# 如果已经扩容过（大于 1GB），跳过
if [ "$ROOT_SIZE" -gt 1000000 ]; then
    logger -t "$LOGTAG" "根分区已大于 1GB(${ROOT_SIZE}KB)，跳过扩容"
    touch /tmp/.auto-expand-done
    rm -f "$0"
    exit 0
fi
logger -t "$LOGTAG" "根分区大小：${ROOT_SIZE}KB，需要扩容"

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
        logger -t "$LOGTAG" "不支持的磁盘类型：$ROOT_DEV"
        exit 0 ;;
esac

[ -z "$DISK" ] && { logger -t "$LOGTAG" "无法识别磁盘"; exit 0; }
logger -t "$LOGTAG" "磁盘：$DISK, 分区：$PART_NUM"

# 等待块设备就绪（最多等待 15 秒）
for i in $(seq 1 15); do
    if [ -b "$ROOT_DEV" ]; then
        break
    fi
    sleep 1
done

# 阶段 1: 用 parted 修改分区表
logger -t "$LOGTAG" "阶段 1: parted 修改分区表..."
parted -s "$DISK" resizepart "$PART_NUM" 100% 2>&1 | logger -t "$LOGTAG"

# 阶段 2: 用 partx 通知内核更新分区信息
if command -v partx >/dev/null 2>&1; then
    logger -t "$LOGTAG" "阶段 2: partx 更新内核分区信息..."
    partx -u -n "$PART_NUM" "$DISK" 2>&1 | logger -t "$LOGTAG"
else
    logger -t "$LOGTAG" "partx 不可用，尝试 blockdev --rereadpt"
    blockdev --rereadpt "$DISK" 2>&1 | logger -t "$LOGTAG"
fi

# 再次等待内核识别新分区
sleep 2

# 阶段 3: 扩容文件系统
logger -t "$LOGTAG" "阶段 3: resize2fs 扩容文件系统..."
resize2fs "$ROOT_DEV" 2>&1 | logger -t "$LOGTAG"

# 标记已完成
touch /tmp/.auto-expand-done

# 清理自身
rm -f "$0"
exit 0
INJECT_EOF

sudo chmod +x "$MNT_DIR/etc/uci-defaults/99-auto-expand"

# ============================================
# 方案 2: /etc/rc.d/S99auto-expand (rc.d 方式，确保早期执行)
# ============================================
sudo mkdir -p "$MNT_DIR/etc/rc.d/"
sudo tee "$MNT_DIR/etc/rc.d/S99auto-expand" > /dev/null << 'RCLOCAL_EOF'
#!/bin/sh
# 自动扩容 - rc.d 方式（早期执行，不依赖 overlay）

LOGTAG="auto-expand-rcl"

# 检查是否已经执行过
if [ -f "/tmp/.auto-expand-done" ]; then
    exit 0
fi

# 从 /proc/mounts 获取根设备
ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts)

# 处理 /dev/root 符号链接
case "$ROOT_DEV" in
    /dev/root) ROOT_DEV=$(readlink -f /dev/root 2>/dev/null || echo "") ;;
esac
[ -z "$ROOT_DEV" ] && { echo "[$LOGTAG] 无法获取根设备"; exit 0; }

echo "[$LOGTAG] 根设备：$ROOT_DEV"

ROOT_SIZE=$(df / | tail -1 | awk '{print $2}')

# 如果已经扩容过（大于 1GB），跳过并标记
if [ "$ROOT_SIZE" -gt 1000000 ]; then
    echo "[$LOGTAG] 根分区已大于 1GB，跳过扩容"
    touch /tmp/.auto-expand-done
    exit 0
fi
echo "[$LOGTAG] 根分区大小：${ROOT_SIZE}KB，开始扩容..."

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
        echo "[$LOGTAG] 不支持的磁盘类型：$ROOT_DEV"
        exit 0 ;;
esac

[ -z "$DISK" ] && { echo "[$LOGTAG] 无法识别磁盘"; exit 0; }
echo "[$LOGTAG] 磁盘：$DISK, 分区：$PART_NUM"

# 等待块设备就绪（最多等待 20 秒）
for i in $(seq 1 20); do
    if [ -b "$ROOT_DEV" ]; then
        break
    fi
    echo "[$LOGTAG] 等待块设备就绪... ($i/20)"
    sleep 1
done

# 阶段 1: parted 修改分区表
echo "[$LOGTAG] 阶段 1: parted 修改分区表..."
parted -s "$DISK" resizepart "$PART_NUM" 100% 2>&1 | tee /dev/stderr | head -5

# 阶段 2: partx 更新内核分区信息
if command -v partx >/dev/null 2>&1; then
    echo "[$LOGTAG] 阶段 2: partx 更新内核分区信息..."
    partx -u -n "$PART_NUM" "$DISK" 2>&1 | head -5
else
    echo "[$LOGTAG] partx 不可用，尝试 blockdev --rereadpt"
    blockdev --rereadpt "$DISK" 2>&1 | head -5
fi

# 等待内核识别新分区
echo "[$LOGTAG] 等待内核识别新分区..."
sleep 3

# 阶段 3: resize2fs 扩容文件系统
echo "[$LOGTAG] 阶段 3: resize2fs 扩容文件系统..."
resize2fs "$ROOT_DEV" 2>&1 | head -10

# 验证扩容结果
NEW_SIZE=$(df / | tail -1 | awk '{print $2}')
echo "[$LOGTAG] 扩容后大小：${NEW_SIZE}KB"

# 标记已完成
touch /tmp/.auto-expand-done

echo "[$LOGTAG] 扩容完成！"
exit 0
RCLOCAL_EOF

sudo chmod +x "$MNT_DIR/etc/rc.d/S99auto-expand"

# ============================================
# 方案 3: /etc/init.d/auto-expand-boot (init.d 方式，procd 启动前执行)
# ============================================
sudo mkdir -p "$MNT_DIR/etc/init.d/"
sudo tee "$MNT_DIR/etc/init.d/auto-expand-boot" > /dev/null << 'BOOT_EOF'
#!/bin/sh /etc/rc.common
# Auto-expand script - executed during boot (before procd starts)
# 使用 OpenWrt init.d 标准格式

START=01
STOP=99

USE_PROCD=0

boot() {
    # Skip if already done
    [ -f "/tmp/.auto-expand-done" ] && return 0
    
    # Get root device from /proc/cmdline or /proc/mounts
    ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts)
    case "$ROOT_DEV" in
        /dev/root) ROOT_DEV=$(readlink -f /dev/root 2>/dev/null || echo "") ;;
    esac
    [ -z "$ROOT_DEV" ] && return 0
    
    ROOT_SIZE=$(df / | tail -1 | awk '{print $2}')
    [ "$ROOT_SIZE" -gt 1000000 ] && { touch /tmp/.auto-expand-done; return 0; }
    
    # Identify disk and partition
    case "$ROOT_DEV" in
        /dev/mmcblk*) DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//'); PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*p//') ;;
        /dev/nvme*) DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//'); PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*p//') ;;
        /dev/sd*|/dev/vd*|/dev/xvd*|/dev/loop*) DISK=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//'); PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*[^0-9]//') ;;
        *) return 0 ;;
    esac
    
    [ -z "$DISK" ] && return 0
    
    # Wait for block device
    for i in $(seq 1 15); do
        [ -b "$ROOT_DEV" ] && break
        sleep 1
    done
    
    # Expand partition and filesystem
    echo "auto-expand: Starting expansion on $ROOT_DEV..."
    parted -s "$DISK" resizepart "$PART_NUM" 100% 2>/dev/null
    command -v partx >/dev/null 2>&1 && partx -u -n "$PART_NUM" "$DISK" 2>/dev/null
    sleep 2
    resize2fs "$ROOT_DEV" 2>/dev/null
    touch /tmp/.auto-expand-done
    echo "auto-expand: Done!"
}
BOOT_EOF

sudo chmod +x "$MNT_DIR/etc/init.d/auto-expand-boot"

# ============================================
# 方案 4: 创建 fstab 配置文件（解决 block 服务报错问题）
# ============================================
echo "创建 fstab 配置..."
sudo mkdir -p "$MNT_DIR/etc/config/"
sudo tee "$MNT_DIR/etc/config/fstab" > /dev/null << 'FSTAB_EOF'
config global
    option anon_mount 1
    option anon_swap 0

config mount
    option target /
    option device '/dev/sda2'
    option fstype 'ext4'
    option options 'rw,noatime'
    option enabled 1

config mount
    option target /boot
    option device '/dev/sda1'
    option fstype 'ext2'
    option options 'rw,noatime'
    option enabled 1
FSTAB_EOF

# 卸载
sudo umount "$MNT_DIR"
rmdir "$MNT_DIR"

# 重新压缩（如果是.gz）
if [ "$TMP_CREATED" = true ]; then
    echo "重新压缩..."
    gzip -9c "$TMP_IMG" > "$IMG"
    rm -f "$TMP_IMG"
fi

echo "✅ 完成：$IMG"
