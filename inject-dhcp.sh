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

cat > "$ADD_DIR/etc/uci-defaults/99-disable-lan-dhcp" << 'EOF'
#!/bin/sh
uci set dhcp.lan.ignore='1'
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
rm -f "$0"
exit 0
EOF
chmod +x "$ADD_DIR/etc/uci-defaults/99-disable-lan-dhcp"

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

# 8. 双重验证（使用灵活匹配）
echo "  验证..."
if ! tar -tzf "$IMG" >/dev/null 2>&1; then
    echo "  ❌ tar 文件损坏"
    exit 1
fi

if ! tar -tzf "$IMG" | grep -qE "(^|/)etc/uci-defaults/99-disable-lan-dhcp$"; then
    echo "  ❌ 脚本未正确注入"
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
