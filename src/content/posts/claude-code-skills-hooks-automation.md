---
author: 李金涛
pubDatetime: 2026-05-21T10:00:00+08:00
title: 那些重复到不想再做的前端工作，可以交给 Claude Code
slug: claude-code-skills-hooks-automation
featured: false
tags: [Claude Code, Skills, Hooks, 前端自动化]
description: 用 Skills 封装可复用流程，用 Hooks 固定格式化和检查动作。
timezone: Asia/Shanghai
---

前端研发流程中，充斥着大量繁琐而机械的重复劳动：每次提测前手动跑一遍构建检查、每次新增组件时复制样板目录结构、每次发版前核对依赖版本差异……

如果你每次都必须在终端里敲一段三四百字的提示词去指挥 Claude Code：“请帮我审查最近一次提交，重点看类型、无障碍和包体积”，这仍然没有摆脱体力劳动的桎梏。

真正成熟的 AI 工程化做法，是利用 Claude Code 的 **Skills（自定义技能）** 与 **Hooks（生命周期钩子）**，把高频团队经验沉淀为可固化的自动化工作流。

---

## 核心心智模型：Skills 流程 vs Hooks 触发器

很多初学者容易混淆 Skill 与 Hook 的边界，它们分别对应着**命令驱动**与**事件驱动**两种不同的交互哲学：

```text
┌────────────────────────────────────────────────────────┐
│              Skills（主动调用 · 流程化 Recipe）           │
│   用户输入 /review-pr 或 /new-post 显式触发             │
│   面向业务意图，包含多步探索、推理规划与输出排版         │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│              Hooks（被动监听 · 确定性 Trigger）           │
│   在 Agent 执行动作（写文件、运行命令、Git 提交）前后自动触发│
│   面向工程规范，保证无条件执行（如代码自动格式化、拦截高危命令）│
└────────────────────────────────────────────────────────┘
```

---

## 实战一：打造团队专属的 `/review-pr` 技能

我们可以将代码审查的标准 SOP 固化为一个自定义 Skill。在项目根目录下创建 `.claude/skills/review-pr.md`：

```markdown
---
name: review-pr
description: 审查当前分支与主干的代码差异，执行类型检查并输出结构化审查报告
---

请按以下严格次序执行本次代码审查：

1. **提取代码变更**：
   运行 `git diff origin/main...HEAD`，列出所有被修改或新增的文件。若没有差异，提前终止并提示。

2. **静态与类型分析**：
   在终端运行 `pnpm astro check`。如果存在类型报错，记录报错文件名与行号。

3. **前端专项审查维度**：
   - **性能影响**：是否引入了不必要的重型依赖？是否有缺少清理函数的 `useEffect`？
   - **可访问性 (a11y)**：交互元素是否有 `aria-label`？图片是否有 `alt` 属性？
   - **设计系统规范**：样式是否遵循 Tailwind CSS v4 约定？是否存在硬编码的十六进制颜色值？

4. **输出格式**：
   使用 Markdown 呈现，包含：
   - 变更概述（一句话总结）
   - 🔴 必须修复的问题（Blocking Issues，附带行号与修复建议）
   - 🟡 优化建议（Nitpicks）
   - 🟢 检查通过项（Verified Checks）
```

现在，团队成员在终端中只需要简单输入：

```bash
/review-pr
```

Claude Code 就会严格按照既定 SOP 调出 diff、执行校验，并生成工业级格式的审查结论。

---

## 实战二：打造博客自动化发文技能 `/create-post`

在 Astro 博客中，手动建文件经常会遗漏 Frontmatter 字段或输错日期格式。创建 `.claude/skills/create-post.md`：

````markdown
---
name: create-post
description: 根据输入的标题快速创建规范的博客草稿
arguments:
  - name: title
    required: true
    description: 文章标题
---

根据参数 `{{title}}` 执行以下动作：

1. 计算英文文件名 slug：将中文标题转换为小写拼音或英文短语，用中划线连接。
2. 在 `src/content/posts/{{slug}}.md` 创建新文件。
3. 自动注入当前的 ISO 8601 时间戳与严谨的前置元数据：
   ```yaml
   ---
   author: 李金涛
   pubDatetime: { { CURRENT_TIME } }
   title: "{{title}}"
   slug: { { slug } }
   featured: false
   draft: true
   tags:
     - 前端
   description: ""
   timezone: Asia/Shanghai
   ---
   ```
````

4. 运行 `pnpm astro check` 确保内容模式解析无误。

````

只需执行 `/create-post title="React 19 核心并发特性解析"`，标准模板和校验立刻在 2 秒内搞定。

---

## 实战三：配置生命周期 Hooks 守死代码质量

Hooks 适合在动作发生的缝隙中插入确定性脚本。在 `.claude/config.json` 或项目级配置中：

```json
{
  "hooks": {
    "post_file_write": "pnpm prettier --write \"$FILE\"",
    "pre_git_commit": "pnpm astro check && pnpm lint"
  }
}
````

### 1. `post_file_write`：静默格式化守护

每当 Claude Code 完成一次文件修改并落盘时，系统会自动将该文件路径注入 `$FILE` 并执行 Prettier 格式化。
这从根源上避免了“AI 生成的代码缩进与团队 Prettier 规范冲突”的问题，开发者再也不需要手动打格式化补丁。

### 2. `pre_git_commit`：拦截不合格提交

在 Agent 准备调用 `git commit` 前，Hook 会自动执行全量类型与 Lint 校验。如果编译挂了，Hook 会返回非零退出码阻断提单，强制 Agent 立即读取报错并在本地修复。

---

## 防死循环与安全守则

在部署自动化 Hooks 时，务必遵守以下防腐原则：

1. **防止 Hook 级联死循环**：
   如果 `post_file_write` 中执行的命令再次触发了文件写操作，会导致死循环。务必确保 Hook 调用的脚本具备幂等性，或设置递归调用锁。
2. **命令超时保护**：
   为所有自动化脚本设置超时时间（如 `timeout: 30s`），防止单元测试死锁或构建卡死导致 Agent 终端假死。
3. **敏感操作不可越权**：
   涉及 `git push -f`、`npm publish` 或涉及生产部署的动作，**绝对禁止配置为静默 Hook**，必须始终要求人工在终端键盘上按 `y` 授权。

---

## 结语

不要让优秀的工程习惯停留在口头相传的“团队守则”里。

把重复的推演写成 **Skills**，把底线的防守交给 **Hooks**。当你的代码仓库具备了自我格式化、自我校验与按 SOP 执行的能力，Claude Code 才真正从一个“提问工具”蜕变成为团队量身定制的“自动化工作站”。
