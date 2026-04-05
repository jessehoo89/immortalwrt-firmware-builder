# 🚀 快速开始指南

## 3 分钟快速上手

### 方式一：GitHub Actions 自动构建 (推荐)

```bash
# 1. 运行初始化脚本
cd immortalwrt-github
./init-repo.sh

# 2. 按提示完成 GitHub 仓库创建

# 3. 在 GitHub 上启用 Actions:
#    Settings → Actions → General → Allow all actions → Save

# 4. 进入 Actions 标签页，点击 "Run workflow"

# 5. 等待构建完成 (约 30-40 分钟)

# 6. 在 Releases 页面下载固件
```

### 方式二：本地构建测试

```bash
# 1. 安装依赖 (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y wget curl unzip zstd make build-essential

# 2. 运行构建脚本
cd immortalwrt-github
chmod +x build-local.sh
./build-local.sh

# 3. 构建完成后，固件在 output/ 目录
```

---

## 📁 仓库结构

```
immortalwrt-github/
├── .github/
│   └── workflows/
│       └── build.yml          # GitHub Actions 工作流
├── .gitignore                 # Git 忽略文件
├── README.md                  # 项目说明
├── DEPLOYMENT.md              # 部署指南
├── LICENSE                    # MIT 许可证
├── config.sh                  # 配置文件
├── build-local.sh             # 本地构建脚本
└── init-repo.sh               # 仓库初始化脚本
```

---

## ⚙️ 自定义配置

### 修改预装软件

编辑 `config.sh`:

```bash
# 添加或删除软件包
PACKAGES_BASE="kmod-tun easytier miniupnpd-nftables"
PACKAGES_PROXY="lucky luci-app-adguardhome luci-app-openclash"
```

### 修改构建频率

编辑 `.github/workflows/build.yml`:

```yaml
schedule:
  # 每天凌晨 3 点
  - cron: '0 3 * * *'
```

### 指定 ImmortalWrt 版本

在 Actions 中手动触发时，输入版本号：
- 留空 = 自动获取最新版
- 例如：`24.10.5`

---

## 📥 下载固件

构建完成后，有两种方式获取：

### 1. GitHub Releases (推荐)

访问：`https://github.com/<your-username>/immortalwrt-github/releases`

### 2. Actions 产物

访问：`https://github.com/<your-username>/immortalwrt-github/actions`
- 点击最近的构建任务
- 在底部 "Artifacts" 下载
- 保留 30 天

---

## 🔧 常见问题

### Q: 构建失败怎么办？

查看 Actions 日志，常见原因：
- 网络问题 → 已配置 GitHub 代理
- 包名错误 → 检查包名是否正确
- 空间不足 → 清理旧 Release

### Q: 如何添加其他架构？

目前支持 `x86/64`，其他架构需要修改工作流文件。

### Q: 固件如何使用？

参考 [`DEPLOYMENT.md`](./DEPLOYMENT.md) 中的部署指南。

---

## 📞 获取帮助

- 查看 [`README.md`](./README.md) 了解功能
- 查看 [`DEPLOYMENT.md`](./DEPLOYMENT.md) 了解部署
- 查看 [`config.sh`](./config.sh) 了解配置选项

---

**开始构建吧！** 🎉
