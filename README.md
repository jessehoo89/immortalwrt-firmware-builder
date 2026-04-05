# 🚀 ImmortalWrt 固件自动构建

基于 GitHub Actions 的 ImmortalWrt 固件自动化构建和发布系统。

## ✨ 功能特性

- 🔄 **自动获取最新版本** - 自动检测 ImmortalWrt 和第三方插件的最新版本
- 📦 **预装常用插件** - EasyTier、Lucky、AdGuardHome、OpenClash 等
- 🌏 **国内镜像加速** - 使用 USTC 镜像源和 GitHub 代理
- 🎯 **自动发布** - 构建完成后自动上传到 GitHub Release
- ⏰ **定时构建** - 每周日凌晨 2 点自动构建最新版
- 📝 **详细日志** - 完整的构建信息和软件版本记录

## 📋 预装软件包

### 核心插件
- **EasyTier** - 智能组网工具
- **Lucky** - 内网穿透工具
- **AdGuardHome** - 广告过滤和 DNS 服务器
- **OpenClash** - 代理客户端
- **ZeroTier** - 虚拟局域网

### 实用工具
- Argon 主题及配置
- 网络唤醒 (WoL)
- 磁盘管理 (DiskMan)
- UPnP 自动端口转发
- 定时重启
- MSD Lite

## 🚀 使用方法

### 1. Fork 仓库

点击 **Fork** 按钮复制此仓库到你的 GitHub 账户。

### 2. 手动触发构建

1. 进入仓库的 **Actions** 标签页
2. 选择 **🚀 ImmortalWrt 固件构建** 工作流
3. 点击 **Run workflow** 按钮
4. 配置选项：
   - **版本**：留空自动获取最新版，或指定版本如 `24.10.5`
   - **上传 Release**：选择是否发布到 GitHub Release
5. 点击 **Run workflow** 开始构建

### 3. 自动定时构建

工作流已配置为每周日凌晨 2 点自动构建最新版本，无需手动操作。

### 4. 下载固件

构建完成后，可以通过以下方式获取固件：

- **GitHub Release**：在仓库的 Releases 页面下载
- **Actions 产物**：在 Actions 页面的构建任务中下载（保留 30 天）

## 📁 固件文件说明

| 文件类型 | 用途 | 推荐 |
|---------|------|------|
| `*-squashfs-combined.img.gz` | 传统 BIOS 启动 | ✅ 推荐 |
| `*-squashfs-combined-efi.img.gz` | UEFI 启动 | ✅ 推荐 |
| `*-ext4-combined.img.gz` | 传统 BIOS，可写分区 | 可选 |
| `*-ext4-combined-efi.img.gz` | UEFI，可写分区 | 可选 |

## ⚙️ 自定义配置

### 修改预装软件包

编辑 `.github/workflows/build.yml`，找到 **构建固件** 步骤中的 `PACKAGES` 变量：

```yaml
PACKAGES="kmod-tun easytier miniupnpd-nftables lucky luci-app-adguardhome ..."
```

根据你的需求添加或删除软件包。

### 修改定时构建时间

编辑 `.github/workflows/build.yml` 中的 `schedule` 触发器：

```yaml
schedule:
  # 每周日凌晨 2 点 (UTC 时间)
  - cron: '0 2 * * 0'
```

时间格式参考：[Cron 表达式](https://crontab.guru/)

### 添加其他架构

目前支持 `x86/64` 架构，如需支持其他架构（如 `arm64`、`mips`），需要：

1. 修改 ImageBuilder 下载链接
2. 调整软件源配置
3. 更新 FILES 目录中的二进制文件架构

## 🔧 第三方软件版本

构建时会自动获取以下软件的最新版本：

| 软件 | 仓库 | 说明 |
|------|------|------|
| EasyTier | EasyTier/luci-app-easytier | 智能组网 |
| Lucky | gdy666/luci-app-lucky | 内网穿透 |
| AdGuardHome LuCI | stevenjoezhang/luci-app-adguardhome | 广告过滤界面 |
| AdGuardHome 核心 | AdguardTeam/AdGuardHome | 广告过滤核心 |
| Mihomo | MetaCubeX/mihomo | OpenClash 内核 |

## 📝 构建日志

构建过程中会生成详细的日志，包括：

- 版本信息获取
- ImageBuilder 下载和解压
- 软件源配置
- 第三方 IPK 下载
- FILES 目录准备
- 固件构建过程
- 输出文件列表

可在 Actions 页面查看实时日志。

## ⚠️ 注意事项

1. **GitHub Actions 限制**
   - 免费账户每月 2000 分钟构建时间
   - 单次构建约 30-40 分钟
   - 建议合理使用定时构建频率

2. **存储空间**
   - Release 存储无限制（合理使用）
   - Actions 产物保留 30 天

3. **网络问题**
   - 已配置 GitHub 代理加速下载
   - 使用 USTC 镜像源提高软件包下载速度

4. **固件兼容性**
   - 构建前请确认目标硬件架构
   - 建议在虚拟机中测试后再部署到生产环境

## 🛠️ 本地构建

如需在本地构建，参考 [`/immortalwrt-build/BUILD_GUIDE.md`](/immortalwrt-build/BUILD_GUIDE.md) 文档。

## 📄 许可证

本项目采用 MIT 许可证。

## 🙏 致谢

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [EasyTier](https://github.com/EasyTier/luci-app-easytier)
- [Lucky](https://github.com/gdy666/luci-app-lucky)
- [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome)
- [OpenClash](https://github.com/vernesong/OpenClash)
- [USTC Linux 用户协会镜像站](https://mirrors.ustc.edu.cn/)

---

**构建时间**: 2026-04-05  
**文档版本**: 1.0.0
