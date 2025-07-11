#!/bin/bash

set -e

REALM_DIR="/etc/realm"
REALM_BIN="$REALM_DIR/realm"
CONFIG_PATH="$REALM_DIR/config.toml"
SERVICE_PATH="/etc/systemd/system/realm.service"

mkdir -p "$REALM_DIR"

# 获取最新版本 tag
echo "[信息] 正在获取 Realm 最新版本..."
LATEST_TAG=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep tag_name | cut -d '"' -f4)
DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${LATEST_TAG}/realm-x86_64-unknown-linux-gnu.tar.gz"

echo "[信息] 下载地址: $DOWNLOAD_URL"

# 下载并解压
echo "[信息] 正在下载 Realm $LATEST_TAG ..."
wget -qO "$REALM_DIR/realm.tar.gz" "$DOWNLOAD_URL"

echo "[信息] 正在解压..."
tar -zxvf "$REALM_DIR/realm.tar.gz" -C "$REALM_DIR"
chmod +x "$REALM_BIN"
rm -f "$REALM_DIR/realm.tar.gz"

# 创建默认配置
if [ ! -f "$CONFIG_PATH" ]; then
  echo "[信息] 创建默认配置文件 config.toml ..."
  cat <<EOF > "$CONFIG_PATH"
[network]
no_tcp = false
use_udp = true
EOF
  echo "[信息] 默认配置文件已创建。"
fi

# 创建 systemd 服务文件（含资源限制）
echo "[信息] 创建 systemd 服务..."
cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=Realm Port Forwarding
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
WorkingDirectory=$REALM_DIR
ExecStartPre=/bin/bash -c 'ulimit -n 1048576'
ExecStart=$REALM_BIN -c $CONFIG_PATH
LimitNOFILE=1048576
LimitNPROC=65535
Environment="RUST_BACKTRACE=1"
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 重载 systemd 并启动服务
echo "[信息] 启用开机启动并启动 Realm 服务..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable realm
systemctl restart realm

# 显示版本信息
REALM_VERSION=$($REALM_BIN -v)
echo ""
echo "✅ Realm 安装完成：$REALM_VERSION"
echo "📂 配置文件路径：$CONFIG_PATH"
echo "🛠️ systemd 启动已设置，并提升了文件句柄限制（ulimit -n 1048576）"
