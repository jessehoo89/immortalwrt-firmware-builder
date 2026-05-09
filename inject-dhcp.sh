#!/bin/bash
# inject-dhcp.sh - 向 rootfs.tar.gz 注入 DHCP 关闭脚本（最终修正版）

set -euo pipefail

IMG="${1:-}"
[ -z "$IMG" ] && { echo "用法: $0 <rootfs.tar.gz>"; exit 1; }
[[ "$IMG" != *rootfs*.tar.gz ]] && { echo "跳过: 非 rootfs.tar.gz"; exit 0; }

ADD_DIR=""
TMP_DIR=""
TMP_UNCOMPRESSED=""
BAK_FILE=""

cleanup() {
    local exit_code=$?
    rm -rf "$ADD_DIR" 2>/dev/null || true
    rm -f "$TMP_UNCOMPRESSED" 2>/dev/null || true
    rm -f "$BAK_FILE" 2>/dev/null || true
    
    if [ $exit_code -ne 0 ] && [ -n "${IMG:-}" ]; then
        rm -f "${IMG}.tmp" 2>/dev/null || true
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

echo "处理: $IMG"

# 1. 准备注入文件
ADD_DIR=$(mktemp -d)
mkdir -p "$ADD_DIR/etc/uci-defaults"

# DHCP关闭脚本
cat > "$ADD_DIR/etc/uci-defaults/99-disable-lan-dhcp" << 'EOF'
#!/bin/sh
uci set dhcp.lan.ignore='1'
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
rm -f "$0"
exit 0
EOF
chmod +x "$ADD_DIR/etc/uci-defaults/99-disable-lan-dhcp"

# 自动扩容脚本（首次启动时扩容rootfs到整个分区）
cat > "$ADD_DIR/etc/uci-defaults/99-auto-expand" << 'EXPANDEOF'
#!/bin/sh
# 自动扩容脚本 - 首次启动时执行
# 使用 parted + partx + e2fsck + resize2fs 四阶段扩容

LOGTAG="auto-expand"

# 从 /proc/mounts 获取根设备
ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts)

# 处理 /dev/root 符号链接
case "$ROOT_DEV" in
    /dev/root) ROOT_DEV=$(readlink -f /dev/root 2>/dev/null || echo "") ;;
esac
[ -z "$ROOT_DEV" ] && { logger -t "$LOGTAG" "无法获取根设备"; exit 0; }

logger -t "$LOGTAG" "根设备: $ROOT_DEV"

ROOT_SIZE=$(df / | tail -1 | awk '{print $2}')

# 如果已经扩容过（大于1GB），跳过
if [ "$ROOT_SIZE" -gt 1000000 ]; then
    logger -t "$LOGTAG" "根分区已大于1MB(${ROOT_SIZE}KB)，跳过扩容"
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

# 阶段1: 用 parted 修改分区表
logger -t "$LOGTAG" "阶段1: parted 修改分区表..."
if parted -s "$DISK" resizepart "$PART_NUM" 100% 2>/dev/null; then
    logger -t "$LOGTAG" "parted 修改分区表成功"
else
    logger -t "$LOGTAG" "parted 修改分区表失败或无需修改"
fi

# 阶段2: 用 partx 通知内核更新分区信息
if command -v partx >/dev/null 2>&1; then
    logger -t "$LOGTAG" "阶段2: partx 更新内核分区信息..."
    if partx -u -n "$PART_NUM" "$DISK" 2>/dev/null; then
        logger -t "$LOGTAG" "partx 更新成功"
    else
        logger -t "$LOGTAG" "partx 更新失败或无需更新"
    fi
fi

# 阶段3: 修复文件系统（在线扩容前必须修复）
logger -t "$LOGTAG" "阶段3: e2fsck 修复文件系统..."
if command -v e2fsck >/dev/null 2>&1; then
    # -f: 强制检查 -y: 自动修复 -n: 只读模式不修改（首选用-n，失败再用-y）
    if e2fsck -f -n "$ROOT_DEV" 2>/dev/null; then
        logger -t "$LOGTAG" "e2fsck 检查通过"
    else
        logger -t "$LOGTAG" "e2fsck 发现问题，尝试修复..."
        e2fsck -f -y "$ROOT_DEV" 2>/dev/null || true
    fi
else
    logger -t "$LOGTAG" "e2fsck 不可用，跳过修复"
fi

# 阶段4: 扩容文件系统
logger -t "$LOGTAG" "阶段4: resize2fs 扩容文件系统..."
if resize2fs "$ROOT_DEV" 2>/dev/null; then
    logger -t "$LOGTAG" "resize2fs 扩容成功"
else
    logger -t "$LOGTAG" "resize2fs 在线扩容失败，尝试离线扩容"
    # 在线扩容失败时，尝试强制修复后重试
    if command -v e2fsck >/dev/null 2>&1; then
        e2fsck -f -y "$ROOT_DEV" 2>/dev/null || true
        resize2fs "$ROOT_DEV" 2>/dev/null || logger -t "$LOGTAG" "resize2fs 最终失败"
    fi
fi

# 清理自身
rm -f "$0"
exit 0
EXPANDEOF
chmod +x "$ADD_DIR/etc/uci-defaults/99-auto-expand"

# 2. 检查是否已存在（使用灵活匹配，兼容 ./ 前缀）
if tar -tzf "$IMG" 2>/dev/null | grep -qE "(^|/)etc/uci-defaults/99-disable-lan-dhcp$"; then
    echo "  已存在 DHCP 脚本，跳过"
    exit 0
fi

# 3. 备份
BAK_FILE="${IMG}.bak.$(date +%s)"
cp "$IMG" "$BAK_FILE"

# 4. 智能选择临时目录
ROOTFS_SIZE=$(stat -c%s "$IMG" 2>/dev/null || stat -f%z "$IMG" 2>/dev/null || echo 0)
NEEDED_KB=$((ROOTFS_SIZE * 3 / 1024))

SHM_AVAILABLE=$(df /dev/shm 2>/dev/null | tail -1 | awk '{print $4}' || echo 0)

if [ -d /dev/shm ] && [ "$SHM_AVAILABLE" -gt "$NEEDED_KB" ]; then
    TMP_DIR="/dev/shm/inject-dhcp-$$"
    mkdir -p "$TMP_DIR"
    echo "  使用内存盘 (/dev/shm)"
else
    TMP_DIR=$(mktemp -d)
    echo "  使用临时目录: $TMP_DIR"
fi

TMP_UNCOMPRESSED="$TMP_DIR/rootfs.tar"

# 5. 解压
echo "  解压 gzip..."
gunzip -c "$IMG" > "$TMP_UNCOMPRESSED" || {
    echo "  ❌ 解压失败"
    exit 1
}

# 6. 修改 tar
echo "  修改 tar 归档..."
tar --delete -f "$TMP_UNCOMPRESSED" etc/uci-defaults/99-disable-lan-dhcp 2>/dev/null || true
tar --delete -f "$TMP_UNCOMPRESSED" ./etc/uci-defaults/99-disable-lan-dhcp 2>/dev/null || true

if ! tar -C "$ADD_DIR" -rf "$TMP_UNCOMPRESSED" etc; then
    echo "  ❌ 追加文件失败"
    exit 1
fi

# 7. 重新压缩
echo "  重新压缩..."
rm -f "$IMG"

if command -v pigz >/dev/null 2>&1; then
    pigz -9c "$TMP_UNCOMPRESSED" > "$IMG.tmp"
else
    gzip -9c "$TMP_UNCOMPRESSED" > "$IMG.tmp"
fi

mv "$IMG.tmp" "$IMG"

# 8. 三重验证（使用灵活匹配）
echo "  验证..."
if ! tar -tzf "$IMG" >/dev/null 2>&1; then
    echo "  ❌ tar 文件损坏"
    exit 1
fi

if ! tar -tzf "$IMG" | grep -qE "(^|/)etc/uci-defaults/99-disable-lan-dhcp$"; then
    echo "  ❌ DHCP脚本未正确注入"
    exit 1
fi

if ! tar -tzf "$IMG" | grep -qE "(^|/)etc/uci-defaults/99-auto-expand$"; then
    echo "  ❌ 自动扩容脚本未正确注入"
    exit 1
fi

# 统计
NEW_SIZE=$(stat -c%s "$IMG")
if [ "$ROOTFS_SIZE" -gt 0 ]; then
    RATIO=$(( (NEW_SIZE - ROOTFS_SIZE) * 100 / ROOTFS_SIZE ))
    echo "  大小变化: ${RATIO}%"
fi

echo "✅ 完成: $IMG"
rm -f "$BAK_FILE"
