#!/bin/bash

# ==========================================
# 项目: s-ui 一键安装/更新/端口转发工具
# ==========================================

# --- 基础配置区 ---
GITHUB_REPO="alireza0/s-ui"
INSTALL_PATH="/usr/local/s-ui"
LOG_FILE="/var/log/s-ui-update.log"
MAX_LOG_SIZE=10240 # 10MB (KB单位)
SCRIPT_LINK="/usr/local/bin/s-ui-updater"
# ------------------

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 1. 日志管理函数 (自动截断)
log_message() {
    local msg="$1"
    if [ -f "$LOG_FILE" ]; then
        local current_size=$(du -k "$LOG_FILE" | cut -f1)
        if [ "$current_size" -gt "$MAX_LOG_SIZE" ]; then
            echo "$(date): Log size exceeded 10MB, rotating..." > "$LOG_FILE"
        fi
    fi
    echo "$(date): $msg" >> "$LOG_FILE"
    echo -e "${GREEN}$(date): $msg${PLAIN}"
}

# 2. 架构自动识别
get_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "amd64" ;;
    esac
}

# 3. 环境依赖检查与安装
check_dependencies() {
    local deps=("curl" "jq" "tar" "iptables")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_message "Installing dependency: $dep"
            if command -v apt &> /dev/null; then
                apt update && apt install -y "$dep"
            elif command -v yum &> /dev/null; then
                yum install -y "$dep"
            fi
        fi
    done
}

# 4. 核心安装/更新逻辑
do_update() {
    check_dependencies
    local ARCH=$(get_arch)
    local CURRENT_VERSION=$($INSTALL_PATH/sui -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    
    # 获取远端版本
    local API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    local LATEST_JSON=$(curl -Lfs --connect-timeout 10 "$API_URL")
    local LATEST_VERSION=$(echo "$LATEST_JSON" | jq -r .tag_name | sed 's/v//g')

    if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
        log_message "Error: Failed to fetch remote version."
        return 1
    fi

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        log_message "Update found: $CURRENT_VERSION -> $LATEST_VERSION"
        local DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${LATEST_VERSION}/s-ui-linux-${ARCH}.tar.gz"
        
        mkdir -p /tmp/sui_update && cd /tmp/sui_update
        if curl -Lfs -o s-ui.tar.gz "$DOWNLOAD_URL"; then
            tar -zxf s-ui.tar.gz
            systemctl stop s-ui 2>/dev/null
            mkdir -p $INSTALL_PATH
            cp -f sui $INSTALL_PATH/
            chmod +x $INSTALL_PATH/sui
            # 如果是初次安装，可能需要下载配置并设置服务，这里简化为二进制替换
            log_message "Update successful to v$LATEST_VERSION"
            systemctl restart s-ui || log_message "Note: s-ui service not started. Please configure it first."
        else
            log_message "Download failed."
        fi
        rm -rf /tmp/sui_update
    else
        log_message "Already up to date: v$CURRENT_VERSION"
    fi
}

# 5. Cron 任务管理
manage_cron() {
    echo -e "\n${YELLOW}--- Cron 自动更新设置 ---${PLAIN}"
    echo "1. 设置每天凌晨 3:00 自动检查更新"
    echo "2. 删除自动更新任务"
    echo "0. 返回"
    read -p "选择操作: " cron_choice
    
    case $cron_choice in
        1)
            (crontab -l 2>/dev/null | grep -v "s-ui-updater update"; echo "0 3 * * * $SCRIPT_LINK update >/dev/null 2>&1") | crontab -
            echo -e "${GREEN}Cron task set: 0 3 * * *${PLAIN}"
            ;;
        2)
            crontab -l | grep -v "s-ui-updater update" | crontab -
            echo -e "${RED}Cron task removed.${PLAIN}"
            ;;
    esac
}

# 6. Hysteria2 端口转发管理 (iptables)
manage_h2_ports() {
    echo -e "\n${YELLOW}--- Hysteria2 端口转发 (UDP) ---${PLAIN}"
    echo "1. 添加转发规则 (例如 20000-20010 -> 443)"
    echo "2. 查看当前转发规则"
    echo "3. 清除所有 Hysteria2 转发规则"
    echo "0. 返回"
    read -p "选择操作: " h2_choice

    case $h2_choice in
        1)
            read -p "输入外部端口段 (如 20000:20010): " port_range
            read -p "输入内部目标端口 (默认 443): " target_port
            target_port=${target_port:-443}
            iptables -t nat -A PREROUTING -p udp --dport $port_range -j REDIRECT --to-ports $target_port
            # 保存规则 (适配不同系统)
            if command -v netfilter-persistent &> /dev/null; then
                netfilter-persistent save
            else
                iptables-save > /etc/iptables.rules
            fi
            echo -e "${GREEN}Redirect rule added: UDP $port_range -> $target_port${PLAIN}"
            ;;
        2)
            iptables -t nat -L PREROUTING -n --line-numbers | grep "REDIRECT"
            ;;
        3)
            # 简单处理：清除所有 nat PREROUTING 规则或根据特征清除
            iptables -t nat -F PREROUTING
            echo -e "${RED}All NAT PREROUTING rules flushed.${PLAIN}"
            ;;
    esac
}

# 7. 脚本自安装
install_self() {
    if [[ ! -f "$SCRIPT_LINK" ]]; then
        cp "$0" "$SCRIPT_LINK"
        chmod +x "$SCRIPT_LINK"
    fi
}

# 主菜单
show_menu() {
    install_self
    clear
    echo -e "${GREEN}s-ui 自动化管理脚本${PLAIN}"
    echo "------------------------"
    echo "1. 安装 / 检查更新 s-ui"
    echo "2. 设置 / 查看 / 删除 自动更新 (Cron)"
    echo "3. 配置 / 查看 / 删除 Hysteria2 端口转发"
    echo "4. 查看更新日志"
    echo "0. 退出"
    echo "------------------------"
    read -p "请输入数字: " main_choice

    case $main_choice in
        1) do_update ;;
        2) manage_cron ;;
        3) manage_h2_ports ;;
        4) tail -n 50 $LOG_FILE ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
    read -p "按回车键返回主菜单..." temp
    show_menu
}

# 判断命令行参数
if [[ "$1" == "update" ]]; then
    do_update
else
    show_menu
fi
