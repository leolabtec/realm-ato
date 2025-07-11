#!/bin/bash

set -e

# 1. 创建工作目录
mkdir -p /root/realm
mkdir -p /root/.realm

# 2. 获取最新版本号
echo "获取 realm 最新版本..."
REALM_LATEST=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -z "$REALM_LATEST" ]]; then
    echo "获取版本失败，请检查网络连接或 GitHub API 是否受限"
    exit 1
fi
echo "最新版本：$REALM_LATEST"

# 3. 检测系统架构
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

case "${ARCH}-${OS}" in
  x86_64-linux)
    FILE_NAME="realm-x86_64-unknown-linux-gnu.tar.gz"
    ;;
  aarch64-linux)
    FILE_NAME="realm-aarch64-unknown-linux-gnu.tar.gz"
    ;;
  armv7l-linux)
    FILE_NAME="realm-armv7-unknown-linux-gnueabi.tar.gz"
    ;;
  *)
    echo "不支持的架构：$ARCH-$OS"
    exit 1
    ;;
esac

# 4. 下载并解压
DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${REALM_LATEST}/${FILE_NAME}"
echo "下载地址：$DOWNLOAD_URL"

cd /root/realm
wget -O realm.tar.gz "$DOWNLOAD_URL"
tar -xvf realm.tar.gz
chmod +x realm

# 5. 创建空白配置文件（只包含网络设置）
cat > /root/.realm/config.toml <<EOF
[network]
no_tcp = false
use_udp = true
EOF

# 6. 写入 systemd 服务文件
cat > /etc/systemd/system/realm.service <<EOF
[Unit]
Description=Realm Port Forwarding
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/.realm/config.toml

[Install]
WantedBy=multi-user.target
EOF

# 7. 重新加载 systemd 并提示完成
systemctl daemon-reload

echo -e "\n✅ Realm ${REALM_LATEST} 已成功安装！"
echo "配置文件路径：/root/.realm/config.toml"
echo "执行以下命令以启动服务："
echo "  systemctl start realm"
echo "如需开机自启："
echo "  systemctl enable realm"
