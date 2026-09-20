---
author: 李金涛
pubDatetime: 2026-06-18T10:00:00+08:00
title: 我把前端项目的规矩写进 CLAUDE.md 之后
slug: claude-code-claude-md-project-rules
featured: false
tags: [Claude Code, CLAUDE.md, 前端, 工程规范]
description: 用 CLAUDE.md 固定前端项目的技术栈、目录约定、验证命令和代码审查规则。
timezone: Asia/Shanghai
---

每次开启新的终端会话，都要反复叮嘱 Agent：“我们用的是 pnpm 不是 npm”、“别给我写 `any`”、“改完代码记得跑一下类型检查”……

这种重复沟通不仅浪费宝贵的上下文窗口，更会导致 Agent 在不同任务之间产生严重的“行为漂移”（Behavioral Drift）。

Claude Code 官方提供的解决方案是在项目根目录放置一份 **`CLAUDE.md`**。它会在每次会话启动时被自动注入为最高优先级的系统级上下文，充当团队工程规范与 AI 协作契约的“定海神针”。

---

## 优秀 `CLAUDE.md` 的四大核心要素

一份能够真正约束模型行为的 `CLAUDE.md`，必须具备“具体、可执行、可机器验证”的特点。避免写“请编写优美简洁的代码”这种无法验证的空话。

```text
┌────────────────────────────────────────────────────────┐
│                   CLAUDE.md 四大核心要素                │
└────────────────────────────────────────────────────────┘
                          │
         1. 常用命令与校验契约 (Commands & Validation)
            - 精确的构建、测试、类型检查命令，杜绝包管理器混用
                          │
         2. 代码风格与架构不变量 (Architecture & Style)
            - 目录分层职责、状态管理规范、组件抽离原则
                          │
         3. 负向约束与红线 (Negative Constraints)
            - 明确禁止的行为（如禁止静默降级 tsconfig、禁止引入重量级依赖）
                          │
         4. 提交与审查规范 (Commits & Review)
            - Git 分支命名、Conventional Commits 格式、修改后说明规范
```

---

## 生产级前端 `CLAUDE.md` 完整模板

以下是为现代前端工程（以 Astro / React / TypeScript / Tailwind 为例）精心提炼的模板，可直接作为根目录规范：

```markdown
# Project Engineering Rules

## 1. Package Management & Scripts

- **Package Manager**: Strictly use `pnpm`. Never execute `npm install` or `yarn`.
- **Type Checking**: Run `pnpm astro check` or `pnpm tsc --noEmit`. Must pass with 0 errors and 0 warnings.
- **Lint & Format**: Run `pnpm format:check` and `pnpm lint`. Use `pnpm format` to auto-format.
- **Build**: `pnpm build`. Do not commit if the build fails.

## 2. Code Invariants & Architectural Rules

- **TypeScript**: Strict mode is enabled. Absolutely NO `any`. Use `unknown` with type guards or generics.
- **Node vs Web APIs**: This project runs in strict ESM. Avoid Node-specific globals (e.g. `Buffer`, `process.cwd()`) in universal components; import from `node:buffer` or web standards where appropriate.
- **Content Collections**: All blog posts live in `src/content/posts/*.md`. Frontmatter must strictly adhere to the Zod schema defined in `src/content.config.ts`.
- **Styling**: Use Tailwind CSS v4 utility classes. Keep class order logical (layout -> spacing -> typography -> visual -> interactive). Avoid inline CSS styles.

## 3. Negative Constraints (Must NOT Do)

- **NO Silent Downgrades**: Never disable TypeScript checks, lint rules, or test assertions to make a build "green".
- **NO Unvetted Dependencies**: Do not install new third-party npm packages without explaining the rationale and size impact to the user first.
- **NO Direct Main Branch Edits**: Any destructive Git commands (`git push --force`, `git reset --hard`) require explicit human confirmation.

## 4. Workflow & Git Commits

- Commit messages MUST follow Conventional Commits:
  - `feat(scope): ...` for new features
  - `fix(scope): ...` for bug fixes
  - `refactor(scope): ...` for structural changes without behavior alterations
- After modifying files, always verify with `pnpm astro check` before declaring the task complete.
```

---

## 多层级继承：工作区与个人偏好解耦

随着项目规模增长，规则也需要分层管理。Claude Code 支持多级规则继承链：

```text
~/.claude/CLAUDE.md              # 1. 个人全局配置（个人编辑器喜好、输出语言偏好）
   └── repo/CLAUDE.md            # 2. 仓库根目录（团队共识、构建命令、代码架构）
        └── repo/src/content/CLAUDE.md # 3. 子目录覆盖（博文排版、Markdown 特殊语法）
```

- **团队根规则（`repo/CLAUDE.md`）**：纳入 Git 版本控制，团队成员共享，代码审查时严格把关。
- **子目录就近规则（Scoped rules）**：针对微前端或特定子包，例如在 `packages/ui/CLAUDE.md` 中规定“只能使用纯 CSS Modules，禁止引用 Tailwind”。
- **个人本地偏好（`~/.claude/CLAUDE.md`）**：存放在用户主目录下，例如“请始终用中文回复思考过程”、“每次修改后展示统一的 git diff”。**切勿将个人偏好提交到团队仓库中**。

---

## 规则工程技巧：如何让 Agent 真正听话？

很多团队抱怨写了 `CLAUDE.md` 但 Agent 还是偶尔违规，通常是因为规则表述不符合大语言模型的注意力机制：

1. **用“正负配对”强化边界**：
   - 弱规则：“请使用正确的类型定义。”
   - 强规则：“必须使用强类型。**禁止使用 `any`**；若类型未知，请定义具名 `interface` 或使用 `unknown` 配合类型守卫。”
2. **绑定确定的校验命令**：
   - 弱规则：“请保持代码格式整洁。”
   - 强规则：“修改完成后，**必须自动运行 `pnpm format:check`**，若有差异直接运行 `pnpm format` 修复。”
3. **保持简炼，定期修剪**：
   `CLAUDE.md` 不是产品需求文档，篇幅控制在 100~200 行以内效果最佳。把已过时的临时要求（如“正在重构 v2 版本期间注意某某文件”）及时清理，防止过时上下文污染推理。

---

## 结语

把团队踩过的坑、项目的技术约束和代码审查标准写进 `CLAUDE.md`，本质上是在将团队中**隐性的工程经验转化为显性的数字资产**。

每一次拉取分支、每一位新加入的成员、每一次启动 Claude Code，这些规则都会自动生效，成为保障代码质量和工程一致性的无形防线。
