#!/bin/bash
# =========================================================
# Realm 转发规则管理器 v1.2 (终结版带手动重启)
# 功能：
#  - 校验监听 IP 必须属于本机接口或公网 IP (0.0.0.0/:: 可选)
#  - 双重校验监听端口是否被占用
#  - 支持添加/查看/删除规则
#  - 自动重启 Realm（添加/删除规则后）
#  - 手动重启 Realm 并查看状态
#  - TOML 配置文件 /root/.realm/config.toml
# =========================================================

CONFIG_PATH="/root/.realm/config.toml"
REALM_SERVICE="realm"
RULE_LOG="/var/log/realm_rules.log"

[ ! -f "$RULE_LOG" ] && touch "$RULE_LOG" && chmod 644 "$RULE_LOG"
[ ! -f "$CONFIG_PATH" ] && mkdir -p "$(dirname "$CONFIG_PATH")" && touch "$CONFIG_PATH"

check_port() {
    local ip="$1"
    local port="$2"
    ss -tuln | grep -qE "0\.0\.0\.0:$port|$ip:$port" && return 1 || return 0
}

get_local_ips() {
    ip -o addr show | awk '{print $4}' | cut -d/ -f1
}

get_public_ips() {
    ipv4=$(curl -s4 ifconfig.co)
    ipv6=$(curl -s6 ifconfig.co)
    [ -n "$ipv4" ] && echo "$ipv4"
    [ -n "$ipv6" ] && echo "$ipv6"
}

validate_ip() {
    local ip="$1"
    [[ "$ip" == "0.0.0.0" || "$ip" == "::" ]] && return 0
    for i in $(get_local_ips) $(get_public_ips); do
        [[ "$ip" == "$i" ]] && return 0
    done
    return 1
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$RULE_LOG"
}

create_rule() {
    echo "=== 新建 Realm 转发规则 ==="
    echo "本机接口 IP：0.0.0.0"
    get_local_ips | sed 's/^/   - /'
    echo "公网 IP："
    get_public_ips | sed 's/^/   - /'

    while true; do
        read -rp "监听 IP (可选 0.0.0.0/::): " listen_ip
        listen_ip=$(echo "$listen_ip" | tr -d ' ')
        if validate_ip "$listen_ip"; then break; else echo "❌ 监听 IP 不在可选范围"; fi
    done

    while true; do
        read -rp "监听端口（1-65535）： " listen_port
        listen_port=$(echo "$listen_port" | tr -d ' ')
        if ! [[ "$listen_port" =~ ^[0-9]+$ ]] || [ "$listen_port" -lt 1 ] || [ "$listen_port" -gt 65535 ]; then
            echo "❌ 输入无效端口号"; continue
        fi
        check_port "$listen_ip" "$listen_port" && break || echo "❌ 端口 $listen_port 在 $listen_ip 或 0.0.0.0 已被占用"
    done

    while true; do
        read -rp "远程地址:端口 (例: 1.1.1.1:7777 或 ddns.com:8888): " remote
        remote=$(echo "$remote" | tr -d ' ')
        [[ "$remote" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$ ]] || [[ "$remote" =~ ^[a-zA-Z0-9.-]+:[0-9]{1,5}$ ]] && break
        echo "❌ 格式错误"
    done

    while true; do
        read -rp "规则名称: " rule_tag
        rule_tag=$(echo "$rule_tag" | tr -d '" ' | tr -s '\t')
        [ -z "$rule_tag" ] && { echo "❌ 规则名称不能为空"; continue; }
        grep -q "tag = \"$rule_tag\"" "$CONFIG_PATH" && { echo "❌ 规则名称已存在"; continue; }
        break
    done

    cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"

    cat <<EOF >> "$CONFIG_PATH"

[[endpoints]]
tag = "$rule_tag"
listen = "$listen_ip:$listen_port"
remote = "$remote"
EOF

    if systemctl restart "$REALM_SERVICE" 2>/dev/null; then
        echo "✅ 规则已添加"
        log_action "添加规则 [$rule_tag] - $listen_ip:$listen_port -> $remote"
    else
        echo "❌ 无法重启 $REALM_SERVICE"
        mv "${CONFIG_PATH}.bak" "$CONFIG_PATH"
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
    mapfile -t LINE_NUMS < <(grep -n '\[\[endpoints\]\]' "$CONFIG_PATH" | cut -d: -f1)
    total=${#LINE_NUMS[@]}
    [ $total -eq 0 ] && { echo "⚠️ 没有可删除的规则"; read -rp "按回车键返回..."; return; }

    echo "🗑️ 可删除的规则："
    for i in "${!LINE_NUMS[@]}"; do
        idx=$((i+1))
        line=${LINE_NUMS[$i]}
        tag=$(sed -n "$((line+1))p" "$CONFIG_PATH" | grep 'tag' | cut -d'"' -f2)
        echo "$idx) $tag"
    done
    echo "0) 取消"
    read -rp "输入要删除的规则编号： " num
    [ "$num" = "0" ] && return
    ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "$total" ] && { echo "❌ 无效选择"; read -rp "按回车键..."; return; }

    cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"
    start=${LINE_NUMS[$((num-1))]}
    end=$([ "$num" -eq "$total" ] && wc -l < "$CONFIG_PATH" || echo $(( ${LINE_NUMS[$num]} -1 )))
    sed -i "${start},${end}d" "$CONFIG_PATH"

    if systemctl restart "$REALM_SERVICE" 2>/dev/null; then
        echo "✅ 规则 $num 已删除"
        log_action "删除规则 [$num]"
    else
        echo "❌ 无法重启 $REALM_SERVICE"
        mv "${CONFIG_PATH}.bak" "$CONFIG_PATH"
    fi
}

manual_restart() {
    echo "🌀 手动重启 Realm 服务..."
    if systemctl restart "$REALM_SERVICE" 2>/dev/null; then
        echo "✅ Realm 已重启，状态如下："
        systemctl status "$REALM_SERVICE" --no-pager
        log_action "手动重启 Realm"
    else
        echo "❌ Realm 重启失败"
    fi
    read -rp "按回车返回菜单..."
}

# 主菜单
while true; do
    clear
    echo "=== Realm 转发规则管理器 ==="
    echo "1) 创建规则"
    echo "2) 查看规则"
    echo "3) 删除规则"
    echo "4) 手动重启 Realm 并查看状态"
    echo "0) 退出"
    echo "=============================="
    read -rp "选择操作: " choice
    case "$choice" in
        1) create_rule ;;
        2) list_rules ;;
        3) delete_rule ;;
        4) manual_restart ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项"; read -rp "按回车键继续..." ;;
    esac
done
