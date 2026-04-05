#!/bin/bash
# ImmortalWrt GitHub 仓库初始化脚本
# 帮助用户快速设置和推送仓库到 GitHub

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

echo "=========================================="
echo "ImmortalWrt GitHub 仓库初始化"
echo "=========================================="
echo ""

# 检查是否在正确的目录
if [ ! -f ".github/workflows/build.yml" ]; then
    log_error "请在 immortalwrt-github 目录中运行此脚本"
    exit 1
fi

# 检查 git 是否安装
if ! command -v git &> /dev/null; then
    log_error "git 未安装，请先安装 git"
    exit 1
fi

# 检查 GitHub CLI 是否安装
if command -v gh &> /dev/null; then
    GH_AVAILABLE=true
else
    GH_AVAILABLE=false
    log_warn "GitHub CLI (gh) 未安装，将使用交互式方式"
fi

echo ""
log_step "1. 配置 Git 用户信息"
echo ""

# 获取 Git 配置
GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    log_info "配置 Git 用户信息..."
    read -p "请输入 Git 用户名: " GIT_NAME
    read -p "请输入 Git 邮箱: " GIT_EMAIL
    
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
fi

log_info "Git 用户：$GIT_NAME <$GIT_EMAIL>"

echo ""
log_step "2. 初始化 Git 仓库"
echo ""

if [ -d ".git" ]; then
    log_warn "Git 仓库已存在"
    read -p "是否重新初始化？(y/N): " REINIT
    if [ "$REINIT" = "y" ] || [ "$REINIT" = "Y" ]; then
        rm -rf .git
        git init
        log_info "Git 仓库已重新初始化"
    fi
else
    git init
    log_info "Git 仓库已初始化"
fi

echo ""
log_step "3. 添加并提交文件"
echo ""

git add .
log_info "已添加所有文件到暂存区"

read -p "请输入提交信息 (默认: Initial commit): " COMMIT_MSG
COMMIT_MSG=${COMMIT_MSG:-"Initial commit: ImmortalWrt firmware builder"}

git commit -m "$COMMIT_MSG"
log_info "文件已提交"

echo ""
log_step "4. 创建 GitHub 仓库"
echo ""

if [ "$GH_AVAILABLE" = true ]; then
    log_info "检测到 GitHub CLI，使用 gh 创建仓库..."
    
    # 检查是否已登录
    if ! gh auth status &> /dev/null; then
        log_warn "未登录 GitHub，请先运行：gh auth login"
        log_info "跳过自动创建，请手动在 GitHub 上创建仓库"
        MANUAL_CREATE=true
    else
        read -p "请输入仓库名称 (默认: immortalwrt-github): " REPO_NAME
        REPO_NAME=${REPO_NAME:-immortalwrt-github}
        
        read -p "仓库可见性？(public/private, 默认: public): " VISIBILITY
        VISIBILITY=${VISIBILITY:-public}
        
        # 尝试创建仓库
        if gh repo create "$REPO_NAME" --$VISIBILITY --source=. --remote=origin --push 2>/dev/null; then
            log_info "仓库已创建并推送：https://github.com/$GIT_NAME/$REPO_NAME"
            MANUAL_CREATE=false
        else
            log_warn "仓库创建失败，可能已存在"
            read -p "是否尝试推送到现有仓库？(y/N): " PUSH_EXISTING
            if [ "$PUSH_EXISTING" = "y" ] || [ "$PUSH_EXISTING" = "Y" ]; then
                read -p "请输入仓库完整名称 (owner/repo): " FULL_REPO
                git remote add origin "https://github.com/$FULL_REPO.git"
                git branch -M main
                git push -u origin main
                log_info "已推送到：https://github.com/$FULL_REPO"
                MANUAL_CREATE=false
            else
                MANUAL_CREATE=true
            fi
        fi
    fi
else
    MANUAL_CREATE=true
fi

if [ "$MANUAL_CREATE" = true ]; then
    echo ""
    log_info "请手动创建 GitHub 仓库:"
    echo ""
    echo "  1. 访问 https://github.com/new"
    echo "  2. 仓库名称：immortalwrt-github (或自定义)"
    echo "  3. 可见性：Public 或 Private"
    echo "  4. ❌ 不要初始化 README、.gitignore 或 license"
    echo "  5. 点击 'Create repository'"
    echo ""
    
    read -p "创建完成后，请输入仓库地址 (https://github.com/owner/repo.git): " REPO_URL
    
    if [ -n "$REPO_URL" ]; then
        git remote add origin "$REPO_URL"
        git branch -M main
        git push -u origin main
        log_info "已推送到：$REPO_URL"
    else
        log_warn "未输入仓库地址，跳过推送"
        log_info "稍后手动推送:"
        echo ""
        echo "  git remote add origin <your-repo-url>"
        echo "  git branch -M main"
        echo "  git push -u origin main"
        echo ""
    fi
fi

echo ""
log_step "5. 配置 GitHub Actions"
echo ""

log_info "启用 GitHub Actions..."
echo ""
echo "请在 GitHub 仓库中进行以下操作:"
echo ""
echo "  1. 进入 Settings → Actions → General"
echo "  2. 选择 'Allow all actions and reusable workflows'"
echo "  3. 点击 'Save'"
echo ""

read -p "是否现在打开浏览器？(y/N): " OPEN_BROWSER
if [ "$OPEN_BROWSER" = "y" ] || [ "$OPEN_BROWSER" = "Y" ]; then
    if command -v xdg-open &> /dev/null; then
        xdg-open "https://github.com/$GIT_NAME/$REPO_NAME/settings/actions" 2>/dev/null || true
    elif command -v open &> /dev/null; then
        open "https://github.com/$GIT_NAME/$REPO_NAME/settings/actions" 2>/dev/null || true
    fi
fi

echo ""
log_step "6. 验证配置"
echo ""

# 检查工作流文件
if [ -f ".github/workflows/build.yml" ]; then
    log_info "✅ 工作流文件存在"
else
    log_error "❌ 工作流文件不存在"
fi

# 检查 README
if [ -f "README.md" ]; then
    log_info "✅ README.md 存在"
else
    log_error "❌ README.md 不存在"
fi

# 检查构建脚本
if [ -f "build-local.sh" ] && [ -x "build-local.sh" ]; then
    log_info "✅ 本地构建脚本已就绪"
else
    log_warn "⚠️ 本地构建脚本不存在或无执行权限"
fi

echo ""
echo "=========================================="
echo "🎉 初始化完成!"
echo "=========================================="
echo ""
echo "下一步操作:"
echo ""
echo "  1. ✅ 在 GitHub 上启用 Actions (见上方提示)"
echo "  2. ✅ 进入 Actions 标签页，手动触发首次构建"
echo "  3. ✅ 或在本地运行 ./build-local.sh 测试"
echo ""
echo "仓库地址：https://github.com/$GIT_NAME/$REPO_NAME"
echo ""
echo "祝构建顺利！🚀"
echo ""
