---
author: 李金涛
pubDatetime: 2026-05-07T10:00:00+08:00
title: 前端大任务太大时，我会怎样拆给多个 Claude Code
slug: claude-code-multi-agent-frontend
featured: false
tags: [Claude Code, Multi-Agent, 前端, 协作]
description: 将大型前端需求拆成边界清晰的子任务，并控制并行 Agent 的冲突和合并成本。
timezone: Asia/Shanghai
---

当一个前端重构任务涉及几十个组件、几百处类型变更以及国际化文案替换时，单会话的 Agent 很快就会遇到瓶颈：

- 上下文窗口逐渐被冗余的代码堆满，推理速度越来越慢；
- 模型开始遗忘几十轮对话之前的既定约束，出现前后矛盾；
- 任务执行一旦在最后一步中断，往往需要从头排查。

解决超大工程任务的必然出路是**多 Agent 并行协同（Multi-Agent Orchestration）**。

但多 Agent 绝不是简单地打开三个终端同时敲命令。如果缺乏物理隔离与契约设计，多个 Agent 在同一个文件夹里互相覆盖文件、抢占 Git 锁，制造出的冲突排查成本将远远超过单人编写。

---

## 拓扑架构：主从协调模式（Coordinator-Worker Pattern）

在前端工程中，最稳定的多 Agent 协作模式是**主从协调拓扑**，而不是松散的对等网络：

```text
┌────────────────────────────────────────────────────────┐
│             Coordinator Agent (主协调实例)             │
│   负责：通读需求、定义契约接口 (Schema)、切分子任务    │
└────────────────────────────────────────────────────────┘
                             │
     ┌───────────────────────┼───────────────────────┐
     ▼ 分发独立子任务         ▼ 分发独立子任务         ▼ 分发独立子任务
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│   Worker A   │        │   Worker B   │        │   Worker C   │
│ UI 组件样板   │        │ 数据适配与请求 │        │ 单元测试套件   │
│ (Branch A)   │        │ (Branch B)   │        │ (Branch C)   │
└──────────────┘        └──────────────┘        └──────────────┘
     │                       │                       │
     └───────────────────────┼───────────────────────┘
                             ▼ 统一汇聚合并
┌────────────────────────────────────────────────────────┐
│            集成验收：运行全量检查与冲突消除             │
└────────────────────────────────────────────────────────┘
```

- **Coordinator（主 Agent）**：只负责架构规划、制定不变式契约、审查 Worker 的提交记录并执行最终合流。它严禁亲自去写具体组件代码。
- **Workers（子 Agent）**：各自被严格限定在特定的目录范围内，输入为明确的输入输出规范，输出为独立的 Git Commit。

---

## 物理隔离利器：Git Worktrees 隔离工作区

如果你在同一个目录的不同终端里同时启动两个 Claude Code，它们会发生极其灾难的冲突：A 刚写完文件还没提交，B 跑了一次 `git checkout`，导致 A 的修改全部报废。

正确的工程做法是使用 **Git Worktree** 为每个 Worker 派发完全独立的物理文件树：

```bash
# 1. 在主仓库基于 main 分支拉出两个隔离的工作区
git worktree add ../blog-worker-ui -b feat/comment-ui
git worktree add ../blog-worker-api -b feat/comment-api

# 2. 在终端窗口 1 打开 UI 工作区并启动 Claude Code
cd ../blog-worker-ui && claude

# 3. 在终端窗口 2 打开 API 工作区并启动 Claude Code
cd ../blog-worker-api && claude
```

每个 Worktree 拥有完全独立的工作目录与分支头指针，但底层共享同一个 `.git` 对象库。两个 Agent 可以同时读写、同时执行构建，互不干扰。

---

## 实战：契约先行（Contract-First）任务拆分法

以“为博客增加带本地持久化的点赞与评论卡片”为例，我们来看 Coordinator 是如何调度的：

### 阶段一：由主 Agent 固化 TypeScript 契约

在主分支上，Coordinator 仅生成一份不可变的类型契约文件 `src/types/comments.ts`：

```ts
export type CommentItem = {
  id: string;
  postId: string;
  authorName: string;
  content: string;
  createdAt: string;
  likes: number;
};

export interface CommentStorageAdapter {
  list(postId: string): Promise<CommentItem[]>;
  create(
    postId: string,
    payload: Omit<CommentItem, "id" | "createdAt" | "likes">
  ): Promise<CommentItem>;
  like(commentId: string): Promise<number>;
}
```

将该提交推送到基线分支后，Worker 们的任务便拥有了铁一样的锚点。

### 阶段二：并行分派无交集的子任务

- **分派给 Worker A（专注于 UI 渲染）**：

  ```text
  目标：实现 src/components/CommentsView.tsx。
  约束：
  1. 纯展示型组件，依赖 src/types/comments.ts 中的 CommentItem 类型。
  2. 包含空评论占位态、加载骨架屏和提交表单。
  3. 只能修改 src/components/Comments* 目录下的文件，禁止碰触存储与数据层。
  ```

- **分派给 Worker B（专注于存储逻辑与 Mock）**：
  ```text
  目标：实现 src/utils/localCommentAdapter.ts。
  约束：
  1. 实现 CommentStorageAdapter 接口，基于 localStorage 与 BroadcastChannel 实现跨标签页同步。
  2. 只能修改 src/utils/localCommentAdapter.ts，禁止引入任何 UI 依赖。
  3. 编写完整的单测确保增删改查逻辑无误。
  ```

两个 Worker 在各自的 Worktree 中飞速编码、各自运行校验，完全没有等待和阻塞。

---

## 阶段三：集成合流与冲突消解

当 Worker A 和 Worker B 分别在其分支完成提单后，回到主工作区进行集成：

```bash
cd /Users/jt-lee/Desktop/blog-project

# 合并 UI 分支
git merge feat/comment-ui

# 合并 API 分支
git merge feat/comment-api

# 唤醒主 Agent 执行集成测试与类型连通性审查
claude -p "运行 pnpm astro check 与 pnpm build，检查 CommentView 与 localCommentAdapter 连接处是否存在类型不兼容，并完成组装。"
```

主 Agent 此时只需要编写胶水代码（将 Adapter 传给 UI），运行一次类型检查确认全绿，整个大需求就以极高的质量完成了交付。

最后清理临时工作区：

```bash
git worktree remove ../blog-worker-ui
git worktree remove ../blog-worker-api
```

---

## 结语

多 Agent 协作的瓶颈从来不是算力，而是**架构切分的清晰度**。

契约先行确立公理、Git Worktree 打造安全沙箱、主从模式统一调度合流——掌握这套工业级的多 Agent 协同体系，你一个人就能调度一支井然有序的“AI 前端突击队”。
