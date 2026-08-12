#!/bin/bash

# ==========================================
# s-ui 自动化管理工具
# ==========================================

# --- 基础配置区 ---
GITHUB_REPO="alireza0/s-ui"
INSTALL_PATH="/usr/local/s-ui"
LOG_FILE="/var/log/s-ui-update.log"
MAX_LOG_SIZE=10240 
SCRIPT_LINK="/usr/local/bin/s-ui-updater"
# ------------------

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 环境依赖检查与安装
check_dependencies() {
    local deps=("curl" "jq" "tar" "iptables")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${YELLOW}正在安装依赖: $dep...${PLAIN}"
            if command -v apt &> /dev/null; then
                apt update && apt install -y "$dep"
            elif command -v yum &> /dev/null; then
                yum install -y "$dep"
            fi
        fi
    done
}

# 日志管理
log_message() {
    local msg="$1"
    [[ ! -f "$LOG_FILE" ]] && touch "$LOG_FILE"
    local current_size=$(du -k "$LOG_FILE" | cut -f1)
    if [[ "$current_size" -gt "$MAX_LOG_SIZE" ]]; then
        echo "$(date): 日志超过10MB，已自动清理旧数据。" > "$LOG_FILE"
    fi
    echo "$(date): $msg" >> "$LOG_FILE"
}

# 版本获取
get_local_version() {
    if [[ -f "$INSTALL_PATH/sui" ]]; then
        "$INSTALL_PATH/sui" -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
    else
        echo "未安装"
    fi
}

get_remote_version() {
    curl -Lfs --connect-timeout 10 "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | jq -r .tag_name | sed 's/v//g'
}

# 更新逻辑
do_update() {
    check_dependencies
    local local_v=$(get_local_version)
    local remote_v=$(get_remote_version)

    if [[ -z "$remote_v" || "$remote_v" == "null" ]]; then
        echo -e "${RED}错误: 无法获取远程版本。${PLAIN}"
        return 1
    fi

    if [[ "$local_v" == "$remote_v" ]]; then
        echo -e "${GREEN}当前已是最新版本 (v$local_v)，无需重复下载。${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}新版本检测成功: ${RED}$local_v${PLAIN} -> ${GREEN}$remote_v${PLAIN}"
    
    local ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64" || ARCH="arm64"
    local DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${remote_v}/s-ui-linux-${ARCH}.tar.gz"
    
    mkdir -p /tmp/sui_update && cd /tmp/sui_update
    echo -e "${YELLOW}正在从 GitHub 下载二进制文件...${PLAIN}"
    if curl -Lfs -o s-ui.tar.gz "$DOWNLOAD_URL"; then
        tar -zxf s-ui.tar.gz
        systemctl stop s-ui 2>/dev/null
        mkdir -p $INSTALL_PATH
        cp -f sui $INSTALL_PATH/ && chmod +x $INSTALL_PATH/sui
        systemctl daemon-reload
        systemctl restart s-ui 2>/dev/null
        log_message "成功更新至 v$remote_v"
        echo -e "${GREEN}s-ui 已成功安装/更新至 v$remote_v${PLAIN}"
    else
        echo -e "${RED}下载失败，请检查网络。${PLAIN}"
    fi
    rm -rf /tmp/sui_update
}

# Cron 管理
manage_cron() {
    clear
    echo -e "${YELLOW}--- Cron 自动更新管理 ---${PLAIN}"
    local current_cron=$(crontab -l 2>/dev/null | grep "$SCRIPT_LINK update")
    if [[ -n "$current_cron" ]]; then
        echo -e "当前状态: ${GREEN}已开启${PLAIN}"
        echo -e "当前配置: ${CYAN}$current_cron${PLAIN}"
    else
        echo -e "当前状态: ${RED}未设置${PLAIN}"
    fi
    echo "------------------------"
    echo "1. 快速设置: 每天凌晨 3:00 检查更新"
    echo "2. 自定义设置: 输入 Cron 表达式"
    echo "3. 删除自动更新任务"
    echo "0. 返回"
    read -p "选择操作: " cron_choice

    case $cron_choice in
        1)
            (crontab -l 2>/dev/null | grep -v "$SCRIPT_LINK update"; echo "0 3 * * * $SCRIPT_LINK update >/dev/null 2>&1") | crontab -
            echo -e "${GREEN}设置成功：每天凌晨3点。${PLAIN}"
            ;;
        2)
            echo -e "${YELLOW}请输入 Cron 表达式 (如 '0 */12 * * *' 表示每12小时):${PLAIN}"
            read -p "表达式: " custom_exp
            (crontab -l 2>/dev/null | grep -v "$SCRIPT_LINK update"; echo "$custom_exp $SCRIPT_LINK update >/dev/null 2>&1") | crontab -
            echo -e "${GREEN}自定义设置成功。${PLAIN}"
            ;;
        3)
            crontab -l | grep -v "$SCRIPT_LINK update" | crontab -
            echo -e "${RED}已删除自动更新任务。${PLAIN}"
            ;;
    esac
}

# Hysteria2 端口转发
manage_h2_ports() {
    check_dependencies
    clear
    echo -e "${YELLOW}--- Hysteria2 端口转发 (UDP) ---${PLAIN}"
    echo "1. 添加转发规则 (端口段映射)"
    echo "2. 查看当前转发规则"
    echo "3. 清除所有相关转发规则"
    echo "0. 返回"
    read -p "选择操作: " h2_choice

    case $h2_choice in
        1)
            echo -e "${CYAN}提示: 格式为 起始端口:结束端口 (如 20000:20010)${PLAIN}"
            read -p "输入外部 UDP 端口段: " port_range
            read -p "输入内部监听端口 (默认 443): " target_port
            target_port=${target_port:-443}
            
            iptables -t nat -A PREROUTING -p udp --dport $port_range -j REDIRECT --to-ports $target_port
            
            # 持久化保存
            if command -v netfilter-persistent &> /dev/null; then
                netfilter-persistent save
            fi
            echo -e "${GREEN}转发已生效: UDP $port_range -> $target_port${PLAIN}"
            ;;
        2)
            echo -e "${YELLOW}当前 iptables NAT 规则:${PLAIN}"
            iptables -t nat -L PREROUTING -n --line-numbers | grep -E "REDIRECT|dport"
            ;;
        3)
            local lines=$(iptables -t nat -L PREROUTING -n --line-numbers | grep "REDIRECT" | awk '{print $1}' | sort -rn)
            for line in $lines; do
                iptables -t nat -D PREROUTING $line
            done
            echo -e "${RED}已清除所有重定向规则。${PLAIN}"
            ;;
    esac
}

# 主菜单
show_menu() {
    if [[ ! -f "$SCRIPT_LINK" ]]; then
        cp "$0" "$SCRIPT_LINK" && chmod +x "$SCRIPT_LINK"
    fi
    
    clear
    echo -e "${GREEN}s-ui 自动化管理工具 (专家版)${PLAIN}"
    echo -e "本地版本: ${YELLOW}$(get_local_version)${PLAIN}"
    echo "------------------------"
    echo "1. 安装 / 检查更新 s-ui"
    echo "2. 查看 / 设置 / 删除 自动更新 (Cron)"
    echo "3. 配置 / 查看 / 删除 Hysteria2 端口转发"
    echo "4. 查看更新日志"
    echo "0. 退出"
    echo "------------------------"
    read -p "请输入数字: " main_choice

    case $main_choice in
        1) do_update ;;
        2) manage_cron ;;
        3) manage_h2_ports ;;
        4) [[ -f "$LOG_FILE" ]] && tail -n 50 "$LOG_FILE" || echo "暂无日志" ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
    read -p "按回车键返回..." temp
    show_menu
}

# 运行逻辑
if [[ "$1" == "update" ]]; then
    do_update
else
    show_menu
fi
