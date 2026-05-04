#!/bin/bash
# ImmortalWrt 固件构建脚本（融合版）
# 交互模式: ./build-local.sh
# 静默模式: ./build-local.sh --batch
#   环境变量: MIRROR, GHPROXY, IMMORTALWRT_VERSION, WORK_DIR, OUTPUT_DIR

set -e

# ==================== 颜色与日志 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# 静默模式时 stdout 只输出变量，日志全走 stderr
log_info_batch()  { echo "[INFO] $1" >&2; }
log_warn_batch()  { echo "[WARN] $1" >&2; }
log_error_batch() { echo "[ERROR] $1" >&2; }
log_step_batch()  { echo "[STEP] $1" >&2; }

# ==================== 脚本目录（注入脚本时用） ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ==================== 辅助函数 ====================
get_latest_tag() {
    local repo=$1
    curl -s "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -E '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

get_latest_version() {
    local mirror=$1
    curl -s "${mirror}/releases/" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+/' \
        | sed 's|/||' \
        | sort -V | uniq | tail -1
}

# ==================== 模式判断与配置获取 ====================
BATCH=false
[ "$1" = "--batch" ] && BATCH=true

if $BATCH; then
    # ===== 静默模式 =====
    MIRROR="${MIRROR:-https://downloads.immortalwrt.org}"
    GHPROXY="${GHPROXY:-}"
    IMMORTALWRT_VERSION="${IMMORTALWRT_VERSION:-}"
    WORK_DIR="${WORK_DIR:-${PWD}/immortalwrt}"
    OUTPUT_DIR="${OUTPUT_DIR:-${PWD}/firmware}"

    if [ -n "$GHPROXY" ]; then
        GHPREFIX="${GHPROXY}/"
    else
        GHPREFIX=""
    fi

    log_step_batch "1/9 配置已加载 (MIRROR=${MIRROR})"
else
    # ===== 交互模式 =====
    echo "=========================================="
    echo "ImmortalWrt 本地构建脚本"
    echo "=========================================="
    echo ""

    log_step "1/9 选择配置"

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
    [ -n "$GHPROXY" ] && log_info "使用代理: $GHPROXY" || log_info "不使用代理 (直连)"
    GHPREFIX="${GHPROXY}/"
    [ -n "$GHPROXY" ] && GHPREFIX="${GHPROXY}/" || GHPREFIX=""

    WORK_DIR="${PWD}/immortalwrt"
    OUTPUT_DIR="${PWD}/firmware"
    echo ""
fi

# ==================== 构建逻辑（唯一份） ====================

# --- 步骤 2: 获取版本信息 ---
$BATCH && log_step_batch "2/9 获取版本信息..." || log_step "2/9 获取版本信息..."

if [ -n "$IMMORTALWRT_VERSION" ]; then
    VERSION="$IMMORTALWRT_VERSION"
else
    VERSION=$(get_latest_version "$MIRROR")
    [ -z "$VERSION" ] && VERSION="24.10.6"
fi
$BATCH && log_info_batch "ImmortalWrt 版本: ${VERSION}" || log_info "ImmortalWrt 版本: ${VERSION}"

KMODS_SUBDIR=$(curl -s "$MIRROR/releases/${VERSION}/targets/x86/64/kmods/" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[0-9a-f-]+' | head -1)
[ -z "$KMODS_SUBDIR" ] && KMODS_SUBDIR="6.6.122-1-e7e50fbc0aafa7443418a79928da2602"
$BATCH && log_info_batch "KMods 目录: ${KMODS_SUBDIR}" || log_info "KMods 目录: ${KMODS_SUBDIR}"

EASYTIER_TAG=$(get_latest_tag "EasyTier/luci-app-easytier")
LUCKY_TAG=$(get_latest_tag "gdy666/luci-app-lucky")
ADG_TAG=$(get_latest_tag "stevenjoezhang/luci-app-adguardhome")
ADG_CORE_TAG=$(get_latest_tag "AdguardTeam/AdGuardHome")
MIHOMO_TAG=$(get_latest_tag "MetaCubeX/mihomo")

EASYTIER_TAG="${EASYTIER_TAG:-v2.5.0}"
LUCKY_TAG="${LUCKY_TAG:-v2.19.5}"
ADG_TAG="${ADG_TAG:-v1.19}"
ADG_CORE_TAG="${ADG_CORE_TAG:-v0.107.55}"
MIHOMO_TAG="${MIHOMO_TAG:-v1.19.0}"

if $BATCH; then
    log_info_batch "EasyTier: ${EASYTIER_TAG}"
    log_info_batch "Lucky: ${LUCKY_TAG}"
    log_info_batch "AdGuardHome LuCI: ${ADG_TAG}"
    log_info_batch "AdGuardHome Core: ${ADG_CORE_TAG}"
    log_info_batch "Mihomo: ${MIHOMO_TAG}"
else
    log_info "EasyTier: ${EASYTIER_TAG}"
    log_info "Lucky: ${LUCKY_TAG}"
    log_info "AdGuardHome LuCI: ${ADG_TAG}"
    log_info "AdGuardHome Core: ${ADG_CORE_TAG}"
    log_info "Mihomo: ${MIHOMO_TAG}"
fi

# --- 步骤 3: 下载 ImageBuilder ---
$BATCH && log_step_batch "3/9 下载 ImageBuilder..." || log_step "3/9 下载 ImageBuilder..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
echo "Downloading ImageBuilder ${VERSION}..." >&2
wget -q "$MIRROR/releases/${VERSION}/targets/x86/64/immortalwrt-imagebuilder-${VERSION}-x86-64.Linux-x86_64.tar.zst" -O imagebuilder.tar.zst
tar -I zstd -xf imagebuilder.tar.zst
rm -f imagebuilder.tar.zst
IMAGEBUILDER_DIR=$(cd immortalwrt-imagebuilder-* && pwd)
$BATCH && log_info_batch "ImageBuilder 目录: ${IMAGEBUILDER_DIR}" || log_info "ImageBuilder 目录: ${IMAGEBUILDER_DIR}"

# --- 步骤 4: 配置软件源 ---
$BATCH && log_step_batch "4/9 配置软件源..." || log_step "4/9 配置软件源..."
cd "$IMAGEBUILDER_DIR"
cat > repositories.conf << EOF
src/gz immortalwrt_core $MIRROR/releases/${VERSION}/targets/x86/64/packages
src/gz immortalwrt_base $MIRROR/releases/${VERSION}/packages/x86_64/base
src/gz immortalwrt_kmods $MIRROR/releases/${VERSION}/targets/x86/64/kmods/${KMODS_SUBDIR}
src/gz immortalwrt_luci $MIRROR/releases/${VERSION}/packages/x86_64/luci
src/gz immortalwrt_packages $MIRROR/releases/${VERSION}/packages/x86_64/packages
src/gz immortalwrt_routing $MIRROR/releases/${VERSION}/packages/x86_64/routing
src/gz immortalwrt_telephony $MIRROR/releases/${VERSION}/packages/x86_64/telephony
src imagebuilder file:packages
EOF

# --- 步骤 5: 下载第三方 IPK ---
$BATCH && log_step_batch "5/9 下载第三方 IPK..." || log_step "5/9 下载第三方 IPK..."
cd "$IMAGEBUILDER_DIR/packages"

wget -q "${GHPREFIX}https://github.com/EasyTier/luci-app-easytier/releases/download/${EASYTIER_TAG}/EasyTier-${EASYTIER_TAG}-x86_64-22.03.7.zip"
unzip -q EasyTier-*.zip && rm -f EasyTier-*.zip

wget -q "${GHPREFIX}https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG}/luci-app-lucky_2.2.2-r1_all.ipk"
wget -q "${GHPREFIX}https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG}/luci-i18n-lucky-zh-cn_25.051.13443.e78d498_all.ipk"
wget -q "${GHPREFIX}https://github.com/gdy666/luci-app-lucky/releases/download/${LUCKY_TAG}/lucky_2.19.5_Openwrt_x86_64.ipk"

wget -q "${GHPREFIX}https://github.com/stevenjoezhang/luci-app-adguardhome/releases/download/${ADG_TAG}/luci-app-adguardhome_1.19_all.ipk"
wget -q "${GHPREFIX}https://github.com/stevenjoezhang/luci-app-adguardhome/releases/download/${ADG_TAG}/luci-i18n-adguardhome-zh-cn_260130.50632_all.ipk"

$BATCH && log_info_batch "第三方 IPK 下载完成" || log_info "第三方 IPK 下载完成"

# --- 步骤 6: 准备 FILES 目录 ---
$BATCH && log_step_batch "6/9 准备 FILES 目录..." || log_step "6/9 准备 FILES 目录..."
cd "$IMAGEBUILDER_DIR"
mkdir -p FILES/usr/bin/AdGuardHome FILES/etc/openclash/core FILES/etc/opkg

cat > FILES/etc/opkg/distfeeds.conf << EOF
src/gz immortalwrt_core $MIRROR/releases/${VERSION}/targets/x86/64/packages
src/gz immortalwrt_base $MIRROR/releases/${VERSION}/packages/x86_64/base
src/gz immortalwrt_kmods $MIRROR/releases/${VERSION}/targets/x86/64/kmods/${KMODS_SUBDIR}
src/gz immortalwrt_luci $MIRROR/releases/${VERSION}/packages/x86_64/luci
src/gz immortalwrt_packages $MIRROR/releases/${VERSION}/packages/x86_64/packages
src/gz immortalwrt_routing $MIRROR/releases/${VERSION}/packages/x86_64/routing
src/gz immortalwrt_telephony $MIRROR/releases/${VERSION}/packages/x86_64/telephony
EOF

wget -q "${GHPREFIX}https://github.com/AdguardTeam/AdGuardHome/releases/download/${ADG_CORE_TAG}/AdGuardHome_linux_amd64.tar.gz"
tar -xzf AdGuardHome_linux_amd64.tar.gz
mv AdGuardHome/AdGuardHome FILES/usr/bin/AdGuardHome/
chmod +x FILES/usr/bin/AdGuardHome/AdGuardHome
rm -rf AdGuardHome AdGuardHome_linux_amd64.tar.gz

wget -q "${GHPREFIX}https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_TAG}/mihomo-linux-amd64-${MIHOMO_TAG}.gz"
gunzip -c mihomo-*.gz > FILES/etc/openclash/core/clash_meta
chmod +x FILES/etc/openclash/core/clash_meta
rm -f mihomo-*.gz

$BATCH && log_info_batch "FILES 目录准备完成" || log_info "FILES 目录准备完成"

# --- 步骤 7: 构建固件 ---
$BATCH && log_step_batch "7/9 构建固件..." || log_step "7/9 构建固件..."
cd "$IMAGEBUILDER_DIR"
PACKAGES="kmod-tun easytier miniupnpd-nftables lucky luci-app-adguardhome luci-app-openclash luci-app-argon-config luci-app-autoreboot luci-app-msd_lite luci-app-wol luci-app-easytier luci-app-zerotier luci-app-diskman luci-app-lucky luci-i18n-zerotier-zh-cn luci-i18n-autoreboot-zh-cn luci-i18n-wol-zh-cn luci-i18n-msd_lite-zh-cn luci-i18n-upnp-zh-cn luci-i18n-diskman-zh-cn luci-i18n-argon-config-zh-cn luci-i18n-firewall-zh-cn luci-app-upnp luci-i18n-package-manager-zh-cn luci-i18n-lucky-zh-cn luci-i18n-adguardhome-zh-cn"
rm -rf output bin/targets && mkdir -p output

make image PROFILE=generic PACKAGES="$PACKAGES" FILES="FILES" EXTRA_IMAGE_NAME="immortalwrt" 2>&1 | tee build.log >&2

# 复制构建产物
[ -d "bin/targets/x86/64" ] && cp -r bin/targets/x86/64/* output/

mkdir -p "$OUTPUT_DIR"
cp -r output/* "$OUTPUT_DIR/"

$BATCH && log_info_batch "固件构建完成" || log_info "固件构建完成"

# --- 步骤 8: 注入脚本到固件 ---
$BATCH && log_step_batch "8/9 注入脚本到固件..." || log_step "8/9 注入脚本到固件..."
cd "$OUTPUT_DIR"

# 注入 DHCP 关闭脚本
for img in *rootfs*.tar.gz; do
    if [ -f "$img" ]; then
        if [ -f "$SCRIPT_DIR/inject-dhcp.sh" ]; then
            bash "$SCRIPT_DIR/inject-dhcp.sh" "$img" || echo "警告: DHCP 注入失败: $img" >&2
        else
            log_warn_batch "未找到 inject-dhcp.sh，跳过 DHCP 注入"
            $BATCH || log_warn "未找到 inject-dhcp.sh，跳过 DHCP 注入"
        fi
    fi
done

# 注入自动扩容脚本
COUNT=0
for img in *ext4*.img.gz; do
    if [ -f "$img" ]; then
        if [ -f "$SCRIPT_DIR/inject-autoexpand.sh" ]; then
            bash "$SCRIPT_DIR/inject-autoexpand.sh" "$img" || echo "警告: 自动扩容注入失败: $img" >&2
            COUNT=$((COUNT + 1))
        else
            log_warn_batch "未找到 inject-autoexpand.sh，跳过自动扩容注入"
            $BATCH || log_warn "未找到 inject-autoexpand.sh，跳过自动扩容注入"
        fi
    fi
done

if $BATCH; then
    [ $COUNT -gt 0 ] && log_info_batch "已处理 $COUNT 个 ext4 固件" || log_info_batch "未找到 ext4 固件"
else
    [ $COUNT -gt 0 ] && log_info "✅ 已处理 $COUNT 个 ext4 固件" || log_info "未找到 ext4 固件"
fi

# --- 步骤 9: 生成构建信息 ---
$BATCH && log_step_batch "9/9 生成构建信息..." || log_step "9/9 生成构建信息..."
BUILD_TIME=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M')
cat > "$OUTPUT_DIR/build-info.txt" << EOF
ImmortalWrt Firmware Build Info
================================
Build Time: $(date '+%Y-%m-%d %H:%M:%S')
Version: ${VERSION}
KMods: ${KMODS_SUBDIR}

Third-party Versions:
- EasyTier: ${EASYTIER_TAG}
- Lucky: ${LUCKY_TAG}
- AdGuardHome LuCI: ${ADG_TAG}
- AdGuardHome Core: ${ADG_CORE_TAG}
- Mihomo: ${MIHOMO_TAG}

Docker Image:
- Repository: ${DOCKER_REPO:-}
- Tags: latest, ${BUILD_DATE:-}

📦 Docker 仓库同步：
immortalwrt-x86-64-generic-rootfs.tar.gz 已同步推送至 Docker 仓库
EOF

$BATCH && log_info_batch "构建完成! 固件目录: ${OUTPUT_DIR}" || log_info "构建完成! 固件目录: ${OUTPUT_DIR}"

# ==================== 输出变量（供 CI 使用） ====================
if $BATCH; then
    cat << VAREOF
VERSION=${VERSION}
KMODS_SUBDIR=${KMODS_SUBDIR}
IMAGEBUILDER_DIR=${IMAGEBUILDER_DIR}
OUTPUT_DIR=${OUTPUT_DIR}
EASYTIER_TAG=${EASYTIER_TAG}
LUCKY_TAG=${LUCKY_TAG}
ADG_TAG=${ADG_TAG}
ADG_CORE_TAG=${ADG_CORE_TAG}
MIHOMO_TAG=${MIHOMO_TAG}
BUILD_TIME=${BUILD_TIME}
VAREOF
fi
