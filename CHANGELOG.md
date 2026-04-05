# 更新日志

## [1.0.0] - 2026-04-05

### ✨ 新增功能

- 🚀 GitHub Actions 自动构建工作流
  - 支持手动触发和定时构建（每周日凌晨 2 点）
  - 自动获取 ImmortalWrt 和第三方插件最新版本
  - 自动上传固件到 GitHub Release
  - 自动构建并发布 Docker 镜像到 Docker Hub
  
- 📦 预装常用插件
  - EasyTier - 智能组网
  - Lucky - 内网穿透
  - AdGuardHome - 广告过滤
  - OpenClash - 代理客户端
  - ZeroTier - 虚拟局域网
  - Argon 主题
  - 磁盘管理、网络唤醒等实用工具

- 🌏 国内镜像加速
  - 使用 USTC 镜像源
  - GitHub 代理加速下载

- 🛠️ 本地构建支持
  - `build-local.sh` 本地测试脚本
  - `config.sh` 配置文件
  - `init-repo.sh` 仓库初始化脚本

- 📝 完整文档
  - README.md - 项目说明
  - QUICKSTART.md - 快速开始
  - DEPLOYMENT.md - 部署指南
  - config.sh - 配置说明

### 🔧 技术细节

- 基于 ImmortalWrt ImageBuilder 24.10.x
- 目标架构：x86/64
- 固件类型：squashfs (只读根文件系统)
- 支持传统 BIOS 和 UEFI 启动

### 📋 构建产物

| 文件类型 | 用途 |
|---------|------|
| `*-squashfs-combined.img.gz` | 传统 BIOS 启动（推荐） |
| `*-squashfs-combined-efi.img.gz` | UEFI 启动（推荐） |
| `*.manifest` | 软件包清单 |
| `*.buildinfo` | 构建信息 |

### 🎯 使用方法

1. Fork 仓库
2. 启用 GitHub Actions
3. 手动触发或等待定时构建
4. 在 Releases 下载固件

详见 [QUICKSTART.md](./QUICKSTART.md)

---

## 计划中的功能

- [ ] 支持更多架构 (arm64, mips)
- [ ] 自定义配置文件支持
- [ ] 多版本并行构建
- [ ] 构建缓存加速
- [ ] 自动清理旧 Release
- [ ] Web 界面配置生成

---

**发布日期**: 2026-04-05  
**初始版本**: 1.0.0
