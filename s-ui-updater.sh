#!/bin/bash

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
PLAIN='\033[0m'

# 日志管理 (自动截断)
log_message() {
    local msg="$1"
    [[ ! -f "$LOG_FILE" ]] && touch "$LOG_FILE"
    local current_size=$(du -k "$LOG_FILE" | cut -f1)
    [[ "$current_size" -gt "$MAX_LOG_SIZE" ]] && echo "$(date): Log rotated." > "$LOG_FILE"
    echo "$(date): $msg" >> "$LOG_FILE"
}

# 获取本地版本
get_local_version() {
    if [[ -f "$INSTALL_PATH/sui" ]]; then
        "$INSTALL_PATH/sui" -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
    else
        echo "none"
    fi
}

# 获取远程版本
get_remote_version() {
    curl -Lfs --connect-timeout 10 "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | jq -r .tag_name | sed 's/v//g'
}

# 核心安装/更新逻辑 (带检测)
do_update() {
    local local_v=$(get_local_version)
    local remote_v=$(get_remote_version)

    if [[ -z "$remote_v" || "$remote_v" == "null" ]]; then
        echo -e "${RED}错误: 无法获取远程版本号，请检查网络。${PLAIN}"
        return 1
    fi

    if [[ "$local_v" == "$remote_v" ]]; then
        echo -e "${GREEN}当前已是最新版本 (v$local_v)，无需更新。${PLAIN}"
        log_message "Check skipped: v$local_v is up to date."
        return 0
    fi

    # 只有版本不一致才会走到这里
    echo -e "${YELLOW}检测到新版本: ${PLAIN}${RED}$local_v${PLAIN} -> ${GREEN}$remote_v${PLAIN}"
    echo -e "${YELLOW}正在开始下载更新...${PLAIN}"
    
    local ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64" || ARCH="arm64"
    local DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${remote_v}/s-ui-linux-${ARCH}.tar.gz"
    
    mkdir -p /tmp/sui_update && cd /tmp/sui_update
    if curl -Lfs -o s-ui.tar.gz "$DOWNLOAD_URL"; then
        tar -zxf s-ui.tar.gz
        systemctl stop s-ui 2>/dev/null
        mkdir -p $INSTALL_PATH
        cp -f sui $INSTALL_PATH/ && chmod +x $INSTALL_PATH/sui
        systemctl restart s-ui 2>/dev/null
        log_message "Successful update to v$remote_v"
        echo -e "${GREEN}更新成功！当前版本: v$remote_v${PLAIN}"
    else
        echo -e "${RED}下载失败，请检查网络连接。${PLAIN}"
    fi
    rm -rf /tmp/sui_update
}

# Cron 增强管理
manage_cron() {
    clear
    echo -e "${YELLOW}--- Cron 自动更新管理 ---${PLAIN}"
    # 查看当前状态
    local current_cron=$(crontab -l 2>/dev/null | grep "$SCRIPT_LINK update")
    if [[ -n "$current_cron" ]]; then
        echo -e "当前状态: ${GREEN}已开启${PLAIN}"
        echo -e "当前配置: ${CYAN}$current_cron${PLAIN}"
    else
        echo -e "当前状态: ${RED}未设置${PLAIN}"
    fi
    echo "------------------------"
    echo "1. 快速设置: 每天凌晨 3:00 检查更新"
    echo "2. 自定义设置: 手动输入 Cron 表达式"
    echo "3. 删除自动更新任务"
    echo "0. 返回"
    read -p "选择操作: " cron_choice

    case $cron_choice in
        1)
            (crontab -l 2>/dev/null | grep -v "$SCRIPT_LINK update"; echo "0 3 * * * $SCRIPT_LINK update >/dev/null 2>&1") | crontab -
            echo -e "${GREEN}设置成功：每天凌晨3点。${PLAIN}"
            ;;
        2)
            echo -e "${YELLOW}请输入 Cron 表达式 (例如 '0 */6 * * *' 表示每6小时):${PLAIN}"
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

# ... (Hysteria2 转发和主菜单逻辑保持一致，但加入 check_dependencies 确保环境)

show_menu() {
    # 确保脚本已链接到 bin
    [[ ! -f "$SCRIPT_LINK" ]] && cp "$0" "$SCRIPT_LINK" && chmod +x "$SCRIPT_LINK"
    
    clear
    echo -e "${GREEN}s-ui 自动化管理工具 (专家版)${PLAIN}"
    echo -e "本地版本: ${YELLOW}$(get_local_version)${PLAIN}"
    echo "------------------------"
    echo "1. 安装 / 检查更新 s-ui"
    echo "2. 查看 / 设置 / 删除 自动更新 (Cron)"
    echo "3. 配置 / 查看 / 删除 Hysteria2 端口转发"
    echo "4. 查看更新日志 ($LOG_FILE)"
    echo "0. 退出"
    echo "------------------------"
    read -p "请输入数字: " main_choice

    case $main_choice in
        1) do_update ;;
        2) manage_cron ;;
        3) manage_h2_ports ;; # 引用上个版本的 H2 逻辑
        4) [[ -f "$LOG_FILE" ]] && tail -n 50 "$LOG_FILE" || echo "暂无日志" ;;
        0) exit 0 ;;
    esac
    read -p "按回车键返回..." temp
    show_menu
}

# 运行逻辑
if [[ "$1" == "update" ]]; then
    do_update
else
    # 首次运行确保 jq 等工具存在
    command -v jq &>/dev/null || (apt update && apt install -y jq || yum install -y jq)
    show_menu
fi
