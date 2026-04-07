#!/bin/bash
# inject-autoexpand.sh - 为 ext4 固件注入自动扩容脚本，为 rootfs 注入 DHCP 关闭脚本

IMG="${1:-}"
[ -z "$IMG" ] && { echo "用法: $0 <镜像文件>"; exit 1; }

# 检查文件是否存在
[ ! -f "$IMG" ] && { echo "错误: 文件不存在: $IMG"; exit 1; }

# ========================================
# 处理 rootfs.tar.gz - 注入关闭 LAN DHCP
# ========================================
if [[ "$IMG" == *rootfs*.tar.gz ]]; then
    echo "处理 rootfs.tar.gz: $IMG"
    
    ADD_DIR=$(mktemp -d)
    mkdir -p "$ADD_DIR/etc/uci-defaults"
    
    cat > "$ADD_DIR/etc/uci-defaults/99-disable-lan-dhcp" << 'EOF'
#!/bin/sh
# 关闭 LAN 口 DHCP 服务（适用于 Docker 环境）
uci set dhcp.lan.ignore='1'
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
rm -f "$0"
exit 0
EOF
    chmod +x "$ADD_DIR/etc/uci-defaults/99-disable-lan-dhcp"
    
    # 检查是否已存在
    if tar -tzf "$IMG" 2>/dev/null | grep -q "etc/uci-defaults/99-disable-lan-dhcp"; then
        echo "  已存在 DHCP 关闭脚本，跳过"
        rm -rf "$ADD_DIR"
        exit 0
    fi
    
    # 流式追加（先删除旧的，再添加新的）
    cp "$IMG" "${IMG}.bak"
    
    # 使用临时文件处理 tar 操作
    TMP_UNCOMPRESSED=$(mktemp)
    gunzip -c "$IMG" > "$TMP_UNCOMPRESSED"
    
    # 删除可能存在的旧文件，然后添加新文件
    tar --delete -f "$TMP_UNCOMPRESSED" etc/uci-defaults/99-disable-lan-dhcp 2>/dev/null || true
    tar -C "$ADD_DIR" -rf "$TMP_UNCOMPRESSED" etc
    
    # 压缩
    gzip -9c "$TMP_UNCOMPRESSED" > "${IMG}.tmp"
    rm -f "$TMP_UNCOMPRESSED"
    
    if [ -s "${IMG}.tmp" ]; then
        mv "${IMG}.tmp" "$IMG"
        rm -rf "$ADD_DIR" "${IMG}.bak"
        echo "✅ 完成: 已注入 DHCP 关闭脚本"
    else
        echo "❌ 失败，恢复原文件"
        mv "${IMG}.bak" "$IMG"
        rm -rf "$ADD_DIR" "${IMG}.tmp"
        exit 1
    fi
    
    exit 0
fi

# ========================================
# 跳过其他 rootfs 文件（非 tar.gz 格式）
# ========================================
if [[ "$IMG" == *rootfs* ]]; then
    echo "跳过: rootfs 文件（非 tar.gz 格式）: $IMG"
    exit 0
fi

# ========================================
# 处理 ext4 固件 - 注入自动扩容脚本
# ========================================
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

sudo chmod +x "$MNT_DIR/etc/uci-defaults/99-auto-expand"

# 卸载
sudo umount "$MNT_DIR"
rmdir "$MNT_DIR"

# 重新压缩
if [[ "$IMG" == *.gz ]]; then
    echo "压缩: $IMG"
    rm -f "$IMG"
    gzip -9c "$WORK_IMG" > "$IMG"
    rm -f "$WORK_IMG"
fi

echo "✅ 完成: $IMG"
