
# Key CN SSH 公钥自动更新脚本（AI 重构增强版）

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Stars](https://img.shields.io/github/stars/lansepeach/SSH_Key_Installer?style=flat-square)](https://github.com/lansepeach/SSH_Key_Installer/stargazers)
[![Forks](https://img.shields.io/github/forks/lansepeach/SSH_Key_Installer?style=flat-square)](https://github.com/lansepeach/SSH_Key_Installer/fork)

> 通过 GitHub 用户名或 HTTPS 链接自动安装 SSH 公钥，并可选开启定时自动更新、修改 SSH 端口、禁用密码登录、自动清理冲突 SSH 配置。

---

## 📖 教程

详见：[博客或文档链接](https://example.com/your-blog-post)

---

## 🧰 功能

- 从 GitHub 用户名下载并安装 SSH 公钥
- 从自定义 HTTPS 链接下载并安装 SSH 公钥
- 自动校验下载内容是否为有效 SSH 公钥
- 安全更新 `/root/.ssh/authorized_keys`
- 自动备份旧的 SSH key 和 SSH 配置文件
- 自动启用 SSH 公钥登录
- 自动设置 `PermitRootLogin prohibit-password`
- 可选禁用 SSH 密码登录
- 可选修改 SSH 端口
- 使用 `/etc/ssh/sshd_config.d/00-key-cn.conf` 管理 SSH 配置
- 自动注释其他配置文件中的冲突 SSH 项
- 修改 SSH 配置后自动执行 `sshd -t` 校验
- 仅当 SSH 配置发生变化时才 reload/restart SSH 服务
- 如果只是更新 `authorized_keys`，不会重载 SSH 服务
- 支持自动创建或更新 cron 定时任务
- 防止重复添加 cron 任务
- 自动记录日志并保留最近 1000 行
- 使用锁文件防止并发运行
- 兼容 Debian 11/12/13 和 Ubuntu 20.04/22.04/24.04+

---

## 💻 支持系统

推荐用于基于 systemd 的 Debian / Ubuntu 系统：

- Debian 11+
- Debian 12+
- Debian 13+
- Ubuntu 20.04+
- Ubuntu 22.04+
- Ubuntu 24.04+

---

## 📦 依赖

脚本需要以 `root` 身份运行。

需要以下组件：

- `curl`
- `openssh-server`
- `systemd`
- `util-linux`

Debian / Ubuntu 可使用以下命令安装依赖：

```bash
apt update
apt install -y curl openssh-server util-linux
```

---

## 🚀 使用方法

### 一键下载脚本

推荐下载到 `/root/key-cn-2.sh`，这样 cron 可以使用绝对路径，稳定性更好。

```bash
curl -fsSL https://raw.githubusercontent.com/lansepeach/SSH_Key_Installer/refs/heads/master/key-cn-2.sh -o /root/key-cn-2.sh && chmod +x /root/key-cn-2.sh
```

如果你使用自己的镜像或代理地址，可以替换为自己的下载链接：

```bash
curl -fsSL https://your-domain.example/path/to/key-cn-2.sh -o /root/key-cn-2.sh && chmod +x /root/key-cn-2.sh
```

---

## 🛠️ 命令行选项

| 参数 | 描述 |
|---|---|
| `-g <GitHub 用户名>` | 从 GitHub 用户名获取公钥，与 `-u` 二选一 |
| `-u <公钥 HTTPS 链接>` | 从 HTTPS 链接获取公钥，与 `-g` 二选一 |
| `-o` | 启用或更新自动定时任务 |
| `-m <分钟数>` | 定时任务执行间隔，默认 `10` 分钟 |
| `-p <端口号>` | 设置新的 SSH 端口号 |
| `-d` | 禁用 SSH 密码登录 |
| `-v` | 查看自动更新日志 |
| `-h` | 显示帮助信息 |

说明：

- `-g` 和 `-u` 不能同时使用
- 使用 `-o` 后会创建或更新 cron 定时任务
- 使用 `-d` 后会禁用 SSH 密码登录
- 使用 `-p` 后会修改 SSH 端口，并清理其他位置的冲突端口配置

---

## 🧪 示例用法

### 从 GitHub 安装公钥

```bash
bash /root/key-cn-2.sh -g your_github_username
```

---

### 从 HTTPS 链接安装公钥

```bash
bash /root/key-cn-2.sh -u https://example.com/authorized_keys
```

---

### 从 GitHub 安装并每 10 分钟自动更新

```bash
bash /root/key-cn-2.sh -g your_github_username -m 10 -o
```

---

### 修改 SSH 端口并禁用密码登录

```bash
bash /root/key-cn-2.sh -g your_github_username -p 2222 -d
```

---

### 推荐示例

```bash
curl -fsSL https://raw.githubusercontent.com/lansepeach/SSH_Key_Installer/refs/heads/master/key-cn-2.sh -o /root/key-cn-2.sh && chmod +x /root/key-cn-2.sh && bash /root/key-cn-2.sh -g 'your_github_username' -m 10 -o -d -p 2222
```

该命令会：

- 下载脚本到 `/root/key-cn-2.sh`
- 赋予执行权限
- 从 GitHub 用户获取 SSH 公钥
- 安装到 `/root/.ssh/authorized_keys`
- 每 10 分钟自动更新一次公钥
- 禁用 SSH 密码登录
- 设置 root 仅允许密钥登录
- 修改 SSH 端口为 `2222`

---

## 🔐 安全性说明

- 脚本必须以 `root` 身份运行
- 只支持 `HTTPS` 公钥链接，不允许使用 `HTTP`
- 下载到的内容会先经过 SSH 公钥格式校验
- 更新 `authorized_keys` 前会自动备份旧文件
- 修改 SSH 配置前会自动备份相关配置文件
- 修改 SSH 配置后会先执行 `sshd -t` 校验
- 只有 SSH 配置发生变化时才会 reload/restart SSH 服务
- 如果只是更新 `/root/.ssh/authorized_keys`，不会 reload/restart SSH 服务
- 使用 `-d` 后会禁用 SSH 密码登录
- 使用 `-p` 后会修改 SSH 端口，并自动注释其他位置的冲突 `Port` 配置
- 脚本会自动注释其他配置文件中的冲突 SSH 安全项，例如：
  - `PermitRootLogin`
  - `PasswordAuthentication`
  - `KbdInteractiveAuthentication`
  - `ChallengeResponseAuthentication`
  - `PubkeyAuthentication`
  - `Port`

---

## ⚠️ 重要提醒

如果你使用了：

```bash
-d -p 2222
```

表示：

- 禁用 SSH 密码登录
- 修改 SSH 端口为 `2222`

请务必：

1. 不要立即关闭当前 SSH 窗口
2. 新开一个终端测试密钥登录
3. 确认可以成功登录后，再关闭旧连接

测试命令：

```bash
ssh -p 2222 root@your_server_ip
```

---

## 🧩 SSH 配置说明

脚本会创建并维护：

```bash
/etc/ssh/sshd_config.d/00-key-cn.conf
```

示例内容：

```conf
# Managed by key-cn-2.sh
# Generated at 2026-01-01 00:00:00

PubkeyAuthentication yes
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
Port 2222
```

同时脚本会检查并注释其他文件中的冲突配置，例如：

```conf
PermitRootLogin yes
PasswordAuthentication yes
Port 22
```

会被注释为：

```conf
# Managed by key-cn-2.sh disabled conflict: PermitRootLogin yes
# Managed by key-cn-2.sh disabled conflict: PasswordAuthentication yes
# Managed by key-cn-2.sh disabled conflict: Port 22
```

---

## ⏰ 定时任务

使用 `-o` 后，脚本会创建或更新自己的 cron 区块：

```cron
# BEGIN key-cn-2
*/10 * * * * /bin/bash /root/key-cn-2.sh -g your_github_username -m 10 -o -d -p 2222 >> /var/log/key-cn-2.log 2>&1
@monthly truncate -s 0 /var/log/key-cn-2.log
# END key-cn-2
```

以后再次运行脚本时，会自动替换该区块，不会重复添加。

---

## 📝 日志说明

默认日志路径：

```bash
/var/log/key-cn-2.log
```

查看日志：

```bash
bash /root/key-cn-2.sh -v
```

或者：

```bash
tail -n 100 /var/log/key-cn-2.log
```

脚本会保留最近 1000 行日志，并创建每月清空日志的 cron 任务。

---

## 📦 备份说明

SSH 相关备份文件默认存放在：

```bash
/etc/ssh/key-cn-backups/
```

查看备份：

```bash
ls -lh /etc/ssh/key-cn-backups/
```

---

## ✅ 验证配置

### 查看最终生效的 SSH 配置

```bash
sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|pubkeyauthentication)\b'
```

示例输出：

```text
port 2222
permitrootlogin without-password
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
```

说明：

- `without-password` 和 `prohibit-password` 在 OpenSSH 输出中基本等价
- 都表示 root 允许使用密钥登录，但不允许密码登录

---

### 查看 SSH 监听端口

```bash
ss -lntp | grep ssh
```

示例：

```text
LISTEN 0 128 0.0.0.0:2222 0.0.0.0:* users:(("sshd",pid=1234,fd=6))
```

---

## ♻️ 卸载

### 删除 cron 任务

```bash
crontab -l | sed '/^# BEGIN key-cn-2$/,/^# END key-cn-2$/d' | crontab -
```

### 删除脚本管理的 SSH 配置

```bash
rm -f /etc/ssh/sshd_config.d/00-key-cn.conf
```

### 检查并重载 SSH

Debian / Ubuntu 通常使用：

```bash
sshd -t && systemctl reload ssh
```

如果你的系统使用 `sshd` 服务名：

```bash
sshd -t && systemctl reload sshd
```

---

## 🧯 恢复备份

查看备份文件：

```bash
ls -lh /etc/ssh/key-cn-backups/
```

根据需要手动恢复对应文件。

---

## 📄 License

本项目使用 [MIT License](LICENSE)。
```
