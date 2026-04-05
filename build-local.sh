#!/bin/bash
# ImmortalWrt 本地构建脚本
# 支持交互式选择构建类型、启动模式和代理

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 函数：获取 GitHub 最新 release tag
get_latest_tag() {
    local repo=$1
    local tag=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | grep -E '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    echo "$tag"
}

echo "=========================================="
echo "ImmortalWrt 本地构建脚本"
echo "=========================================="
echo ""

# === 步骤 1: 选择配置 ===
log_step "1. 选择配置"

# 镜像源选择
echo "请选择镜像源:"
echo "  1) downloads.immortalwrt.org (官方)"
echo "  2) mirrors.ustc.edu.cn (中科大)"
read -p "请输入选项 (1-2，默认 1): " MIRROR_CHOICE
MIRROR_CHOICE=${MIRROR_CHOICE:-1}

case $MIRROR_CHOICE in
    1) MIRROR="https://downloads.immortalwrt.org" ;;
    2) MIRROR="https://mirrors.ustc.edu.cn/immortalwrt" ;;
    *) MIRROR="https://downloads.immortalwrt.org" ;;
esac
log_info "使用镜像: $MIRROR"

# 代理选择
echo ""
echo "是否使用 GitHub 代理? (网络问题时使用)"
echo "  1) 不使用 (直连)"
echo "  2) 使用 gh-proxy.org"
read -p "请输入选项 (1-2，默认 1): " PROXY_CHOICE
PROXY_CHOICE=${PROXY_CHOICE:-1}

case $PROXY_CHOICE in
    1) GHPROXY="" ;;
    2) GHPROXY="https://gh-proxy.org" ;;
    *) GHPROXY="" ;;
esac

if [ -n "$GHPROXY" ]; then
    log_info "使用代理: $GHPROXY"
else
    log_info "不使用代理 (直连)"
fi

# GitHub 下载 URL 前缀
if [ -n "$GHPROXY" ]; then
    GHPREFIX="${GHPROXY}/"
else
    GHPREFIX=""
fi

# 构建类型选择
echo ""
echo "请选择固件类型:"
echo "  1) squashfs (只读根文件系统，更安全，推荐)"
echo "  2) ext4 (可写根文件系统，更灵活)"
echo "  3) 两者都构建"
read -p "请输入选项 (1-3，默认 1): " TYPE_CHOICE
TYPE_CHOICE=${TYPE_CHOICE:-1}

case $TYPE_CHOICE in
    1) FIRMWARE_TYPE="squashfs" ;;
    2) FIRMWARE_TYPE="ext4" ;;
    3) FIRMWARE_TYPE="both" ;;
    *) FIRMWARE_TYPE="squashfs" ;;
esac
log_info "固件类型: $FIRMWARE_TYPE"

# 启动模式选择
echo ""
echo "请选择启动模式:"
echo "  1) combined (传统 BIOS)"
echo "  2) combined-efi (UEFI)"
echo "  3) 两者都构建"
read -p "请输入选项 (1-3，默认 3): " BOOT_CHOICE
BOOT_CHOICE=${BOOT_CHOICE:-3}

case $BOOT_CHOICE in
    1) BOOT_MODE="combined" ;;
    2) BOOT_MODE="combined-efi" ;;
    3) BOOT_MODE="both" ;;
    *) BOOT_MODE="both" ;;
esac
log_info "启动模式: $BOOT_MODE"

# 虚拟机镜像格式选择
echo ""
echo "请选择虚拟机镜像格式:"
echo "  1) img.gz (RAW 格式压缩，仅物理机刷写)"
echo "  2) qcow2.gz (QEMU/KVM)"
echo "  3) vmdk.gz (VMware)"
echo "  4) vdi.gz (VirtualBox)"
echo "  5) vhdx.gz (Hyper-V)"
echo "  6) 全部格式"
read -p "请输入选项 (1-6，默认 6): " VM_CHOICE
VM_CHOICE=${VM_CHOICE:-6}

case $VM_CHOICE in
    1) VM_FORMAT="img" ;;
    2) VM_FORMAT="qcow2" ;;
    3) VM_FORMAT="vmdk" ;;
    4) VM_FORMAT="vdi" ;;
    5) VM_FORMAT="vhdx" ;;
    6) VM_FORMAT="all" ;;
    *) VM_FORMAT="all" ;;
esac

if [ "$VM_FORMAT" = "all" ]; then
    log_info "虚拟机镜像格式: 全部 (img, qcow2, vmdk, vdi, vhdx)"
else
    log_info "虚拟机镜像格式: $VM_FORMAT"
fi

echo ""

# === 步骤 2: 获取版本信息 ===
log_step "2. 获取版本信息..."

VERSION=$(curl -s "$MIRROR/releases/" | grep -oE '/immortalwrt/releases/[0-9]+\.[0-9]+\.[0-9]+[^/]*' | sed 's|.*/||' | grep -v 'SNAPSHOT' | grep -v 'rc' | sort -V | tail -1)
[ -z "$VERSION" ] && VERSION="24.10.5"
log_info "ImmortalWrt 版本: ${VERSION}"

# 获取 kmods 目录
KMODS_SUBDIR=$(curl -s "$MIRROR/releases/${VERSION}/targets/x86/64/kmods/" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[0-9a-f-]+' | head -1)
[ -z "$KMODS_SUBDIR" ] && KMODS_SUBDIR="6.6.122-1-e7e50fbc0aafa7443418a79928da2602"
log_info "KMods 目录: ${KMODS_SUBDIR}"

# 获取第三方软件版本
EASYTIER_TAG=$(get_latest_tag "EasyTier/luci-app-easytier")
LUCKY_TAG=$(get_latest_tag "gdy666/luci-app-lucky")
ADG_LUCI_TAG=$(get_latest_tag "stevenjoezhang/luci-app-adguardhome")
ADG_CORE_TAG=$(get_latest_tag "AdguardTeam/AdGuardHome")
MIHOMO_TAG=$(get_latest_tag "MetaCubeX/mihomo")

log_info "EasyTier: ${EASYTIER_TAG:-v2.5.0}"
log_info "Lucky: ${LUCKY_TAG:-v2.19.5}"
log_info "AdGuardHome LuCI: ${ADG_LUCI_TAG:-v1.19}"
log_info "AdGuardHome Core: ${ADG_CORE_TAG:-v0.107.55}"
log_info "Mihomo: ${MIHOMO_TAG:-v1.19.0}"

# === 步骤 3: 下载 ImageBuilder ===
log_step "3. 下载 ImageBuilder..."

cd /tmp
rm -rf immortalwrt-imagebuilder-*

if [ ! -d "immortalwrt-imagebuilder-${VERSION}-x86-64.Linux-x86_64" ]; then
    log_info "下载 ImageBuilder ${VERSION}..."
    wget -q "${MIRROR}/releases/${VERSION}/targets/x86/64/immortalwrt-imagebuilder-${VERSION}-x86-64.Linux-x86_64.tar.zst"
    tar -I zstd -xf immortalwrt-imagebuilder-*.tar.zst
    rm -f *.tar.zst
fi

cd immortalwrt-imagebuilder-${VERSION}-x86-64.Linux-x86_64
log_info "ImageBuilder 目录: $(pwd)"

# === 步骤 4: 配置软件源 ===
log_step "4. 配置软件源..."

cat > repositories.conf << EOF
src/gz immortalwrt_core ${MIRROR}/releases/${VERSION}/targets/x86/64/packages
src/gz immortalwrt_base ${MIRROR}/releases/${VERSION}/packages/x86_64/base
src/gz immortalwrt_kmods ${MIRROR}/releases/${VERSION}/targets/x86/64/kmods/${KMODS_SUBDIR}
src/gz immortalwrt_luci ${MIRROR}/releases/${VERSION}/packages/x86_64/luci
src/gz immortalwrt_packages ${MIRROR}/releases/${VERSION}/packages/x86_64/packages
src/gz immortalwrt_routing ${MIRROR}/releases/${VERSION}/packages/x86_64/routing
src/gz immortalwrt_telephony ${MIRROR}/releases/${VERSION}/packages/x86_64/telephony
src imagebuilder file:packages
EOF

log_info "软件源已配置"

# === 步骤 5: 下载第三方 IPK ===
log_step "5. 下载第三方 IPK..."

# EasyTier
log_info "下载 EasyTier..."
wget -q "${GHPREFIX}https://github.com/EasyTier/luci-app-easytier/releases/download/${EASYTIER_TAG}/EasyTier-${EASYTIER_TAG}-x86_64-22.03.7.zip"
unzip -q EasyTier-*.zip && rm -f EasyTier-*.zip

# Lucky
log_info "下载 Lucky..."
wget -q "${GHPREFIX}https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG}/luci-app-lucky_2.2.2-r1_all.ipk"
wget -q "${GHPREFIX}https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG}/luci-i18n-lucky-zh-cn_25.051.13443.e78d498_all.ipk"
wget -q "${GHPREFIX}https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG}/lucky_2.19.5_Openwrt_x86_64.ipk"

# AdGuardHome LuCI
log_info "下载 AdGuardHome LuCI..."
wget -q "${GHPREFIX}https://github.com/stevenjoezhang/luci-app-adguardhome/releases/download/${ADG_LUCI_TAG}/luci-app-adguardhome_1.19_all.ipk"
wget -q "${GHPREFIX}https://github.com/stevenjoezhang/luci-app-adguardhome/releases/download/${ADG_LUCI_TAG}/luci-i18n-adguardhome-zh-cn_260130.50632_all.ipk"

# === 步骤 6: 准备 FILES 目录 ===
log_step "6. 准备 FILES 目录..."

mkdir -p FILES/usr/bin/AdGuardHome FILES/etc/openclash/core FILES/etc/opkg

# distfeeds.conf
cat > FILES/etc/opkg/distfeeds.conf << EOF
src/gz immortalwrt_core ${MIRROR}/releases/${VERSION}/targets/x86/64/packages
src/gz immortalwrt_base ${MIRROR}/releases/${VERSION}/packages/x86_64/base
src/gz immortalwrt_kmods ${MIRROR}/releases/${VERSION}/targets/x86/64/kmods/${KMODS_SUBDIR}
src/gz immortalwrt_luci ${MIRROR}/releases/${VERSION}/packages/x86_64/luci
src/gz immortalwrt_packages ${MIRROR}/releases/${VERSION}/packages/x86_64/packages
src/gz immortalwrt_routing ${MIRROR}/releases/${VERSION}/packages/x86_64/routing
src/gz immortalwrt_telephony ${MIRROR}/releases/${VERSION}/packages/x86_64/telephony
EOF

# AdGuardHome 核心
log_info "下载 AdGuardHome 核心..."
wget -q "${GHPREFIX}https://github.com/AdguardTeam/AdGuardHome/releases/download/${ADG_CORE_TAG}/AdGuardHome_linux_amd64.tar.gz"
tar -xzf AdGuardHome_linux_amd64.tar.gz
mv AdGuardHome/AdGuardHome FILES/usr/bin/AdGuardHome/
chmod +x FILES/usr/bin/AdGuardHome/AdGuardHome
rm -rf AdGuardHome AdGuardHome_linux_amd64.tar.gz

# Mihomo 核心
log_info "下载 Mihomo 核心..."
wget -q "${GHPREFIX}https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_TAG}/mihomo-linux-amd64-${MIHOMO_TAG}.gz"
gunzip -c mihomo-*.gz > FILES/etc/openclash/core/clash_meta
chmod +x FILES/etc/openclash/core/clash_meta
rm -f mihomo-*.gz

# === 步骤 7: 构建固件 ===
log_step "7. 构建固件..."

# 检查并安装 qemu-img (用于转换虚拟机格式)
if ! command -v qemu-img &> /dev/null; then
    log_info "安装 qemu-img 用于虚拟机格式转换..."
    sudo apt-get update && sudo apt-get install -y qemu-utils 2>/dev/null || true
fi

PACKAGES="kmod-tun easytier miniupnpd-nftables lucky luci-app-adguardhome luci-app-openclash luci-app-argon-config luci-app-autoreboot luci-app-msd_lite luci-app-wol luci-app-easytier luci-app-zerotier luci-app-diskman luci-app-lucky luci-i18n-zerotier-zh-cn luci-i18n-autoreboot-zh-cn luci-i18n-wol-zh-cn luci-i18n-msd_lite-zh-cn luci-i18n-upnp-zh-cn luci-i18n-diskman-zh-cn luci-i18n-argon-config-zh-cn luci-i18n-firewall-zh-cn luci-app-upnp luci-i18n-package-manager-zh-cn luci-i18n-lucky-zh-cn luci-i18n-adguardhome-zh-cn"

rm -rf output bin/targets && mkdir -p output

# ImageBuilder 一次运行会生成所有格式：squashfs/ext4 + combined/combined-efi
log_info "开始构建固件 (一次构建所有基础格式)..."
make image PROFILE=generic PACKAGES="$PACKAGES" FILES="FILES" EXTRA_IMAGE_NAME="immortalwrt" 2>&1 | tee build.log

# 复制基础固件
[ -d "bin/targets/x86/64" ] && cp -r bin/targets/x86/64/* output/

# 转换虚拟机格式
if [ "$VM_FORMAT" != "img" ] && command -v qemu-img &> /dev/null; then
    log_step "转换虚拟机格式..."
    
    convert_vm_image() {
        local input_file=$1
        local format=$2
        local output_file=$3
        
        if [ ! -f "$input_file" ]; then
            return 1
        fi
        
        # 解压
        local raw_file="${input_file%.gz}"
        if [[ "$input_file" == *.gz ]]; then
            gunzip -c "$input_file" > "$raw_file"
        else
            cp "$input_file" "$raw_file"
        fi
        
        # 转换
        qemu-img convert -f raw -O "$format" "$raw_file" "$output_file"
        gzip -f "$output_file"
        rm -f "$raw_file"
    }
    
    # 遍历所有 img 文件并转换
    for img in output/*.img; do
        [ -f "$img" ] || continue
        basename=$(basename "$img" .img)
        
        if [ "$VM_FORMAT" = "all" ] || [ "$VM_FORMAT" = "qcow2" ]; then
            convert_vm_image "$img" "qcow2" "output/${basename}.qcow2"
        fi
        if [ "$VM_FORMAT" = "all" ] || [ "$VM_FORMAT" = "vmdk" ]; then
            convert_vm_image "$img" "vmdk" "output/${basename}.vmdk"
        fi
        if [ "$VM_FORMAT" = "all" ] || [ "$VM_FORMAT" = "vdi" ]; then
            convert_vm_image "$img" "vdi" "output/${basename}.vdi"
        fi
        if [ "$VM_FORMAT" = "all" ] || [ "$VM_FORMAT" = "vhdx" ]; then
            convert_vm_image "$img" "vhdx" "output/${basename}.vhdx"
        fi
    done
fi

log_info "构建完成!"

# === 步骤 8: 显示结果 ===
log_step "8. 构建结果..."

echo ""
echo "=========================================="
echo "构建完成!"
echo "=========================================="
echo "版本: ${VERSION}"
echo "固件类型: ${FIRMWARE_TYPE}"
echo "启动模式: ${BOOT_MODE}"
echo ""
echo "固件文件:"
ls -lh output/*.img.gz 2>/dev/null || echo "未找到固件文件"
echo ""
echo "输出目录: $(pwd)/output"
echo ""

# === 步骤 9: 生成构建信息 ===
log_step "9. 生成构建信息..."

cat > output/build-info.txt << EOF
ImmortalWrt 固件构建信息
========================
构建时间：$(date '+%Y-%m-%d %H:%M:%S')
ImmortalWrt 版本：${VERSION}
内核版本：${KMODS_SUBDIR}
固件类型：${FIRMWARE_TYPE}
启动模式：${BOOT_MODE}

第三方软件版本:
- EasyTier: ${EASYTIER_TAG}
- Lucky: ${LUCKY_TAG}
- AdGuardHome LuCI: ${ADG_LUCI_TAG}
- AdGuardHome 核心：${ADG_CORE_TAG}
- Mihomo: ${MIHOMO_TAG}

文件列表:
$(ls -lh output/*.img.gz)
EOF

log_info "构建信息已保存到 output/build-info.txt"

echo ""
echo "=========================================="
echo "🎉 构建完成!"
echo "=========================================="
echo ""