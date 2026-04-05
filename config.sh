# ImmortalWrt 固件构建配置文件
# 修改此文件后，在 build-local.sh 中 source 使用

# ==================== 版本配置 ====================

# ImmortalWrt 版本 (留空则自动获取最新版)
IMMORTALWRT_VERSION=""

# ==================== 镜像源配置 ====================

# 主镜像源
MIRROR="https://mirrors.ustc.edu.cn/immortalwrt"

# GitHub 代理 (加速下载)
GHPROXY="https://gh-proxy.org"

# ==================== 预装软件包配置 ====================

# 基础网络包
PACKAGES_BASE="kmod-tun easytier miniupnpd-nftables"

# 代理和广告过滤
PACKAGES_PROXY="lucky luci-app-adguardhome luci-app-openclash"

# LuCI 主题和工具
PACKAGES_LUCI="luci-app-argon-config luci-app-autoreboot luci-app-msd_lite luci-app-wol"

# 组网工具
PACKAGES_NETWORK="luci-app-easytier luci-app-zerotier"

# 磁盘管理
PACKAGES_STORAGE="luci-app-diskman"

# 国际化包
PACKAGES_I18N="luci-i18n-zerotier-zh-cn luci-i18n-autoreboot-zh-cn luci-i18n-wol-zh-cn luci-i18n-msd_lite-zh-cn luci-i18n-upnp-zh-cn luci-i18n-diskman-zh-cn luci-i18n-argon-config-zh-cn luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-lucky-zh-cn luci-i18n-adguardhome-zh-cn"

# 完整包列表
PACKAGES="${PACKAGES_BASE} ${PACKAGES_PROXY} ${PACKAGES_LUCI} ${PACKAGES_NETWORK} ${PACKAGES_STORAGE} ${PACKAGES_I18N}"

# ==================== 第三方软件版本 ====================
# 留空则自动获取最新版

# EasyTier
EASYTIER_TAG=""

# Lucky
LUCKY_TAG=""

# AdGuardHome LuCI
ADGUARDHOME_LUCI_TAG=""

# AdGuardHome 核心
ADGUARDHOME_CORE_TAG=""

# Mihomo (Meta 内核)
MIHOMO_TAG=""

# ==================== 构建配置 ====================

# 目标架构
TARGET_ARCH="x86"
TARGET_SUBARCH="64"

# 固件类型 (squashfs/ext4)
# squashfs: 只读根文件系统，更安全
# ext4: 可写根文件系统，更灵活
FIRMWARE_TYPE="squashfs"

# 启动方式 (combined/combined-efi)
# combined: 传统 BIOS
# combined-efi: UEFI
BOOT_MODE="both"  # both: 两种都构建

# ==================== GitHub Actions 配置 ====================

# 是否启用定时构建
ENABLE_SCHEDULE="true"

# 定时构建时间 (Cron 表达式)
# 格式：分钟 小时 日期 月份 星期
# 默认：每周日凌晨 2 点 (UTC 时间)
SCHEDULE_CRON="0 2 * * 0"

# 是否自动上传 Release
AUTO_UPLOAD_RELEASE="true"

# 是否创建 Draft Release (需要手动发布)
DRAFT_RELEASE="false"

# 是否标记为预发布版本
PRERELEASE="false"

# ==================== 自定义 FILES 目录 ====================

# 如需添加自定义文件，在 FILES 目录下创建相应结构
# 例如：
# FILES/etc/config/myconfig -> /etc/config/myconfig
# FILES/usr/bin/myapp -> /usr/bin/myapp

# ==================== 其他配置 ====================

# 是否启用日志输出
ENABLE_LOG="true"

# 日志保留天数
LOG_RETENTION_DAYS="30"

# 构建产物保留天数 (GitHub Actions)
ARTIFACT_RETENTION_DAYS="30"
