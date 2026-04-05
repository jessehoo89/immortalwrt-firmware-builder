# 📖 部署指南

本指南将帮助你使用 ImmortalWrt 固件自动构建仓库。

## 🎯 快速开始

### 方案一：使用 GitHub Actions (推荐)

适合大多数用户，无需本地环境，自动构建和发布。

#### 1. Fork 仓库

```bash
# 在 GitHub 上点击 Fork 按钮
# 或访问：https://github.com/<your-username>/immortalwrt-github
```

#### 2. 启用 GitHub Actions

1. 进入你的仓库
2. 点击 **Settings** → **Actions** → **General**
3. 确保 **Allow all actions and reusable workflows** 已启用
4. 点击 **Save**

#### 3. 配置工作流 (可选)

如需自定义配置，编辑 `.github/workflows/build.yml`：

```yaml
# 修改定时构建时间
schedule:
  - cron: '0 2 * * 0'  # 每周日凌晨 2 点

# 修改预装软件包
PACKAGES="kmod-tun easytier ..."
```

#### 4. 手动触发构建

1. 进入 **Actions** 标签页
2. 选择 **🚀 ImmortalWrt 固件构建**
3. 点击 **Run workflow**
4. 选择版本和发布选项
5. 点击 **Run workflow**

#### 5. 下载固件

构建完成后：

- **Release 页面**: `https://github.com/<your-username>/immortalwrt-github/releases`
- **Actions 产物**: 在 Actions 页面下载 (保留 30 天)

---

### 方案二：本地构建

适合需要快速测试或自定义的用户。

#### 环境要求

- Ubuntu 22.04 / Debian 11+ / macOS
- 至少 10GB 可用磁盘空间
- 至少 4GB RAM
- 稳定的网络连接

#### 1. 克隆仓库

```bash
git clone https://github.com/<your-username>/immortalwrt-github.git
cd immortalwrt-github
```

#### 2. 安装依赖

**Ubuntu/Debian:**

```bash
sudo apt-get update
sudo apt-get install -y \
    wget curl unzip zstd gzip tar make \
    build-essential libssl-dev zlib1g-dev \
    gawk git ccache libncurses5-dev libncursesw5-dev \
    rsync python3 python3-pip python3-setuptools \
    python3-yaml swig libpython3-dev
```

**macOS:**

```bash
brew install wget curl unzip zstd gawk make
# 注意：macOS 上构建可能需要额外配置
```

#### 3. 运行构建脚本

```bash
chmod +x build-local.sh
./build-local.sh
```

构建时间约 30-40 分钟，完成后固件在 `output/` 目录。

#### 4. 自定义配置

编辑 `config.sh` 文件：

```bash
# 指定 ImmortalWrt 版本
IMMORTALWRT_VERSION="24.10.5"

# 修改预装软件包
PACKAGES_BASE="kmod-tun easytier"
PACKAGES_PROXY="lucky luci-app-adguardhome"

# 其他配置...
```

然后运行：

```bash
source config.sh
./build-local.sh
```

---

## 🔧 高级配置

### 修改 GitHub Actions 触发条件

编辑 `.github/workflows/build.yml`:

```yaml
on:
  workflow_dispatch:  # 手动触发
    inputs:
      version:
        description: '版本'
        required: false
        default: ''
  
  schedule:  # 定时触发
    - cron: '0 2 * * 0'  # 每周日凌晨 2 点 UTC
  
  push:  # 推送触发 (可选)
    branches: [ main ]
    paths:
      - '.github/workflows/build.yml'
      - 'config.sh'
```

### 添加多个架构支持

目前支持 `x86/64`，如需添加其他架构：

```yaml
strategy:
  matrix:
    include:
      - target: x86
        subtarget: 64
        profile: generic
      
      - target: armsr
        subtarget: armv8
        profile: generic
      
      - target: ramips
        subtarget: mt7621
        profile: xiaomi_mi-router-4a-gigabit
```

### 自定义 Release 标签格式

```yaml
- name: ⬆️ 上传固件到 GitHub Release
  uses: softprops/action-gh-release@v2
  with:
    tag_name: immortalwrt-${{ steps.version.outputs.VERSION }}-${{ github.run_number }}
    name: "🚀 ImmortalWrt ${{ steps.version.outputs.VERSION }} - 构建 #${{ github.run_number }}"
    body_path: ${{ github.workspace }}/firmware/build-info.txt
```

---

## 📋 故障排查

### Actions 构建失败

#### 问题：下载超时

```yaml
# 增加下载超时时间
- name: ⬇️ 下载 ImageBuilder
  run: |
    wget --timeout=300 --tries=3 ...
```

#### 问题：空间不足

GitHub Actions 提供约 14GB 空间，如不足：

```yaml
- name: 🧹 清理空间
  run: |
    sudo rm -rf /usr/share/dotnet
    sudo rm -rf /opt/ghc
    sudo rm -rf "/usr/local/share/boost"
    sudo rm -rf "$AGENT_TOOLSDIRECTORY"
```

#### 问题：包名错误

检查包名是否正确：

```bash
# 在镜像源中搜索包名
curl -s https://mirrors.ustc.edu.cn/immortalwrt/releases/24.10.5/packages/x86_64/luci/Packages | grep "Package: 包名"
```

### 本地构建失败

#### 问题：权限错误

```bash
# 确保脚本有执行权限
chmod +x build-local.sh

# 确保 FILES 目录文件有正确权限
chmod +x FILES/usr/bin/AdGuardHome/AdGuardHome
chmod +x FILES/etc/openclash/core/clash_meta
```

#### 问题：依赖缺失

```bash
# 重新安装依赖
sudo apt-get install -y make build-essential libssl-dev
```

#### 问题：网络问题

```bash
# 使用代理
export https_proxy=http://proxy-server:port
export http_proxy=http://proxy-server:port

# 或使用 GitHub 代理
GHPROXY="https://gh-proxy.org"
```

---

## 🚀 部署到设备

### x86 平台安装

#### 1. 写入 U 盘/硬盘

```bash
# 解压固件
gunzip immortalwrt-*-squashfs-combined.img.gz

# 写入 U 盘 (替换 /dev/sdX 为实际设备)
sudo dd if=immortalwrt-*-squashfs-combined.img of=/dev/sdX bs=4M status=progress conv=fsync

# 或写入硬盘
sudo dd if=immortalwrt-*-squashfs-combined.img of=/dev/sda bs=4M status=progress conv=fsync
```

#### 2. 启动设备

1. 插入 U 盘或硬盘
2. 启动设备，进入 BIOS/UEFI
3. 选择从 U 盘或硬盘启动
4. 等待系统启动完成

#### 3. 访问管理界面

- 默认 IP: `192.168.1.1`
- 默认密码：无 (首次登录需设置)
- 管理界面：`http://192.168.1.1`

### 虚拟机测试

#### VirtualBox

1. 创建新虚拟机 (Linux, 其他/未知)
2. 内存：至少 512MB
3. 硬盘：使用现有虚拟硬盘文件
4. 转换固件格式：

```bash
# 转换为 VDI
VBoxManage convertfromraw immortalwrt-*-squashfs-combined.img firmware.vdi

# 或使用 QCOW2 (QEMU/KVM)
qemu-img convert -f raw -O qcow2 immortalwrt-*.img firmware.qcow2
```

#### VMware

```bash
# 转换为 VMDK
qemu-img convert -f raw -O vmdk immortalwrt-*.img firmware.vmdk
```

---

## 📊 GitHub Actions 使用技巧

### 减少构建时间

1. **启用缓存**:

```yaml
- name: 📦 缓存 ImageBuilder
  uses: actions/cache@v4
  with:
    path: immortalwrt-imagebuilder-*
    key: ${{ runner.os }}-imagebuilder-${{ steps.version.outputs.VERSION }}
```

2. **并行构建**:

```yaml
strategy:
  matrix:
    target: [x86/64, armsr/armv8]
  max-parallel: 2
```

### 管理存储空间

1. **定期清理旧 Release**:

```yaml
- name: 🧹 清理旧 Release
  uses: dev-drprasad/delete-older-releases@v0.2.1
  with:
    keep_latest: 3
    delete_tags: true
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

2. **限制产物保留时间**:

```yaml
- name: 📦 上传构建产物
  uses: actions/upload-artifact@v4
  with:
    name: firmware
    retention-days: 7  # 只保留 7 天
```

---

## 🔐 安全建议

1. **首次登录后立即设置密码**
2. **定期更新固件**
3. **关闭不必要的服务**
4. **配置防火墙规则**
5. **使用 HTTPS 访问管理界面**

---

## 📞 获取帮助

- **GitHub Issues**: 提交问题和建议
- **ImmortalWrt 论坛**: https://forum.immortalwrt.org/
- **OpenWrt 文档**: https://openwrt.org/docs/

---

**最后更新**: 2026-04-05  
**文档版本**: 1.0.0
