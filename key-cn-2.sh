#!/bin/bash

# ==============================================================================
#  SSH 公钥自动部署脚本 (适用于 GitHub 或远程链接公钥同步)
#  作者：lansepeach (已添加 PermitRootLogin 补丁)
#  日期：2025-12-04
#  功能：自动从 GitHub 或远程链接获取 SSH 公钥、设置 SSH 参数、添加定时任务更新密钥
#  支持系统：Debian / Ubuntu / CentOS
#  版权：MIT License
# ==============================================================================

# ========== 全局变量 ==========
log_file="/var/log/key-cn-2.log"
timestamp=$(date '+%Y%m%d%H%M%S')
backup_flag_file="/etc/ssh/.sshd_config_backup_done"

# ========== 函数定义 ==========
print_help() {
    echo "用法: bash $0 [选项]"
    echo "可用选项："
    echo "  -g <github 用户名>        GitHub 用户名（与 -u 二选一）"
    echo "  -u <公钥 URL 链接>         公钥链接地址（与 -g 二选一）"
    echo "  -m <分钟间隔>              可选：自动更新间隔（默认 5）必须和-o搭配使用在-o前面"
    echo "  -o                        可选：开启自动定时任务"
    echo "  -p <端口号>                可选：更改 SSH 端口"
    echo "  -d                        可选：禁用 SSH 密码登录"
    echo "  -v                        查看自动更新日志"
    echo "  -h                        显示帮助"
    echo "示例:"
    echo "  bash $0 -g your_github_username -m 5 -o -d -p 2222"
    echo "  bash $0 -u https://your.domain/key.pub -o -p 2222"
}

log() {
    echo "[INFO] $(date '+%F %T') $1" | tee -a "$log_file"
}
warn() {
    echo "[WARN] $(date '+%F %T') $1" | tee -a "$log_file"
}
err() {
    echo "[ERROR] $(date '+%F %T') $1" | tee -a "$log_file" >&2
}

# ========== 检查必须为 root 执行 ==========
if [[ "$(id -u)" -ne 0 ]]; then
    err "此脚本必须以 root 身份运行"
    exit 1
fi

# ========== 参数解析 ==========
github_user=""
key_url=""
interval="5"
setup_cron=0
disable_password_login=0
ssh_port=""
view_log=0

# 若无参数传入，则显示帮助信息但继续执行
if [[ $# -eq 0 ]]; then
    print_help
fi

while getopts ":g:u:m:op:dhv" opt; do
  case $opt in
    g) github_user="$OPTARG" ;;
    u) key_url="$OPTARG" ;;
    m) interval="$OPTARG" ;;
    o) setup_cron=1 ;;
    d) disable_password_login=1 ;;
    p) ssh_port="$OPTARG" ;;
    v) view_log=1 ;;
    h) print_help ; exit 0 ;;
    :) err "选项 -$OPTARG 缺少参数"; exit 1 ;;
    \?) err "无效参数: -$OPTARG"; print_help; exit 1 ;;
  esac
done

# ========== 查看日志模式 ==========
if [[ "$view_log" -eq 1 ]]; then
    if [[ -f "$log_file" ]]; then
        less "$log_file"
    else
        echo "日志文件不存在：$log_file"
    fi
    exit 0
fi

# ========== 参数合法性校验 ==========
if ! [[ "$interval" =~ ^[1-9][0-9]*$ ]]; then
    err "无效的分钟间隔，请输入正整数"
    exit 1
fi
if [[ -n "$ssh_port" && (! "$ssh_port" =~ ^[0-9]{1,5}$ || "$ssh_port" -lt 1 || "$ssh_port" -gt 65535) ]]; then
    err "无效的 SSH 端口号：$ssh_port，应为 1-65535 之间的数字"
    exit 1
fi

# ========== 交互补全参数 ==========
if [[ -z "$github_user" && -z "$key_url" ]]; then
    read -p "请选择公钥来源输入1或2回车（1=GitHub用户名 2=链接地址）: " key_source
    if [[ "$key_source" == "1" ]]; then
        read -p "请输入 GitHub 用户名: " github_user
    else
        read -p "请输入公钥链接地址: " key_url
    fi
fi
if [[ -z "$interval" ]]; then
    read -p "请输入密钥更新间隔分钟数 (默认5): " interval
    interval=${interval:-5}
fi
if [[ "$setup_cron" -eq 0 ]]; then
    read -p "是否开启自动定时任务？(Y/n): " cron_choice
    [[ "$cron_choice" =~ ^[Yy]$ ]] && setup_cron=1
fi
if [[ "$disable_password_login" -eq 0 ]]; then
    read -p "是否禁用 SSH 密码登录? (y/N): " disable_choice
    [[ "$disable_choice" =~ ^[Yy]$ ]] && disable_password_login=1
fi
if [[ -z "$ssh_port" ]]; then
    read -p "是否修改 SSH 端口? (输入空闲0到65535的端口数字，留空为不修改): " ssh_port
fi

# ========== 显示参数信息 ==========
[[ -n "$github_user" ]] && log "GitHub 帐号为: $github_user"
[[ -n "$key_url" ]] && log "公钥链接地址为: $key_url"
log "密钥更新间隔（分钟）: $interval"
log "开启自动定时任务: $([[ "$setup_cron" -eq 1 ]] && echo "是" || echo "否")"
log "禁用密码登录: $([[ "$disable_password_login" -eq 1 ]] && echo "是" || echo "否")"
[[ -n "$ssh_port" ]] && log "SSH 端口: $ssh_port"

# ========== 获取公钥 ==========
log "获取公钥..."
mkdir -p /root/.ssh
if [[ -n "$github_user" ]]; then
    curl -sf "https://git666.463791874.xyz/proxy/https://github.com/$github_user.keys" -o /root/.ssh/authorized_keys || {
        err "无法从 GitHub 获取公钥，请检查用户名是否正确"
        exit 1
    }
elif [[ -n "$key_url" ]]; then
    if [[ "$key_url" =~ ^http:// ]]; then
        err "不允许使用 HTTP，必须为 HTTPS 以确保安全"
        exit 1
    fi
    curl -sf "$key_url" -o /root/.ssh/authorized_keys || {
        err "无法从指定链接下载公钥，请检查链接地址"
        exit 1
    }
fi

# 检查公钥格式合法性
if ! grep -qE '^ssh-(rsa|ed25519|ecdsa)' /root/.ssh/authorized_keys; then
    err "获取的公钥无效或为空，请检查来源"
    exit 1
fi
chmod 600 /root/.ssh/authorized_keys
log "SSH 密钥安装成功！"

# ========== 修改 SSH 配置 ==========
sshd_config="/etc/ssh/sshd_config"
if [[ ! -f "$backup_flag_file" ]]; then
    backup_config="${sshd_config}.bak.$timestamp"
    cp "$sshd_config" "$backup_config"
    echo "$backup_config" > "$backup_flag_file"
    log "备份原 sshd_config 到 $backup_config"
fi

# 修改端口
if [[ -n "$ssh_port" ]]; then
    sed -i "s/^#Port .*/Port $ssh_port/;s/^Port .*/Port $ssh_port/" "$sshd_config" || echo "Port $ssh_port" >> "$sshd_config"
    log "SSH端口更改为 $ssh_port"
fi

# 启用公钥登录
sed -i "s/^#PubkeyAuthentication .*/PubkeyAuthentication yes/;s/^PubkeyAuthentication .*/PubkeyAuthentication yes/" "$sshd_config"
log "启用 SSH 公钥登录"

# ------------------------------------------------------------
# [新增] 强制设置 PermitRootLogin 为 prohibit-password
# ------------------------------------------------------------
if grep -q "^#\?PermitRootLogin" "$sshd_config"; then
    sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/" "$sshd_config"
else
    echo "PermitRootLogin prohibit-password" >> "$sshd_config"
fi
log "设置 Root 仅允许密钥登录 (PermitRootLogin prohibit-password)"
# ------------------------------------------------------------

# 禁用密码登录
if [[ "$disable_password_login" -eq 1 ]]; then
    sed -i "s/^#PasswordAuthentication .*/PasswordAuthentication no/;s/^PasswordAuthentication .*/PasswordAuthentication no/" "$sshd_config"
    log "禁用 SSH 密码登录"
fi

systemctl restart sshd && log "SSH 服务重启完成"

# ========== 设置或移除 cron 任务 ==========
cron_cmd="/bin/bash $0"
[[ -n "$github_user" ]] && cron_cmd+=" -g $(printf '%q' "$github_user")"
[[ -n "$key_url" ]] && cron_cmd+=" -u $(printf '%q' "$key_url")"
cron_cmd+=" -m $interval -o"
[[ "$disable_password_login" -eq 1 ]] && cron_cmd+=" -d"
[[ -n "$ssh_port" ]] && cron_cmd+=" -p $ssh_port"
cron_expression="*/$interval * * * * $cron_cmd >> $log_file 2>&1"
cron_file_tmp="/tmp/current_cron"

crontab -l 2>/dev/null | grep -v "$0" | grep -v 'key-cn-2.log' > "$cron_file_tmp"

if [[ "$setup_cron" -eq 1 ]]; then
    if (( 60 % interval != 0 )); then
        warn "自定义分钟间隔 $interval 不能被 60 整除，cron 可能不精确。"
    fi
    echo "$cron_expression" >> "$cron_file_tmp"
    echo "@monthly truncate -s 0 $log_file" >> "$cron_file_tmp"
    crontab "$cron_file_tmp"
    log "已设置每 $interval 分钟密钥更新 cron 作业。"
else
    crontab "$cron_file_tmp"
    log "未设置自动更新 cron 任务。"
fi

rm -f "$cron_file_tmp"

# ========== 日志清理（保留最近1000行） ==========
if [[ -f "$log_file" ]]; then
    tail -n 1000 "$log_file" > "$log_file.tmp" && mv "$log_file.tmp" "$log_file"
fi

exit 0
