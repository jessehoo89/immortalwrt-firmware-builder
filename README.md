# 🚀 ImmortalWrt 固件自动构建

基于 GitHub Actions 的 ImmortalWrt 固件自动化构建和发布系统。

## ✨ 功能特性

- 🔧 **基于官方 ImageBuilder** - 内核 Hash 值不变，可安装官方 kmod 插件
- 📦 **到手可用** - 集成常用必备工具和第三方软件，自动保持更新
- 🔄 **自动获取最新版本** - 自动检测 ImmortalWrt 和第三方插件的最新版本
- 🎯 **自动发布** - 构建完成后自动上传到 GitHub Release
- 🐳 **Docker 镜像发布** - 自动构建并发布 Docker 镜像到 Docker Hub
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
4. 点击 **Run workflow** 开始构建（版本留空自动获取最新版）

### 3. 自动定时构建

工作流已配置为每周日凌晨 2 点自动构建最新版本，无需手动操作。

### 4. 下载固件

构建完成后，可以通过以下方式获取固件：

- **GitHub Release**：在仓库的 Releases 页面下载
- **Actions 产物**：在 Actions 页面的构建任务中下载（保留 30 天）

### 5. 使用 Docker 镜像

构建完成后，Docker 镜像会自动发布到 Docker Hub：

```bash
# 拉取最新镜像
docker pull jessehoo89/immortalwrt-x86-64:latest

# 拉取指定构建版本
docker pull jessehoo89/immortalwrt-x86-64:<构建编号>
```

**Docker 镜像使用说明：**

- 镜像基于 `immortalwrt-x86-64-generic-rootfs.tar.gz` 构建
- 包含完整的 ImmortalWrt 文件系统
- 可用于容器化部署或作为基础镜像
- 标签说明：
  - `latest`：最新构建版本
  - `<构建编号>`：对应 GitHub Actions 的运行编号

## 📁 固件文件说明

### 物理机固件
| 文件类型 | 用途 | 推荐 |
|---------|------|------|
| `*-squashfs-combined.img.gz` | 传统 BIOS 启动 | ✅ 推荐 |
| `*-squashfs-combined-efi.img.gz` | UEFI 启动 | ✅ 推荐 |
| `*-ext4-combined.img.gz` | 传统 BIOS，可写分区 | 可选 |
| `*-ext4-combined-efi.img.gz` | UEFI，可写分区 | 可选 |

### 虚拟机固件
| 文件类型 | 平台 | 用途 |
|---------|------|------|
| `*.qcow2.gz` | QEMU/KVM | 虚拟化环境 |
| `*.vmdk.gz` | VMware | VMware 虚拟机 |
| `*.vdi.gz` | VirtualBox | VirtualBox 虚拟机 |
| `*.vhdx.gz` | Hyper-V | Windows Hyper-V |

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

## 🔧 第三方软件版本

构建时会自动获取以下软件的最新版本：

| 软件 | 仓库 | 说明 |
|------|------|------|
| EasyTier | EasyTier/luci-app-easytier | 智能组网 |
| Lucky | gdy666/luci-app-lucky | 内网穿透 |
| AdGuardHome LuCI | stevenjoezhang/luci-app-adguardhome | 广告过滤界面 |
| AdGuardHome 核心 | AdguardTeam/AdGuardHome | 广告过滤核心 |
| Mihomo | MetaCubeX/mihomo | OpenClash 内核 |

## ⚠️ 注意事项

1. **GitHub Actions 限制**
   - 免费账户每月 2000 分钟构建时间
   - 单次构建约 30-40 分钟
   - 建议合理使用定时构建频率

2. **存储空间**
   - Release 存储无限制（合理使用）
   - Actions 产物保留 30 天

3. **固件兼容性**
   - 构建前请确认目标硬件架构
   - 建议在虚拟机中测试后再部署到生产环境

## 🛠️ 本地构建

如需在本地构建，运行：

```bash
chmod +x build-local.sh
./build-local.sh
```

脚本会交互式询问：
- 镜像源选择（官方/中科大）
- 是否使用 GitHub 代理

## 📄 许可证

本项目采用 MIT 许可证。

## 🙏 致谢

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [EasyTier](https://github.com/EasyTier/luci-app-easytier)
- [Lucky](https://github.com/gdy666/luci-app-lucky)
- [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome)
- [OpenClash](https://github.com/vernesong/OpenClash)
- [ImmortalWrt 官方镜像站](https://downloads.immortalwrt.org/)

---

**文档版本**: 1.0.0
