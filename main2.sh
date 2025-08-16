#!/bin/bash

CONFIG_PATH="/root/.realm/config.toml"
REALM_SERVICE="realm"
RULE_LOG="/var/log/realm_rules.log"

[ ! -f "$RULE_LOG" ] && touch "$RULE_LOG" && chmod 644 "$RULE_LOG"

if [ ! -w "$CONFIG_PATH" ]; then
    echo "❌ 错误：无法写入 $CONFIG_PATH。请以足够权限运行。"
    exit 1
fi

check_system_port() {
    netstat -tuln 2>/dev/null | grep -q ":$1[[:space:]]" && return 0 || return 1
}

check_config_port() {
    grep -q "listen = .*:$1\"" "$CONFIG_PATH" && return 0 || return 1
}

validate_ip_port() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$ ]] || 
    [[ "$1" =~ ^[a-zA-Z0-9.-]+:[0-9]{1,5}$ ]]
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$RULE_LOG"
}

create_rule() {
    while true; do
        read -rp "规则名称（例如：hk_forward）： " rule_tag
        rule_tag=$(echo "$rule_tag" | tr -d '" ' | tr -s '\t')
        [ -z "$rule_tag" ] && { echo "❌ 规则名称不能为空"; continue; }
        grep -q "tag = \"$rule_tag\"" "$CONFIG_PATH" && { echo "❌ 规则名称已存在"; continue; }
        break
    done

    while true; do
        read -rp "监听端口（例如：8765）： " listen_port
        listen_port=$(echo "$listen_port" | tr -d ' ')
        if ! [[ "$listen_port" =~ ^[0-9]{1,5}$ ]] || [ "$listen_port" -lt 1 ] || [ "$listen_port" -gt 65535 ]; then
            echo "❌ 无效端口号（1~65535）"
            continue
        fi
        if check_system_port "$listen_port"; then
            echo "❌ 端口 $listen_port 已被系统占用"
            continue
        fi
        if check_config_port "$listen_port"; then
            echo "❌ 端口 $listen_port 已在 Realm 配置中使用"
            continue
        fi
        break
    done

    while true; do
        read -rp "远程地址:端口（如 1.1.1.1:7777 或 ddns.com:8888）： " remote
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
        echo "✅ 添加成功：$rule_tag -> $listen_port ➜ $remote"
        log_action "添加规则 [$rule_tag] - 监听: $listen_port -> $remote"
    else
        mv "${CONFIG_PATH}.bak" "$CONFIG_PATH"
        echo "❌ 无法重启 $REALM_SERVICE，已还原配置。请检查语法。"
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
    echo "🗑️ 正在扫描配置文件中的规则..."

    mapfile -t RULES < <(awk '
        BEGIN { start = 0; tag = ""; listen = ""; remote = "" }
        {
            if ($0 ~ /^\[\[endpoints\]\]/) {
                if (start > 0) {
                    printf("%d|%d|%s|%s|%s\n", start, NR-1, tag, listen, remote)
                }
                start = NR
                tag = ""; listen = ""; remote = ""
            }
            if ($0 ~ /tag *= *".*"/) {
                match($0, /tag *= *"([^"]+)"/, a); tag = a[1]
            }
            if ($0 ~ /listen *= *".*"/) {
                match($0, /listen *= *"([^"]+)"/, a); listen = a[1]
            }
            if ($0 ~ /remote *= *".*"/) {
                match($0, /remote *= *"([^"]+)"/, a); remote = a[1]
            }
        }
        END {
            if (start > 0) {
                printf("%d|%d|%s|%s|%s\n", start, NR, tag, listen, remote)
            }
        }
    ' "$CONFIG_PATH")

    total=${#RULES[@]}
    if [ "$total" -eq 0 ]; then
        echo "⚠️ 未找到任何规则块"
        read -rp "按回车返回菜单..."
        return
    fi

    echo "🔍 可删除的规则列表："
    for i in "${!RULES[@]}"; do
        IFS="|" read -r start end tag listen remote <<< "${RULES[i]}"
        idx=$((i+1))
        echo "$idx) [$tag]"
        echo "   监听: $listen"
        echo "   远程: $remote"
        echo "-----------------------------"
    done
    echo "0) 取消"

    read -rp "请输入要删除的规则编号： " sel
    if [[ "$sel" == "0" ]]; then return; fi
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "$total" ]; then
        echo "❌ 无效输入"
        read -rp "按回车返回菜单..."
        return
    fi

    cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"

    IFS="|" read -r start end tag listen remote <<< "${RULES[$((sel-1))]}"

    sed -i "${start},${end}d" "$CONFIG_PATH"

    if systemctl restart "$REALM_SERVICE"; then
        echo "✅ 已删除规则 [$tag] (监听 $listen ➜ $remote)"
        log_action "删除规则 [$tag] - 原监听: $listen -> $remote"
    else
        mv "${CONFIG_PATH}.bak" "$CONFIG_PATH"
        echo "❌ Realm 重启失败，配置已还原"
    fi

    read -rp "按回车返回菜单..."
}


restart_service() {
    echo "🔄 正在重启 Realm 服务..."
    if systemctl restart "$REALM_SERVICE"; then
        echo "✅ Realm 服务已成功重启"
    else
        echo "❌ 重启失败，请检查配置文件或 systemd 日志"
    fi
    read -rp "按回车键返回菜单..."
}

# 主菜单循环
while true; do
    clear
    echo "=== Realm 转发规则管理器 ==="
    echo "1) 创建规则"
    echo "2) 查看规则"
    echo "3) 删除规则"
    echo "4) 重启 Realm 服务"
    echo "0) 退出"
    echo "============================="
    read -rp "请选择操作： " choice
    case "$choice" in
        1) create_rule ;;
        2) list_rules ;;
        3) delete_rule ;;
        4) restart_service ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项"; read -rp "按回车继续..." ;;
    esac
done
