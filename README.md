# Key CN SSH 公钥自动更新脚本

[![License: MIT](https://img.shields.io/github/license/P3TERX/SSH_Key_Installer?style=flat-square)](LICENSE)
[![Stars](https://img.shields.io/github/stars/yourname/key-cn-ssh-installer?style=flat-square)](https://github.com/yourname/key-cn-ssh-installer/stargazers)
[![Forks](https://img.shields.io/github/forks/yourname/key-cn-ssh-installer?style=flat-square)](https://github.com/yourname/key-cn-ssh-installer/fork)

> 通过 GitHub 用户名或 HTTPS 链接自动安装 SSH 公钥，并可选开启定时自动更新、修改端口、禁用密码登录。

## 📖 教程（中文）

详见：[博客链接或文档链接](https://example.com/your-blog-post)

---

## 🧰 功能

* 从 GitHub 或 HTTPS 链接下载并安装 SSH 公钥
* 支持自动设置 SSH 端口和禁用密码登录
* 支持设定定时任务自动更新公钥
* 支持交互模式和命令行参数两种方式
* 自动记录操作日志并保留最近1000行

---

## 🚀 使用方法

### 一键安装命令

```bash
bash <(curl -fsSL https://yourdomain.com/key-cn-2.sh) [选项...]
```

---

## 🛠️ 命令行选项

| 参数                 | 描述                           |
| ------------------ | ---------------------------- |
| `-g <GitHub 用户名>`  | 从 GitHub 用户名获取公钥（与 `-u` 二选一） |
| `-u <公钥 HTTPS 链接>` | 从 HTTPS 链接获取公钥（与 `-g` 二选一）   |
| `-o`               | 启用自动定时任务（与 `-m` 一起使用）        |
| `-m <分钟数>`         | 定时任务执行间隔（默认：5分钟）             |
| `-p <端口号>`         | 设置新的 SSH 端口号                 |
| `-d`               | 禁用 SSH 密码登录（启用密钥登录）          |
| `-v`               | 查看自动更新日志                     |
| `-h`               | 显示帮助信息                       |

---

## 🧪 示例用法

```bash
# 从 GitHub 安装并每 5 分钟更新
bash key-cn-2.sh -g username -m 5 -o

# 从 HTTPS 链接安装，改 SSH 端口为 2222 并禁用密码登录
bash key-cn-2.sh -u https://yourdomain.com/id.pub -p 2222 -d
```

---

## 🔐 安全性说明

* 只支持 `HTTPS` 下载公钥，不允许使用 `HTTP`；
* 脚本必须以 `root` 身份运行；
* 自动备份原始 SSH 配置文件。

---

## 📝 日志说明

日志路径为 `/var/log/key-cn-2.log`，脚本每次执行都会记录时间和操作。最多保留 1000 行。

---

## 📄 License

本项目使用 [MIT License](LICENSE)
