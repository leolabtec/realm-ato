#!/bin/bash

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误：请以 root 权限运行此脚本（使用 sudo）。"
    exit 1
fi

# 安装依赖
install_dependency() {
    if ! command -v "$1" &>/dev/null; then
        echo "⏳ 未检测到 $1，正在安装..."
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install "$1" -y
        elif command -v yum &>/dev/null; then
            yum install "$1" -y
        else
            echo "❌ 无法自动安装 $1，请手动安装。"
            exit 1
        fi
    fi
}

install_dependency "curl"
install_dependency "gawk"

DEST_DIR="/etc/bash"
mkdir -p "$DEST_DIR"

# ✅ 使用正确格式的 raw URL
INSTALL_URL="https://raw.githubusercontent.com/leolabtec/realm-ato/main/install.sh"
MAIN_URL="https://raw.githubusercontent.com/leolabtec/realm-ato/main/main.sh"

echo "⏳ 正在下载脚本..."
curl -s -o "$DEST_DIR/install.sh" "$INSTALL_URL"
curl -s -o "$DEST_DIR/main.sh" "$MAIN_URL"

if [ ! -s "$DEST_DIR/install.sh" ] || [ ! -s "$DEST_DIR/main.sh" ]; then
    echo "❌ 下载失败或内容为空，请检查链接是否正确。"
    exit 1
fi

chmod +x "$DEST_DIR/install.sh" "$DEST_DIR/main.sh"
echo "✅ 文件已准备完毕。"

# 执行 install.sh
bash "$DEST_DIR/install.sh"

# 设置 alias
BASHRC="$HOME/.bashrc"
ALIAS_LINE='alias r="bash /etc/bash/main.sh"'

if ! grep -Fxq "$ALIAS_LINE" "$BASHRC"; then
    echo "$ALIAS_LINE" >> "$BASHRC"
    echo "✅ 已添加 alias r 到 $BASHRC"
fi

# 刷新并执行主菜单
source "$BASHRC"
bash /etc/bash/main.sh
