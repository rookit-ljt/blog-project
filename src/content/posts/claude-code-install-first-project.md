---
author: 李金涛
pubDatetime: 2026-08-25T10:00:00+08:00
title: 第一次用 Claude Code，我用一个小项目确认它真的能工作
slug: claude-code-install-first-project
featured: false
draft: false
tags: [Claude Code, 前端, CLI, Agent]
description: 按官方方式安装 Claude Code，并在一个真实前端项目中完成首次分析任务。
timezone: Asia/Shanghai
---

安装一个能在终端执行命令、修改文件的 AI Agent，最容易让人心里打鼓：**它会不会在后台误删文件？环境变量和网络代理怎么配？第一次启动该如何验证它真的就绪了？**

很多人首次使用失败，往往不是模型推理能力的问题，而是卡在 Node 版本、PATH 环境变量、OAuth 登录重定向或企业内网代理上。

这篇文章记录一份现代前端工程下的完整安装、配置与首次验真清单。

---

## 跨平台安装矩阵

Claude Code 要求宿主环境具备 Node.js（推荐 `>= 22.12.0`）及 Git。请根据你的操作系统选择最干净的安装路径：

### 1. macOS & Linux（原生安装或 Homebrew）

官方推荐通过原生脚本安装，自动配置独立二进制与更新通道：

```bash
# 方式 A：官方 Native 脚本（推荐）
curl -fsSL https://claude.ai/install.sh | bash

# 方式 B：Homebrew 安装
brew install anthropics/claude/claude-code
```

安装完成后，若终端提示 `command not found: claude`，通常是因为安装目录未写入 `PATH`。请将以下配置追加至 `~/.zshrc` 或 `~/.bashrc`：

```bash
export PATH="$HOME/.local/bin:$PATH"
source ~/.zshrc
```

### 2. Windows（PowerShell 或 WSL2）

在 Windows 上，强烈推荐在 **WSL2 (Ubuntu)** 中运行，体验与 Linux 一致。如果必须在原生 Windows 下运行：

```powershell
# 以当前用户权限放行脚本执行策略
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# 执行官方 PowerShell 安装脚本
irm https://claude.ai/install.ps1 | iex
```

> [!WARNING]
> Windows CMD 用户请勿直接复制 PowerShell 的 `irm` 命令；若在 CMD 下使用，请使用 `curl.exe` 或优先使用 WSL2 终端。

---

## 认证授权与企业代理配置

首次在终端输入 `claude` 时，CLI 会引导你完成身份认证。这里分为两种使用场景：

### 场景 A：Claude Pro / Max / Team 个人订阅

直接回车打开浏览器完成 OAuth 授权，凭据会自动加密存储在系统 Keychain 或本地 `~/.claude/` 目录下。

### 场景 B：API Key 与企业中继代理

若团队使用 Anthropic Console API 或企业内网中转，可以在终端直接导出环境变量：

```bash
# 配置 API 密钥
export ANTHROPIC_API_KEY="sk-ant-api03-xxxx"

# 若使用企业自建中继网关
export ANTHROPIC_BASE_URL="https://api.your-company.com/v1"

# 若处于严格的企业网络代理后
export HTTP_PROXY="http://127.0.0.1:7890"
export HTTPS_PROXY="http://127.0.0.1:7890"
# 若遇到自签名企业证书拦截
export NODE_EXTRA_CA_CERTS="/path/to/enterprise-ca.pem"
```

---

## 首次项目安全信任与权限配置

进入你的前端项目根目录（例如本项目 `blog-project`）：

```bash
cd /Users/jt-lee/Desktop/blog-project
claude
```

首次进入项目时，Claude Code 会弹出安全提示：

```text
Trust this repository?
Allowing Claude Code in /Users/jt-lee/Desktop/blog-project gives it access to
read and write files, and run commands in this directory.
[y] Yes, trust this folder
[n] No, exit
```

按下 `y` 确认信任。此时会在当前项目初始化上下文缓存。

为了防止 Agent 执行非预期的破坏性命令，Claude Code 默认处于**授权确认模式（Ask before executing）**：

- **读取文件 / 检索代码**：静默自动执行
- **修改文件（Unified Diff）**：在屏幕展示高亮 Diff，等待人工按键确认
- **执行终端命令（如 `rm`、`npm install`、`git push`）**：明确展示将要执行的完整命令，等待人工授权

---

## 首次实操验真：三步确认法

刚安装好不要急着让它“写个大功能”。用这三步验证它的感知、执行与回滚能力：

### 第一步：只读健康检查（验感知）

在会话中输入：

```text
只做只读检查：
1. 确认这是哪一种前端框架与包管理器？
2. 找到本项目的开发、构建和静态检查命令。
3. 列出 src/ 目录下的主要子模块及其职责。
暂时不要修改任何文件。
```

**验收指标**：观察终端输出是否精准识别出 `astro`、`pnpm` 以及各模块路径。如果它能列出真实存在的文件名而不是臆想的组件，说明文件系统与检索索引工作正常。

### 第二步：受控微小修改（验执行与检查）

要求它修改一个无害的非核心文件，例如给 `README.md` 底部增加一行贡献说明：

```text
请在 README.md 底部增加“## 贡献指南”简要章节。
修改后运行 pnpm format:check 检查格式，并展示修改的 diff。
```

**验收指标**：

1. 终端弹出文件修改预览，清晰标出绿色新增行；
2. 确认后文件成功落盘；
3. 自动执行格式化命令并输出通过状态。

### 第三步：主动回滚测试（验安全）

确认它的改动可以被无损撤销：

```bash
# 退出或在新终端中执行
git diff README.md
git checkout -- README.md
```

通过这一套完整的“只读排查 ➔ 受控变更 ➔ 格式检查 ➔ 干净回滚”，你就能建立起对终端 Agent 的基础确定性。

---

## 常见问题与排错手册

| 报错现象                            | 根本原因                            | 解决方案                                                   |
| :---------------------------------- | :---------------------------------- | :--------------------------------------------------------- |
| `EPERM: operation not permitted`    | 沙箱文件权限或系统权限受限          | 检查是否在受保护目录运行；确认当前用户对工程目录有读写权限 |
| `FetchError: request to ... failed` | 网络代理或 DNS 解析异常             | 配置 `HTTPS_PROXY` 或检查本地代理端口                      |
| `node version mismatch`             | Node 版本低于 22.12                 | 使用 `nvm use 22` 或 `nvm install 22` 切换至现代 LTS 版本  |
| `Command failed with exit code 127` | 依赖工具（如 pnpm/git）未在 PATH 中 | 检查全局 npm/pnpm bin 路径是否已加入系统环境变量           |

---

## 结语

安装与初次使用 Claude Code，不是在电脑里装一个“玩具脚本”，而是给你的本地开发环境引入一个具备终端执行权限的自动化工具。

花 10 分钟建立起正确的网络代理、Node 环境和只读验真意识，后续无论是让它重构深层组件、排查死锁 Bug 还是补充测试套件，整个协作过程都会既高效又安全。
