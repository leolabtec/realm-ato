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
    mapfile -t LINE_NUMS < <(grep -n '\[\[endpoints\]\]' "$CONFIG_PATH" | cut -d: -f1)
    total=${#LINE_NUMS[@]}
    if [ $total -eq 0 ]; then
        echo "⚠️ 没有可删除的规则"
        read -rp "按回车键返回菜单..."
        return
    fi

    echo "🗑️ 可删除的规则："
    for i in "${!LINE_NUMS[@]}"; do
        idx=$((i+1))
        line=${LINE_NUMS[$i]}
        tag=$(sed -n "$((line+1))p" "$CONFIG_PATH" | grep 'tag' | cut -d'"' -f2)
        echo "$idx) $tag"
    done
    echo "0) 取消"
    read -rp "输入要删除的规则编号： " num

    if [ "$num" = "0" ]; then
        return
    elif ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "$total" ]; then
        echo "❌ 无效的选择"
        read -rp "按回车键返回菜单..."
        return
    fi

    cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"

    start=${LINE_NUMS[$((num-1))]}
    if [ "$num" -eq "$total" ]; then
        end=$(wc -l < "$CONFIG_PATH")
    else
        end=$(( ${LINE_NUMS[$num]} - 1 ))
    fi

    sed -i "${start},${end}d" "$CONFIG_PATH"

    if systemctl restart "$REALM_SERVICE" 2>/dev/null; then
        echo "✅ 规则 $num 已删除"
        log_action "删除规则 [$num]"
    else
        echo "❌ 无法重启 $REALM_SERVICE"
        mv "${CONFIG_PATH}.bak" "$CONFIG_PATH"
        read -rp "按回车键返回菜单..."
    fi
}

# 主菜单循环
while true; do
    clear
    echo "=== Realm 转发规则管理器 ==="
    echo "1) 创建规则"
    echo "2) 查看规则"
    echo "3) 删除规则"
    echo "0) 退出"
    echo "============================="
    read -rp "请选择操作： " choice
    case "$choice" in
        1) create_rule ;;
        2) list_rules ;;
        3) delete_rule ;;
        0) exit 0 ;;
        *) echo "❌ 无效的选项"; read -rp "按回车键继续..." ;;
    esac
done
