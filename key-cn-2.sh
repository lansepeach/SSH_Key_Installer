#!/usr/bin/env bash
# ==============================================================================
#  Key CN SSH 公钥自动更新脚本（AI 重构增强版）
#  日期：2026-5-01
#  作者：lansepeach
#  适用于：
#    - Debian 11/12/13
#    - Ubuntu 20.04/22.04/24.04+
#
#  功能：
#    - 从 GitHub 用户名或 HTTPS 公钥链接同步 SSH 公钥
#    - 安全更新 /root/.ssh/authorized_keys
#    - 支持修改 SSH 端口
#    - 支持禁用密码登录
#    - 强制 root 仅允许密钥登录
#    - 使用 /etc/ssh/sshd_config.d/00-key-cn.conf 管理 SSH 配置
#    - 自动注释其他文件里的冲突 SSH 配置
#    - 修改配置前备份
#    - 修改配置后先 sshd -t 校验，通过后才 reload/restart
#    - 如果 SSH 配置无变化，则不 reload/restart SSH
#    - 如果仅 authorized_keys 更新，则不 reload/restart SSH
#    - 自动设置 cron 定时任务
#    - 自动日志清理
#    - 防止并发执行
#    - 支持自定义 GitHub 代理前缀，但默认不内置代理
#
#  License: MIT
# ==============================================================================

set -u
umask 077

# ==================== 基础配置 ====================

LOG_FILE="/var/log/key-cn-2.log"
LOCK_FILE="/run/key-cn-2.lock"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN_FILE="${SSHD_DROPIN_DIR}/00-key-cn.conf"

BACKUP_DIR="/etc/ssh/key-cn-backups"
BACKUP_FLAG_FILE="/etc/ssh/.key-cn-backup-done"

AUTHORIZED_KEYS="/root/.ssh/authorized_keys"

DEFAULT_INTERVAL="10"

# GitHub 代理前缀，默认留空，不写死代理
# 可通过以下两种方式设置：
#   1. 命令行参数：-P 'https://your-proxy.example/proxy/'
#   2. 环境变量：KEY_CN_GITHUB_PROXY_PREFIX='https://your-proxy.example/proxy/'
GITHUB_PROXY_PREFIX="${KEY_CN_GITHUB_PROXY_PREFIX:-}"

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SSH_CONFIG_CHANGED=0
AUTHORIZED_KEYS_CHANGED=0

# ==================== 日志函数 ====================

log() {
    local msg="[INFO]  $(date '+%F %T') $*"
    echo "$msg" >> "$LOG_FILE"
    [[ -t 1 ]] && echo "$msg"
}

warn() {
    local msg="[WARN]  $(date '+%F %T') $*"
    echo "$msg" >> "$LOG_FILE"
    [[ -t 1 ]] && echo "$msg"
}

err() {
    local msg="[ERROR] $(date '+%F %T') $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

die() {
    err "$*"
    exit 1
}

# ==================== 帮助信息 ====================

print_help() {
    cat <<EOF
用法:
  bash $SCRIPT_PATH [选项]

公钥来源，二选一：
  -g <GitHub用户名>        从 GitHub 用户名获取公钥
  -u <HTTPS公钥链接>       从 HTTPS URL 获取公钥

可选参数：
  -m <分钟间隔>            自动更新间隔，默认 ${DEFAULT_INTERVAL} 分钟
  -o                       开启或更新自动定时任务
  -p <端口号>              修改 SSH 端口，范围 1-65535
  -d                       禁用 SSH 密码登录
  -P <GitHub代理前缀>      可选：设置 GitHub 代理前缀，用于获取 GitHub 公钥
  -v                       查看日志
  -h                       显示帮助

示例：
  bash $SCRIPT_PATH -g your_github_username -m 10 -o -d -p 2222
  bash $SCRIPT_PATH -u https://example.com/authorized_keys -m 10 -o -d -p 2222

使用 GitHub 代理前缀示例：
  bash $SCRIPT_PATH -g your_github_username -m 10 -o -d -p 2222 -P 'https://your-proxy.example/proxy/'

也可以通过环境变量设置代理前缀：
  KEY_CN_GITHUB_PROXY_PREFIX='https://your-proxy.example/proxy/' bash $SCRIPT_PATH -g your_github_username

说明：
  1. -g 和 -u 不能同时使用。
  2. -P 只影响通过 -g 获取 GitHub 公钥，不影响 -u。
  3. -P 不是脚本下载地址，而是 GitHub 公钥请求代理前缀。
  4. 脚本默认不内置代理地址。
EOF
}

# ==================== 加锁 ====================

acquire_lock() {
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        warn "脚本已在运行，跳过本次执行"
        exit 0
    fi
}

# ==================== 基础检查 ====================

check_root() {
    [[ "$(id -u)" -eq 0 ]] || die "此脚本必须以 root 身份运行"
}

check_dependencies() {
    local missing=()

    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v sshd >/dev/null 2>&1 || [[ -x /usr/sbin/sshd ]] || missing+=("openssh-server")
    command -v systemctl >/dev/null 2>&1 || missing+=("systemd/systemctl")
    command -v flock >/dev/null 2>&1 || missing+=("flock")

    if (( ${#missing[@]} > 0 )); then
        die "缺少依赖：${missing[*]}，请先安装。Debian/Ubuntu 可执行：apt update && apt install -y curl openssh-server util-linux"
    fi
}

ensure_log_file() {
    touch "$LOG_FILE" || die "无法写入日志文件：$LOG_FILE"
    chmod 600 "$LOG_FILE" 2>/dev/null || true
}

# ==================== 参数默认值 ====================

github_user=""
key_url=""
interval="$DEFAULT_INTERVAL"
setup_cron=0
disable_password_login=0
ssh_port=""
view_log=0

# ==================== 参数解析 ====================

parse_args() {
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi

    while getopts ":g:u:m:op:dP:hv" opt; do
        case "$opt" in
            g) github_user="$OPTARG" ;;
            u) key_url="$OPTARG" ;;
            m) interval="$OPTARG" ;;
            o) setup_cron=1 ;;
            p) ssh_port="$OPTARG" ;;
            d) disable_password_login=1 ;;
            P) GITHUB_PROXY_PREFIX="$OPTARG" ;;
            v) view_log=1 ;;
            h) print_help; exit 0 ;;
            :) die "选项 -$OPTARG 缺少参数" ;;
            \?) print_help; die "无效参数：-$OPTARG" ;;
        esac
    done
}

# ==================== 查看日志 ====================

view_log_if_needed() {
    if [[ "$view_log" -eq 1 ]]; then
        if [[ -f "$LOG_FILE" ]]; then
            less "$LOG_FILE"
        else
            echo "日志文件不存在：$LOG_FILE"
        fi
        exit 0
    fi
}

# ==================== 参数校验 ====================

validate_args() {
    if [[ -n "$github_user" && -n "$key_url" ]]; then
        die "-g 和 -u 只能二选一，不能同时使用"
    fi

    if [[ -z "$github_user" && -z "$key_url" ]]; then
        die "必须提供 -g <GitHub用户名> 或 -u <HTTPS公钥链接>"
    fi

    if ! [[ "$interval" =~ ^[1-9][0-9]*$ ]]; then
        die "无效的分钟间隔：$interval，请输入正整数"
    fi

    if (( interval < 1 || interval > 1440 )); then
        die "分钟间隔建议范围为 1-1440，当前为：$interval"
    fi

    if [[ -n "$ssh_port" ]]; then
        if ! [[ "$ssh_port" =~ ^[0-9]{1,5}$ ]] || (( ssh_port < 1 || ssh_port > 65535 )); then
            die "无效的 SSH 端口号：$ssh_port，应为 1-65535"
        fi
    fi

    if [[ -n "$key_url" ]]; then
        if [[ "$key_url" =~ ^http:// ]]; then
            die "不允许使用 HTTP 公钥链接，请使用 HTTPS"
        fi

        if ! [[ "$key_url" =~ ^https:// ]]; then
            die "公钥链接必须以 https:// 开头"
        fi
    fi

    if [[ -n "$GITHUB_PROXY_PREFIX" ]]; then
        if [[ "$GITHUB_PROXY_PREFIX" =~ ^http:// ]]; then
            die "GitHub 代理前缀不允许使用 HTTP，请使用 HTTPS"
        fi

        if ! [[ "$GITHUB_PROXY_PREFIX" =~ ^https:// ]]; then
            die "GitHub 代理前缀必须以 https:// 开头"
        fi
    fi
}

# ==================== 备份函数 ====================

backup_file_once() {
    local file="$1"
    local name
    local backup_file

    [[ -f "$file" ]] || return 0

    mkdir -p "$BACKUP_DIR"

    name="$(basename "$file")"
    backup_file="${BACKUP_DIR}/${name}.bak.$(date '+%Y%m%d%H%M%S')"

    cp -a "$file" "$backup_file" || die "备份失败：$file -> $backup_file"
    log "已备份 $file 到 $backup_file"
}

backup_ssh_config_once() {
    mkdir -p "$BACKUP_DIR"

    if [[ ! -f "$BACKUP_FLAG_FILE" ]]; then
        [[ -f "$SSHD_CONFIG" ]] && backup_file_once "$SSHD_CONFIG"
        [[ -f "$SSHD_DROPIN_FILE" ]] && backup_file_once "$SSHD_DROPIN_FILE"
        echo "$(date '+%F %T')" > "$BACKUP_FLAG_FILE"
        log "SSH 配置首次备份完成"
    fi
}

# ==================== URL 工具函数 ====================

normalize_proxy_prefix() {
    local prefix="$1"

    [[ -z "$prefix" ]] && return 0

    if [[ "$prefix" != */ ]]; then
        prefix="${prefix}/"
    fi

    printf '%s' "$prefix"
}

# ==================== 构造公钥下载 URL ====================

build_key_urls() {
    local official_url
    local proxy_prefix

    if [[ -n "$github_user" ]]; then
        official_url="https://github.com/${github_user}.keys"

        if [[ -n "$GITHUB_PROXY_PREFIX" ]]; then
            proxy_prefix="$(normalize_proxy_prefix "$GITHUB_PROXY_PREFIX")"
            printf '%s\n' "${proxy_prefix}${official_url}"
        fi

        printf '%s\n' "$official_url"
    else
        printf '%s\n' "$key_url"
    fi
}

# ==================== 公钥校验 ====================

filter_valid_keys() {
    local input="$1"
    local output="$2"

    awk '
        /^[[:space:]]*$/ { next }
        /^#/ { next }
        $1 ~ /^(ssh-rsa|rsa-sha2-256|rsa-sha2-512|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)$/ {
            print
        }
    ' "$input" > "$output"

    [[ -s "$output" ]]
}

# ==================== 下载并安装公钥 ====================

install_authorized_keys() {
    local tmp_raw
    local tmp_keys
    local url
    local ok=0

    install -d -m 700 /root/.ssh

    tmp_raw="$(mktemp)"
    tmp_keys="$(mktemp)"

    log "开始获取 SSH 公钥"

    while read -r url; do
        [[ -z "$url" ]] && continue

        log "尝试下载公钥：$url"

        if curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$tmp_raw"; then
            if filter_valid_keys "$tmp_raw" "$tmp_keys"; then
                ok=1
                log "公钥下载并校验成功：$url"
                break
            else
                warn "下载内容中没有有效 SSH 公钥：$url"
            fi
        else
            warn "下载公钥失败：$url"
        fi
    done < <(build_key_urls)

    if [[ "$ok" -ne 1 ]]; then
        rm -f "$tmp_raw" "$tmp_keys"
        die "无法获取有效 SSH 公钥，已停止更新 authorized_keys"
    fi

    if [[ -f "$AUTHORIZED_KEYS" ]] && cmp -s "$tmp_keys" "$AUTHORIZED_KEYS"; then
        log "authorized_keys 无变化，无需更新"
        rm -f "$tmp_raw" "$tmp_keys"
        return 0
    fi

    if [[ -f "$AUTHORIZED_KEYS" ]]; then
        backup_file_once "$AUTHORIZED_KEYS"
    fi

    install -m 600 "$tmp_keys" "$AUTHORIZED_KEYS"
    rm -f "$tmp_raw" "$tmp_keys"

    AUTHORIZED_KEYS_CHANGED=1
    log "authorized_keys 更新完成：$AUTHORIZED_KEYS"
}

# ==================== 确保 sshd_config 包含 drop-in ====================

ensure_sshd_include() {
    [[ -f "$SSHD_CONFIG" ]] || die "找不到 SSH 主配置文件：$SSHD_CONFIG"

    mkdir -p "$SSHD_DROPIN_DIR"

    if grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG"; then
        log "sshd_config 已包含 sshd_config.d 配置目录"
        return 0
    fi

    backup_file_once "$SSHD_CONFIG"

    {
        echo ""
        echo "# Added by key-cn-2.sh"
        echo "Include /etc/ssh/sshd_config.d/*.conf"
    } >> "$SSHD_CONFIG"

    SSH_CONFIG_CHANGED=1
    log "已向 sshd_config 添加 Include /etc/ssh/sshd_config.d/*.conf"
}

# ==================== 判断是否跳过文件 ====================

should_skip_sshd_file() {
    local file="$1"

    [[ ! -f "$file" ]] && return 0

    [[ "$file" == "$SSHD_DROPIN_FILE" ]] && return 0

    [[ "$file" == *.bak ]] && return 0
    [[ "$file" == *.backup ]] && return 0
    [[ "$file" == *.old ]] && return 0
    [[ "$file" == *.orig ]] && return 0
    [[ "$file" == *.save ]] && return 0
    [[ "$file" == *~ ]] && return 0

    return 1
}

# ==================== 注释 SSH 冲突配置 ====================

disable_conflicting_sshd_options() {
    local file
    local changed
    local tmp_file

    log "开始检查 SSH 冲突配置"

    local keys=(
        "PermitRootLogin"
        "PubkeyAuthentication"
        "PasswordAuthentication"
        "KbdInteractiveAuthentication"
        "ChallengeResponseAuthentication"
    )

    if [[ -n "$ssh_port" ]]; then
        keys+=("Port")
    fi

    while IFS= read -r file; do
        should_skip_sshd_file "$file" && continue

        changed=0
        tmp_file="$(mktemp)"

        cp -a "$file" "$tmp_file"

        for key in "${keys[@]}"; do
            if grep -Eq "^[[:space:]]*${key}[[:space:]]+" "$tmp_file"; then
                sed -i -E "s|^([[:space:]]*)(${key}[[:space:]].*)|# Managed by key-cn-2.sh disabled conflict: \2|" "$tmp_file"
                changed=1
            fi
        done

        if [[ "$changed" -eq 1 ]]; then
            if ! cmp -s "$file" "$tmp_file"; then
                backup_file_once "$file"
                cat "$tmp_file" > "$file"
                SSH_CONFIG_CHANGED=1
                log "已注释 $file 中的 SSH 冲突配置"
            fi
        fi

        rm -f "$tmp_file"
    done < <(
        {
            echo "$SSHD_CONFIG"
            find "$SSHD_DROPIN_DIR" -maxdepth 1 -type f -name '*.conf' 2>/dev/null | sort
        } | awk '!seen[$0]++'
    )

    log "SSH 冲突配置检查完成"
}

# ==================== 写入 SSH drop-in 配置 ====================

write_sshd_dropin() {
    local tmp_conf
    tmp_conf="$(mktemp)"

    mkdir -p "$SSHD_DROPIN_DIR"

    {
        echo "# Managed by key-cn-2.sh"
        echo ""
        echo "PubkeyAuthentication yes"
        echo "PermitRootLogin prohibit-password"

        if [[ "$disable_password_login" -eq 1 ]]; then
            echo "PasswordAuthentication no"
            echo "KbdInteractiveAuthentication no"
            echo "ChallengeResponseAuthentication no"
        fi

        if [[ -n "$ssh_port" ]]; then
            echo "Port $ssh_port"
        fi
    } > "$tmp_conf"

    if [[ -f "$SSHD_DROPIN_FILE" ]] && cmp -s "$tmp_conf" "$SSHD_DROPIN_FILE"; then
        log "SSH drop-in 配置无变化：$SSHD_DROPIN_FILE"
        rm -f "$tmp_conf"
        return 0
    fi

    if [[ -f "$SSHD_DROPIN_FILE" ]]; then
        backup_file_once "$SSHD_DROPIN_FILE"
    fi

    install -m 600 "$tmp_conf" "$SSHD_DROPIN_FILE"
    rm -f "$tmp_conf"

    SSH_CONFIG_CHANGED=1
    log "SSH drop-in 配置已写入：$SSHD_DROPIN_FILE"
}

# ==================== SSH 配置校验 ====================

get_sshd_bin() {
    if command -v sshd >/dev/null 2>&1; then
        command -v sshd
    elif [[ -x /usr/sbin/sshd ]]; then
        echo "/usr/sbin/sshd"
    else
        return 1
    fi
}

test_sshd_config() {
    local sshd_bin

    sshd_bin="$(get_sshd_bin)" || die "找不到 sshd 命令"

    if "$sshd_bin" -t; then
        log "sshd 配置校验通过"
    else
        die "sshd 配置校验失败，请检查 $SSHD_CONFIG 和 $SSHD_DROPIN_FILE"
    fi
}

# ==================== 检测 SSH 服务名 ====================

detect_ssh_service() {
    if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
        echo "ssh"
        return 0
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
        echo "sshd"
        return 0
    fi

    if systemctl status ssh >/dev/null 2>&1; then
        echo "ssh"
        return 0
    fi

    if systemctl status sshd >/dev/null 2>&1; then
        echo "sshd"
        return 0
    fi

    echo "ssh"
}

# ==================== 重载 SSH 服务 ====================

reload_ssh_service() {
    local service
    service="$(detect_ssh_service)"

    log "准备重载 SSH 服务：$service"

    if systemctl reload "$service" >/dev/null 2>&1; then
        log "SSH 服务 reload 完成：$service"
        return 0
    fi

    warn "SSH 服务 reload 失败，尝试 restart：$service"

    if systemctl restart "$service" >/dev/null 2>&1; then
        log "SSH 服务 restart 完成：$service"
        return 0
    fi

    die "SSH 服务 reload/restart 失败：$service"
}

# ==================== 显示最终生效 SSH 配置 ====================

log_effective_sshd_config() {
    local sshd_bin

    sshd_bin="$(get_sshd_bin)" || return 0

    log "当前 sshd 最终生效关键配置如下："
    "$sshd_bin" -T 2>/dev/null \
        | grep -Ei '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|pubkeyauthentication)\b' \
        | while read -r line; do
            log "  $line"
        done
}

# ==================== 应用 SSH 配置 ====================

apply_ssh_config() {
    backup_ssh_config_once
    ensure_sshd_include
    disable_conflicting_sshd_options
    write_sshd_dropin

    if [[ "$SSH_CONFIG_CHANGED" -eq 1 ]]; then
        test_sshd_config
        reload_ssh_service
    else
        log "SSH 配置无变化，不重载 SSH 服务"
    fi

    log_effective_sshd_config
}

# ==================== cron 管理 ====================

install_or_update_cron() {
    local cron_begin="# BEGIN key-cn-2"
    local cron_end="# END key-cn-2"
    local cron_cmd
    local cron_expression
    local monthly_expression
    local tmp_cron

    cron_cmd="/bin/bash $SCRIPT_PATH"

    if [[ -n "$github_user" ]]; then
        cron_cmd+=" -g $(printf '%q' "$github_user")"
    fi

    if [[ -n "$key_url" ]]; then
        cron_cmd+=" -u $(printf '%q' "$key_url")"
    fi

    cron_cmd+=" -m $interval -o"

    if [[ "$disable_password_login" -eq 1 ]]; then
        cron_cmd+=" -d"
    fi

    if [[ -n "$ssh_port" ]]; then
        cron_cmd+=" -p $ssh_port"
    fi

    if [[ -n "$GITHUB_PROXY_PREFIX" ]]; then
        cron_cmd+=" -P $(printf '%q' "$GITHUB_PROXY_PREFIX")"
    fi

    cron_expression="*/$interval * * * * $cron_cmd >> $LOG_FILE 2>&1"
    monthly_expression="@monthly truncate -s 0 $LOG_FILE"

    if (( 60 % interval != 0 )); then
        warn "分钟间隔 $interval 不能整除 60，cron 表达式 */$interval 可能不是严格每 $interval 分钟执行一次"
    fi

    tmp_cron="$(mktemp)"

    crontab -l 2>/dev/null \
        | sed "/^${cron_begin}$/,/^${cron_end}$/d" \
        | grep -vE 'key-cn-2\.sh|key-cn-2\.log' \
        > "$tmp_cron" || true

    {
        echo "$cron_begin"
        echo "$cron_expression"
        echo "$monthly_expression"
        echo "$cron_end"
    } >> "$tmp_cron"

    crontab "$tmp_cron"
    rm -f "$tmp_cron"

    log "已安装或更新 cron 定时任务：每 $interval 分钟执行一次"
}

# ==================== 日志清理 ====================

trim_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local tmp_log
        tmp_log="$(mktemp)"
        tail -n 1000 "$LOG_FILE" > "$tmp_log" && cat "$tmp_log" > "$LOG_FILE"
        rm -f "$tmp_log"
    fi
}

# ==================== 显示当前参数 ====================

show_summary() {
    log "========== key-cn-2 执行开始 =========="
    [[ -n "$github_user" ]] && log "GitHub 用户名：$github_user"
    [[ -n "$key_url" ]] && log "公钥链接：$key_url"
    [[ -n "$GITHUB_PROXY_PREFIX" ]] && log "GitHub 代理前缀：$GITHUB_PROXY_PREFIX"
    log "自动更新间隔：$interval 分钟"
    log "设置 cron：$([[ "$setup_cron" -eq 1 ]] && echo 是 || echo 否)"
    log "禁用密码登录：$([[ "$disable_password_login" -eq 1 ]] && echo 是 || echo 否)"
    [[ -n "$ssh_port" ]] && log "SSH 端口：$ssh_port"
    log "脚本路径：$SCRIPT_PATH"
}

# ==================== 主流程 ====================

main() {
    ensure_log_file
    acquire_lock
    check_root
    parse_args "$@"
    view_log_if_needed
    validate_args
    check_dependencies

    show_summary

    install_authorized_keys
    apply_ssh_config

    if [[ "$setup_cron" -eq 1 ]]; then
        install_or_update_cron
    fi

    if [[ "$AUTHORIZED_KEYS_CHANGED" -eq 1 && "$SSH_CONFIG_CHANGED" -eq 0 ]]; then
        log "authorized_keys 已更新，但 SSH 配置无变化，不需要重载 SSH 服务"
    fi

    trim_log
    log "========== key-cn-2 执行完成 =========="
}

main "$@"
