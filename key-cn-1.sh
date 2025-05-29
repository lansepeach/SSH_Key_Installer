#!/usr/bin/env bash
#=============================================================
# https://github.com/P3TERX/SSH_Key_Installer
# Description: Install SSH keys via GitHub, URL or local files.
#              Added hourly auto-update feature.
# Version: 2.8.1 (Patched)
# Author: P3TERX
# Blog: https://p3terx.com
# Modifier: Gemini
#=============================================================

VERSION=2.8.1 # Updated version to reflect patch
RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
YELLOW_FONT_PREFIX="\033[1;33m" # Added yellow for warnings
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${LIGHT_GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
WARN="[${YELLOW_FONT_PREFIX}WARN${FONT_COLOR_SUFFIX}]" # Added WARN variable

[ $EUID != 0 ] && SUDO=sudo

AUTO_UPDATE_HOURLY=0
CURRENT_KEY_SOURCE_FLAG=""
CURRENT_KEY_SOURCE_ARG=""

USAGE() { # Renamed from 使用说明 and updated
    echo "
SSH 密钥安装程序 ${VERSION}

用法:
  bash <(curl -sSL https://gitee.com/lansepeach/SSH_Key_Installer/raw/master/key-cn.sh) [选项...] <参数>

选项:
  -A	自动设置每小时更新密钥的 cron 作业 (与 -g, -u, 或 -f 结合使用)
  -o	覆盖模式，此选项在顶部有效
  -g	从 GitHub 获取公钥，参数是 GitHub ID
  -u	从 URL 获取公钥，参数是 URL
  -f	从本地文件获取公钥，参数是本地文件路径
  -p	更改 SSH 端口，参数是端口号
  -d	禁用密码登录"
}

if [ $# -eq 0 ]; then
    USAGE # Call USAGE
    exit 1
fi

get_github_key() {
    if [ "${KEY_ID}" == '' ]; then
        read -e -p "Please enter the GitHub account:" KEY_ID
        [ "${KEY_ID}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} GitHub 帐号为: ${KEY_ID}"
    echo -e "${INFO} 从 GitHub 获取密钥..."
    PUB_KEY=$(curl -fsSL https://git666.463791874.xyz/proxy/https://github.com/${KEY_ID}.keys)
    if [ "${PUB_KEY}" == 'Not Found' ]; then
        echo -e "${ERROR} 未找到 GitHub 帐户。"
        exit 1
    elif [ "${PUB_KEY}" == '' ]; then
        echo -e "${ERROR} 该帐户 ssh 密钥不存在。"
        exit 1
    fi
}

get_url_key() {
    if [ "${KEY_URL}" == '' ]; then
        read -e -p "Please enter the URL:" KEY_URL
        [ "${KEY_URL}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} 从 URL 获取密钥..."
    PUB_KEY=$(curl -fsSL ${KEY_URL})
}

get_local_key() { # Renamed from get_loacl_key
    if [ "${KEY_PATH}" == '' ]; then
        read -e -p "Please enter the path:" KEY_PATH
        [ "${KEY_PATH}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} 获取本地文件密钥 ${KEY_PATH}..." # Corrected message
    PUB_KEY=$(cat "${KEY_PATH}") # Added quotes around KEY_PATH
}

install_key() {
    [ "${PUB_KEY}" == '' ] && echo -e "${ERROR} ssh 密钥不存在。" && exit 1
    if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
        echo -e "${INFO} '${HOME}/.ssh/authorized_keys' 不见了..."
        echo -e "${INFO} 正在创建  ${HOME}/.ssh/authorized_keys..."
        mkdir -p "${HOME}/.ssh/"
        touch "${HOME}/.ssh/authorized_keys"
        if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
            echo -e "${ERROR} 无法创建 SSH 密钥文件。"
            exit 1 # Exit if creation fails
        else
            echo -e "${INFO} 密钥文件已创建，正在处理..."
        fi
    fi
    if [ "${OVERWRITE}" == 1 ]; then
        echo -e "${INFO} 正在覆盖 SSH 密钥..."
        echo -e "${PUB_KEY}\n" >"${HOME}/.ssh/authorized_keys"
    else
        echo -e "${INFO} 添加 SSH 密钥..."
        echo -e "\n${PUB_KEY}\n" >>"${HOME}/.ssh/authorized_keys"
    fi
    chmod 700 "${HOME}/.ssh/"
    chmod 600 "${HOME}/.ssh/authorized_keys"
    # Ensure the key is actually in the file before declaring success
    if grep -qF -- "${PUB_KEY}" "${HOME}/.ssh/authorized_keys"; then
        echo -e "${INFO} SSH 密钥安装成功!"
    else
        echo -e "${ERROR} SSH 密钥安装失败!"
        exit 1
    fi # CORRECTED: Was '}' before
}

setup_hourly_update() {
    if [ -z "${CURRENT_KEY_SOURCE_FLAG}" ] || [ -z "${CURRENT_KEY_SOURCE_ARG}" ]; then
        echo -e "${ERROR} 无法设置每小时更新：密钥源信息丢失。"
        return 1
    fi

    local SCRIPT_PATH_FOR_CRON
    if command -v realpath >/dev/null 2>&1; then
        SCRIPT_PATH_FOR_CRON=$(realpath "$0")
    else
        echo -e "${WARN} 'realpath' 命令未找到。无法可靠地确定 cron 作业的脚本路径。"
        echo -e "${WARN} 如果脚本不是通过绝对路径执行的，cron 作业可能失败。"
        echo -e "${WARN} 请考虑安装 'realpath' (通常在 coreutils 包中) 或手动验证 cron 作业中的脚本路径。"
        # Fallback: use $0 as is, hoping it's absolute or cron's context allows it.
        SCRIPT_PATH_FOR_CRON="$0"
    fi

    # The cron job will run the script with -o (overwrite) and the original key source.
    # If the script needs sudo for internal operations (like sed /etc/ssh/sshd_config),
    # it already has $SUDO logic. The cron job will run as the user who owns the crontab.
    # If this script was run with sudo (e.g. sudo ./script.sh -A -g user),
    # then crontab - will edit root's crontab, and the job runs as root.
    local CRON_CMD_TO_RUN="${SCRIPT_PATH_FOR_CRON} -o -${CURRENT_KEY_SOURCE_FLAG} '${CURRENT_KEY_SOURCE_ARG}'"
    local CRON_JOB_LINE="0 * * * * ${CRON_CMD_TO_RUN}"
    # Using a more unique comment to avoid collision and for easier identification
    local CRON_COMMENT="# Hourly SSH Key Update: ${CURRENT_KEY_SOURCE_FLAG} ${CURRENT_KEY_SOURCE_ARG} (Managed by ${SCRIPT_PATH_FOR_CRON})"

    echo -e "${INFO} 正在设置每小时密钥更新的 cron 作业..."
    
    # Check if cron job with this specific comment already exists
    if (crontab -l 2>/dev/null | grep -Fq -- "${CRON_COMMENT}"); then
        echo -e "${INFO} 具有相同注释的 cron 作业已存在。跳过添加。"
        echo -e "${INFO} 如需修改，请手动编辑您的 crontab (使用 'crontab -e' 命令)。"
    else
        # Add new cron job
        (crontab -l 2>/dev/null; echo "${CRON_COMMENT}"; echo "${CRON_JOB_LINE}") | crontab -
        if [ $? -eq 0 ]; then
            echo -e "${INFO} 每小时密钥更新 cron 作业设置成功。"
            echo -e "${INFO} 命令: ${CRON_JOB_LINE}"
            echo -e "${INFO} 它将作为用户 $(whoami) 每小时的第0分钟运行。"
        else
            echo -e "${ERROR} 设置 cron 作业失败。您可能需要手动设置。"
        fi
    fi
}


change_port() {
    echo -e "${INFO} 将 SSH 端口更改为 ${SSH_PORT} ..."
    if [ "$(uname -o)" == Android ]; then # Use $(uname -o) for consistency with original script
        [[ -z $(grep "Port " "$PREFIX/etc/ssh/sshd_config") ]] &&
            echo -e "${INFO} Port ${SSH_PORT}" >>"$PREFIX/etc/ssh/sshd_config" ||
            sed -i "s@.*\(Port \).*@\1${SSH_PORT}@" "$PREFIX/etc/ssh/sshd_config"
        [[ $(grep "Port ${SSH_PORT}" "$PREFIX/etc/ssh/sshd_config") ]] && { # Check for specific port
            echo -e "${INFO} SSH端口更改成功!"
            RESTART_SSHD=2
        } || {
            RESTART_SSHD=0 # Should be 0 if failed
            echo -e "${ERROR} SSH port change failed!"
            exit 1
        }
    else
        $SUDO sed -i "s@^#\?Port .*@Port ${SSH_PORT}@" /etc/ssh/sshd_config && { # Improved sed to handle commented Port
            echo -e "${INFO} SSH端口更改成功！"
            RESTART_SSHD=1
        } || {
            RESTART_SSHD=0 # Should be 0 if failed
            echo -e "${ERROR} SSH 端口更改失败！"
            exit 1
        }
    fi
}

disable_password() {
    if [ "$(uname -o)" == Android ]; then # Use $(uname -o)
        sed -i "s@.*\(PasswordAuthentication \).*@\1no@" "$PREFIX/etc/ssh/sshd_config" && {
            RESTART_SSHD=2
            echo -e "${INFO} 禁用 SSH 中的密码登录。"
        } || {
            RESTART_SSHD=0 # Should be 0 if failed
            echo -e "${ERROR} 禁用密码登录失败！"
            exit 1
        }
    else
        # Ensure PasswordAuthentication line exists or add it, then set to no
        if grep -q "^#\?PasswordAuthentication" /etc/ssh/sshd_config; then
            $SUDO sed -i "s@^#\?PasswordAuthentication .*@PasswordAuthentication no@" /etc/ssh/sshd_config
        else
            echo "PasswordAuthentication no" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
        fi
        
        if grep -q "^PasswordAuthentication no$" /etc/ssh/sshd_config; then
            RESTART_SSHD=1
            echo -e "${INFO} 禁用 SSH 中的密码登录。"
        else
            RESTART_SSHD=0 # Should be 0 if failed
            echo -e "${ERROR} 禁用密码登录失败!"
            exit 1
        }
    fi
}

while getopts "Aog:u:f:p:d" OPT; do # Added A
    case $OPT in
    A)
        AUTO_UPDATE_HOURLY=1
        ;;
    o)
        OVERWRITE=1
        ;;
    g)
        KEY_ID=$OPTARG
        CURRENT_KEY_SOURCE_FLAG="g"
        CURRENT_KEY_SOURCE_ARG="${KEY_ID}"
        get_github_key
        install_key && {
            if [ "${AUTO_UPDATE_HOURLY}" = 1 ]; then
                setup_hourly_update
            fi
        }
        ;;
    u)
        KEY_URL=$OPTARG
        CURRENT_KEY_SOURCE_FLAG="u"
        CURRENT_KEY_SOURCE_ARG="${KEY_URL}" # URLs can be long, ensure quoting in cron is fine
        get_url_key
        install_key && {
            if [ "${AUTO_UPDATE_HOURLY}" = 1 ]; then
                setup_hourly_update
            fi
        }
        ;;
    f)
        KEY_PATH_ORIG=$OPTARG # Original path as provided by user
        CURRENT_KEY_SOURCE_FLAG="f"
        
        # For cron, try to use an absolute path for the key file
        if command -v realpath >/dev/null 2>&1; then
             CURRENT_KEY_SOURCE_ARG=$(realpath "${KEY_PATH_ORIG}")
        else
            CURRENT_KEY_SOURCE_ARG="${KEY_PATH_ORIG}"
            # Warning about realpath not found will be given in setup_hourly_update if needed for SCRIPT_PATH
            # Here, we just inform if using non-absolute path for key file in cron
            if [[ ! "$KEY_PATH_ORIG" = /* && "${AUTO_UPDATE_HOURLY}" = 1 ]]; then
                 echo -e "${WARN} 'realpath' 命令未找到，且提供的密钥文件路径 '${KEY_PATH_ORIG}' 不是绝对路径。"
                 echo -e "${WARN} cron 作业可能无法找到此文件，除非其工作目录正确或路径对 cron 环境有效。"
            fi
        fi
        
        KEY_PATH="${KEY_PATH_ORIG}" # get_local_key uses this
        get_local_key # Call renamed function
        install_key && {
            if [ "${AUTO_UPDATE_HOURLY}" = 1 ]; then
                # setup_hourly_update uses CURRENT_KEY_SOURCE_ARG (potentially absolute path)
                setup_hourly_update
            fi
        }
        ;;
    p)
        SSH_PORT=$OPTARG
        change_port
        ;;
    d)
        disable_password
        ;;
    ?)
        USAGE # Call USAGE
        exit 1
        ;;
    :) # Handle missing option arguments
        echo -e "${ERROR} 选项 -${OPTARG} 需要一个参数。"
        USAGE
        exit 1
        ;;
    *) # Should not happen with getopts
        USAGE
        exit 1
        ;;
    esac
done

# Shift processed options away if you need to access further non-option arguments
# shift "$((OPTIND -1))"

if [ "$RESTART_SSHD" = 1 ]; then
    echo -e "${INFO} 正在重新启动 sshd..."
    $SUDO systemctl restart sshd && echo -e "${INFO} 成功。" || echo -e "${ERROR} 重启 sshd 失败。"
elif [ "$RESTART_SSHD" = 2 ]; then
    echo -e "${INFO} 重新启动 sshd 或 Termux App 以生效."
fi
