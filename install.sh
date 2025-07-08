#!/bin/bash

REALM_DIR="/etc/realm"
REALM_BIN="$REALM_DIR/realm"
CONFIG_PATH="$REALM_DIR/config.toml"
SERVICE_PATH="/etc/systemd/system/realm.service"

# 下载并解压 Realm 二进制文件
echo "[信息] 正在下载 Realm..."
wget -qO "$REALM_DIR/realm.tar.gz" "https://github.com/zhboner/realm/releases/download/v2.1.4/realm-x86_64-unknown-linux-gnu.tar.gz"

echo "[信息] 正在解压..."
tar -zxvf "$REALM_DIR/realm.tar.gz" -C "$REALM_DIR"
chmod +x "$REALM_BIN"

# 创建默认配置文件（如果没有）
if [ ! -f "$CONFIG_PATH" ]; then
  echo "[信息] 创建默认配置文件 config.toml ..."
  cat <<EOF > "$CONFIG_PATH"
[network]
no_tcp = false
use_udp = true
EOF
  echo "[信息] 默认配置文件已创建。"
fi

# 创建 systemd 服务
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
ExecStart=$REALM_BIN -c $CONFIG_PATH
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 启动并启用服务
echo "[信息] 启用开机自启并启动 Realm..."
systemctl daemon-reload
systemctl enable realm
systemctl restart realm

echo "✅ Realm 安装完成！"
echo "👉 配置文件路径: $CONFIG_PATH"
