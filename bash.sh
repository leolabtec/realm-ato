#!/bin/bash

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误：请以 root 权限运行此脚本（使用 sudo）。"
    exit 1
fi

# 安装依赖函数
install_dependency() {
    if ! command -v "$1" &>/dev/null; then
        echo "⏳ 检测到 $1 未安装，正在安装..."
        if command -v apt-get &>/dev/null; then
            apt-get update
            apt-get install -y "$1"
        elif command -v yum &>/dev/null; then
            yum install -y "$1"
        else
            echo "❌ 无法自动安装 $1，请手动安装后重试。"
            exit 1
        fi
    fi
}

# 安装必要依赖
install_dependency "curl"
install_dependency "gawk"

# 设置脚本目标目录
DEST_DIR="/etc/bash"
echo "📁 创建脚本目录：$DEST_DIR"
mkdir -p "$DEST_DIR"

# 下载 install.sh 和 main.sh 脚本
INSTALL_URL="https://raw.githubusercontent.com/leolabtec/AutoRealm/refs/heads/main/install.sh"
MAIN_URL="https://raw.githubusercontent.com/leolabtec/AutoRealm/refs/heads/main/main.sh"

echo "⏬ 正在下载 install.sh 和 main.sh ..."
curl -fsSL "$INSTALL_URL" -o "$DEST_DIR/install.sh"
curl -fsSL "$MAIN_URL" -o "$DEST_DIR/main.sh"

# 检查是否成功下载
if [[ ! -s "$DEST_DIR/install.sh" || ! -s "$DEST_DIR/main.sh" ]]; then
    echo "❌ 下载失败，请检查网络或 GitHub 可用性。"
    exit 1
fi

# 设置执行权限
chmod +x "$DEST_DIR/install.sh" "$DEST_DIR/main.sh"
echo "✅ 脚本已设置执行权限"

# 执行 install.sh 安装 realm
echo "🚀 执行 install.sh 安装 Realm ..."
bash "$DEST_DIR/install.sh"

# 设置 alias 快捷键到 ~/.bashrc
BASHRC="$HOME/.bashrc"
ALIAS_LINE='alias r="bash /etc/bash/main.sh"'

if [ -f "$BASHRC" ] && ! grep -Fxq "$ALIAS_LINE" "$BASHRC"; then
    echo "$ALIAS_LINE" >> "$BASHRC"
    echo "✅ 已添加快捷命令 alias 'r' 到 $BASHRC"
fi

# 加载新 alias，执行主菜单
echo "🔁 正在刷新 Bash 环境..."
source "$BASHRC"

echo -e "\n🎉 所有组件安装完成！你现在可以输入 \033[1mr\033[0m 快速管理 Realm 转发规则。"
bash /etc/bash/main.sh
