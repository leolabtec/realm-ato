#!/bin/bash

CONFIG_PATH="/etc/realm/config.toml"
REALM_SERVICE="realm"
RULE_LOG="/var/log/realm_rules.log"

# 确保日志文件存在并具有适当的权限
[ ! -f "$RULE_LOG" ] && touch "$RULE_LOG" && chmod 644 "$RULE_LOG"

# 检查配置文件是否可写
if [ ! -w "$CONFIG_PATH" ]; then
    echo "❌ 错误：无法写入 $CONFIG_PATH。请以足够权限运行。"
    exit 1
fi

check_port() {
    netstat -tuln 2>/dev/null | grep -q ":$1[ \t]" && return 0 || return 1
}

validate_ip_port() {
    # 验证 IP:端口 或 主机名:端口 格式
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$ ]] || 
    [[ "$1" =~ ^[a-zA-Z0-9.-]+:[0-9]{1,5}$ ]]
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$RULE_LOG"
}

create_rule() {
    while true; do
        read -rp "规则名称（例如：hongkong_forward）： " rule_tag
        rule_tag=$(echo "$rule_tag" | tr -d '" ' | tr -s '\t')
        [ -z "$rule_tag" ] && { echo "❌ 规则名称不能为空"; continue; }
        grep -q "tag = \"$rule_tag\"" "$CONFIG_PATH" && { echo "❌ 规则名称已存在"; continue; }
        break
    done

    while true; do
        read -rp "监听端口（例如：8765）： " listen_port
        listen_port=$(echo "$listen_port" | tr -d ' ')
        if ! [[ "$listen_port" =~ ^[0-9]{1,5}$ ]] || [ "$listen_port" -lt 1 ] || [ "$listen_port" -gt 65535 ]; then
            echo "❌ 无效的端口号（必须为 1-65535）"
            continue
        fi
        check_port "$listen_port" && { echo "❌ 端口 $listen_port 已被占用"; continue; }
        break
    done

    while true; do
        read -rp "远程地址:端口（例如：1.1.1.1:7777 或 ddns.com:8888）： " remote
        remote=$(echo "$remote" | tr -d ' ')
        validate_ip_port "$remote" && break || echo "❌ 格式错误。使用 IP:端口 或 主机名:端口"
    done

    cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"

    cat <<EOF >> "$CONFIG_PATH"
[[endpoints]]
tag = "$rule_tag"
listen = "0.0.0.0:$listen_port"
remote = "$remote"
EOF

    if systemctl restart "$REALM_SERVICE" 2>/dev/null; then
        echo "✅ 规则已添加：$rule_tag -> 监听: $listen_port, 远程: $remote"
        log_action "添加规则 [$rule_tag] - 监听: $listen_port -> $remote"
    else
        echo "❌ 无法重启 $REALM_SERVICE"
        mv "${CONFIG_PATH}.bak" "$CONFIG_PATH"
        exit 1
    fi
}

list_rules() {
    echo "📋 当前规则："
    if ! grep -q '\[\[endpoints\]\]' "$CONFIG_PATH"; then
        echo "未配置任何规则"
    else
        awk '
        BEGIN { RS="\\[\\[endpoints\\]\\]"; ORS=""; i=0 }
        NR > 1 {
            i++
            match($0, /tag *= *"([^"]+)"/, t)
            match($0, /listen *= *"([^"]+)"/, l)
            match($0, /remote *= *"([^"]+)"/, r)
            printf("%d) [%s]\n   监听: %s\n   远程: %s\n--------------------------\n", i, t[1], l[1], r[1])
        }
        ' "$CONFIG_PATH"
    fi
    read -rp "按回车键返回菜单..."
}

delete_rule() {
    mapfile -t LINE_NUMS < <(grep -n '\[\[endpoints\]\
