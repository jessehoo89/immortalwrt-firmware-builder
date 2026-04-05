#!/bin/bash
# ImmortalWrt GitHub Actions 本地测试脚本
# 用于在本地模拟 GitHub Actions 的构建流程

set -e

# 基础配置
MIRROR="https://mirrors.ustc.edu.cn/immortalwrt"
GHPROXY="https://gh-proxy.org"
WORK_DIR=$(pwd)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 函数：获取 GitHub 最新 release tag
get_latest_tag() {
    local repo=$1
    local tag=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | grep -E '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    echo "$tag"
}

echo "=========================================="
echo "ImmortalWrt 本地构建测试脚本"
echo "=========================================="
echo ""

# === 步骤 0: 获取版本信息 ===
log_info "[0/9] 获取版本信息..."

# ImmortalWrt 版本
VERSION="24.10.5"
LATEST_VERSION=$(curl -s "${MIRROR}/releases/" | grep -oE '/immortalwrt/releases/[0-9]+\.[0-9]+\.[0-9]+[^/]*' | sed 's|.*/||' | grep -v 'SNAPSHOT' | grep -v 'rc' | sort -V | tail -1)

if [ -n "$LATEST_VERSION" ]; then
    if curl -s "${MIRROR}/releases/${LATEST_VERSION}/targets/x86/64/" 2>/dev/null | head -10 | grep -q "Directory Listing\|Packages"; then
        VERSION="$LATEST_VERSION"
        log_info "找到最新稳定版本：${VERSION}"
    else
        log_warn "版本 ${LATEST_VERSION} 没有 x86/64 目录，使用：${VERSION}"
    fi
else
    log_warn "无法获取版本信息，使用默认：${VERSION}"
fi

# 第三方软件版本
EASYTIER_TAG=$(get_latest_tag "EasyTier/luci-app-easytier")
LUCKY_TAG=$(get_latest_tag "gdy666/luci-app-lucky")
ADGUARDHOME_LUCI_TAG=$(get_latest_tag "stevenjoezhang/luci-app-adguardhome")
ADGUARDHOME_CORE_TAG=$(get_latest_tag "AdguardTeam/AdGuardHome")
MIHOMO_TAG=$(get_latest_tag "MetaCubeX/mihomo")

log_info "EasyTier: ${EASYTIER_TAG:-v2.5.0}"
log_info "Lucky: ${LUCKY_TAG:-v2.19.5}"
log_info "AdGuardHome LuCI: ${ADGUARDHOME_LUCI_TAG:-v1.19}"
log_info "AdGuardHome 核心：${ADGUARDHOME_CORE_TAG:-v0.107.55}"
log_info "Mihomo: ${MIHOMO_TAG:-v1.19.0}"
echo ""

# === 步骤 1: 下载 ImageBuilder ===
log_info "[1/9] 检查 ImageBuilder..."
if [ ! -d "immortalwrt-imagebuilder-${VERSION}-x86-64.Linux-x86_64" ]; then
    log_info "正在下载 ImageBuilder ${VERSION}..."
    wget -q --show-progress "${MIRROR}/releases/${VERSION}/targets/x86/64/immortalwrt-imagebuilder-${VERSION}-x86-64.Linux-x86_64.tar.zst" -O imagebuilder.tar.zst
    log_info "解压中..."
    tar -I zstd -xf imagebuilder.tar.zst
    rm -f imagebuilder.tar.zst
else
    log_info "ImageBuilder 已存在，跳过下载"
fi
cd "immortalwrt-imagebuilder-${VERSION}-x86-64.Linux-x86_64"

# === 步骤 2: 配置软件源 ===
log_info "[2/9] 配置软件源..."
KMODS_SUBDIR=$(curl -s "${MIRROR}/releases/${VERSION}/targets/x86/64/kmods/" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[0-9a-f-]+' | head -1)
if [ -z "$KMODS_SUBDIR" ]; then
    KMODS_SUBDIR="6.6.122-1-e7e50fbc0aafa7443418a79928da2602"
    log_warn "无法获取 kmods 目录，使用默认"
else
    log_info "找到 kmods 目录：${KMODS_SUBDIR}"
fi

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

# === 步骤 3: 下载第三方 IPK ===
log_info "[3/9] 下载第三方 IPK..."
cd packages

# EasyTier
if [ ! -f "easytier_*.ipk" ]; then
    log_info "下载 EasyTier (${EASYTIER_TAG:-v2.5.0})..."
    wget -q "${GHPROXY}/https://github.com/EasyTier/luci-app-easytier/releases/download/${EASYTIER_TAG:-v2.5.0}/EasyTier-${EASYTIER_TAG:-v2.5.0}-x86_64-22.03.7.zip"
    unzip -qq -o EasyTier-*.zip
    rm -f EasyTier-*.zip
else
    log_info "EasyTier 已存在，跳过"
fi

# Lucky
if [ ! -f "lucky_*.ipk" ]; then
    log_info "下载 Lucky (${LUCKY_TAG:-v2.19.5})..."
    wget -q "${GHPROXY}/https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG:-v2.19.5}/luci-app-lucky_2.2.2-r1_all.ipk"
    wget -q "${GHPROXY}/https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG:-v2.19.5}/luci-i18n-lucky-zh-cn_25.051.13443.e78d498_all.ipk"
    wget -q "${GHPROXY}/https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG:-v2.19.5}/lucky_2.19.5_Openwrt_x86_64.ipk"
else
    log_info "Lucky 已存在，跳过"
fi

# AdGuardHome LuCI
if [ ! -f "luci-app-adguardhome_*.ipk" ]; then
    log_info "下载 AdGuardHome LuCI (${ADGUARDHOME_LUCI_TAG:-v1.19})..."
    wget -q "${GHPROXY}/https://github.com/stevenjoezhang/luci-app-adguardhome/releases/download/${ADGUARDHOME_LUCI_TAG:-v1.19}/luci-app-adguardhome_1.19_all.ipk"
    wget -q "${GHPROXY}/https://github.com/stevenjoezhang/luci-app-adguardhome/releases/download/${ADGUARDHOME_LUCI_TAG:-v1.19}/luci-i18n-adguardhome-zh-cn_260130.50632_all.ipk"
else
    log_info "AdGuardHome LuCI 已存在，跳过"
fi

log_info "第三方 IPK 下载完成"
cd ..

# === 步骤 4: 准备 FILES 目录 ===
log_info "[4/9] 准备 FILES 目录..."

mkdir -p FILES/usr/bin/AdGuardHome
mkdir -p FILES/etc/openclash/core
mkdir -p FILES/etc/opkg

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
if [ ! -f "FILES/usr/bin/AdGuardHome/AdGuardHome" ]; then
    log_info "下载 AdGuardHome 核心 (${ADGUARDHOME_CORE_TAG:-v0.107.55})..."
    wget -q "${GHPROXY}/https://github.com/AdguardTeam/AdGuardHome/releases/download/${ADGUARDHOME_CORE_TAG:-v0.107.55}/AdGuardHome_linux_amd64.tar.gz" -O adg.tar.gz
    tar -xzf adg.tar.gz
    mv AdGuardHome/AdGuardHome FILES/usr/bin/AdGuardHome/
    chmod +x FILES/usr/bin/AdGuardHome/AdGuardHome
    rm -rf AdGuardHome adg.tar.gz
else
    log_info "AdGuardHome 核心已存在，跳过"
fi

# Mihomo 内核
if [ ! -f "FILES/etc/openclash/core/clash_meta" ]; then
    log_info "下载 Mihomo 内核 (${MIHOMO_TAG:-v1.19.0})..."
    wget -q "${GHPROXY}/https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_TAG:-v1.19.0}/mihomo-linux-amd64-${MIHOMO_TAG:-v1.19.0}.gz" -O mihomo.gz
    gunzip -c mihomo.gz > FILES/etc/openclash/core/clash_meta
    chmod +x FILES/etc/openclash/core/clash_meta
    rm -f mihomo.gz
else
    log_info "Mihomo 内核已存在，跳过"
fi

log_info "FILES 目录内容:"
find FILES -type f

# === 步骤 5: 构建固件 ===
log_info "[5/9] 构建固件..."

PACKAGES="kmod-tun easytier miniupnpd-nftables lucky luci-app-adguardhome luci-app-openclash luci-app-argon-config luci-app-autoreboot luci-app-msd_lite luci-app-wol luci-app-easytier luci-app-zerotier luci-app-diskman luci-app-lucky luci-i18n-zerotier-zh-cn luci-i18n-autoreboot-zh-cn luci-i18n-wol-zh-cn luci-i18n-msd_lite-zh-cn luci-i18n-upnp-zh-cn luci-i18n-diskman-zh-cn luci-i18n-argon-config-zh-cn luci-i18n-firewall-zh-cn luci-app-upnp luci-i18n-package-manager-zh-cn luci-i18n-lucky-zh-cn luci-i18n-adguardhome-zh-cn"

rm -rf output bin/targets
mkdir -p output

log_info "开始构建 (这可能需要 30-40 分钟)..."
make image PROFILE=generic PACKAGES="$PACKAGES" FILES="FILES" 2>&1 | tee build.log

if [ -d "bin/targets/x86/64" ]; then
    cp -r bin/targets/x86/64/* output/
    log_info "输出文件已复制到 output/"
fi

# === 步骤 6: 显示结果 ===
log_info "[6/9] 构建完成!"
echo ""
echo "=========================================="
echo "构建结果"
echo "=========================================="
echo "ImmortalWrt 版本：${VERSION}"
echo ""
echo "固件文件:"
ls -lh output/*.img.gz 2>/dev/null || log_error "未找到固件文件"
echo ""
echo "输出目录：$(pwd)/output"
echo ""

# === 步骤 7: 生成构建信息 ===
log_info "[7/9] 生成构建信息..."

cat > output/build-info.txt << EOF
ImmortalWrt 固件构建信息
========================
构建时间：$(date '+%Y-%m-%d %H:%M:%S')
ImmortalWrt 版本：${VERSION}
内核版本：${KMODS_SUBDIR}

第三方软件版本:
- EasyTier: ${EASYTIER_TAG:-v2.5.0}
- Lucky: ${LUCKY_TAG:-v2.19.5}
- AdGuardHome LuCI: ${ADGUARDHOME_LUCI_TAG:-v1.19}
- AdGuardHome 核心：${ADGUARDHOME_CORE_TAG:-v0.107.55}
- Mihomo: ${MIHOMO_TAG:-v1.19.0}

预装软件包:
${PACKAGES}

文件列表:
$(ls -lh output/*.img.gz 2>/dev/null)
EOF

log_info "构建信息已保存到 output/build-info.txt"

# === 步骤 8: 清理 ===
log_info "[8/9] 清理临时文件..."
rm -f adg.tar.gz mihomo.gz 2>/dev/null || true
log_info "清理完成"

# === 步骤 9: 完成 ===
log_info "[9/9] 完成!"
echo ""
echo "=========================================="
echo "🎉 本地构建完成!"
echo "=========================================="
echo ""
echo "下一步:"
echo "1. 测试固件：在虚拟机中测试构建的固件"
echo "2. 部署：将固件刷入目标设备"
echo "3. 推送：如需使用 GitHub Actions，推送代码到仓库"
echo ""
