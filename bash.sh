#!/bin/bash

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误：请以 root 权限运行此脚本（使用 sudo）。"
    exit 1
fi

# 检查并安装依赖（curl 和 gawk）
install_dependency() {
    if ! command -v "$1" &>/dev/null; then
        echo "⏳ 检测到 $1 未安装，正在尝试安装..."
        if command -v apt-get &>/dev/null; then
            apt-get update
            apt-get install "$1" -y
        elif command -v yum &>/dev/null; then
            yum install "$1" -y
        else
            echo "❌ 错误：无法自动安装 $1，请手动安装。"
            exit 1
        fi
    fi
}

# 安装 curl 和 gawk
install_dependency "curl"
install_dependency "gawk"

# 创建目标目录
DEST_DIR="/etc/bash"
mkdir -p "$DEST_DIR"

# 下载并安装 main.sh 和 install.sh
INSTALL_URL="https://raw.githubusercontent.com/leolabtec/AutoRealm/refs/heads/main/install.sh"
MAIN_URL="https://raw.githubusercontent.com/leolabtec/AutoRealm/refs/heads/main/main.sh"

# 下载文件
echo "⏳ 正在下载 install.sh 和 main.sh ..."
curl -s -o "$DEST_DIR/install.sh" "$INSTALL_URL"
curl -s -o "$DEST_DIR/main.sh" "$MAIN_URL"

# 检查文件下载成功
if [ ! -f "$DEST_DIR/install.sh" ] || [ ! -f "$DEST_DIR/main.sh" ]; then
    echo "❌ 错误：文件下载失败。"
    exit 1
fi

# 设置文件权限
chmod +x "$DEST_DIR/install.sh" "$DEST_DIR/main.sh"
echo "✅ 文件权限已设置。"

# 执行 install.sh
echo "⏳ 正在执行 install.sh ..."
bash "$DEST_DIR/install.sh"

# 设置快捷键 alias r
BASHRC="$HOME/.bashrc"
ALIAS_LINE='alias r="bash /etc/bash/main.sh"'

if ! grep -Fx "$ALIAS_LINE" "$BASHRC" &>/dev/null; then
    echo "$ALIAS_LINE" >> "$BASHRC"
    echo "✅ 已添加快捷键 alias r 到 $BASHRC。"
fi

# 刷新 .bashrc 并执行 main.sh
source ~/.bashrc
bash /etc/bash/main.sh
