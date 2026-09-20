---
author: 李金涛
pubDatetime: 2026-09-02T10:00:00+08:00
title: Agent 的记忆系统架构：短期 Checkpoint 与跨会话 Long-Term Store
slug: agent-memory-architecture-checkpoint-and-store
featured: false
draft: false
tags:
  - Agent
  - Memory
  - LangGraph
  - 状态管理
  - 架构
description: 译述 LangChain 记忆架构最新实践：区分单会话 Checkpoint 栈与跨会话持久化 Store API，为 Agent 构建像人脑一样分层的记忆系统。
timezone: Asia/Shanghai
---

在与大语言模型交流时，最令人挫败的体验之一莫过于它的“失忆症”：

- 昨天明明刚跟它约定过“我是前端架构师，请用 TypeScript 严格模式回答”，今天换了一个新会话，它又重新从最基础的 JavaScript 讲起；
- 在一个长达 30 步的复杂开发任务中，中间因为浏览器刷新，之前的推演上下文全部归零。

许多人以为解决记忆问题就是“把聊天记录一股脑存进数据库，每次请求全量塞进 Prompt”。但在真实业务中，这种暴力追加很快会把 Token 窗口撑爆，同时引发灾难性的记忆错乱。

LangChain / LangGraph 团队在最新的系统设计中，正式明确了 **Agent 记忆系统的两层架构（Two-Tier Memory Architecture）**：

1. **短期工作记忆（Thread-Scoped Checkpointer）**；
2. **长期语义记忆（Cross-Thread Store API）**。

---

## 人脑记忆模型与 Agent 架构的映射

认知科学将人类记忆划分为两类：**工作记忆（Working Memory）**与**长期记忆（Long-Term Memory）**。现代 Agent 记忆架构正是这一理论在工程上的数字映射：

```text
┌────────────────────────────────────────────────────────┐
│                   Agent 两层记忆架构体系                │
└────────────────────────────────────────────────────────┘
                          │
     ┌────────────────────┴────────────────────┐
     ▼                                         ▼
【短期记忆 (Short-Term)】               【长期记忆 (Long-Term)】
- 作用域：单会话 / 单线程 (Thread)      - 作用域：跨会话 / 全局用户 (Cross-Thread)
- 载体：Checkpointer (快照栈)          - 载体：Store API (文档/语义库)
- 记录：当前对话、中间变量、工具出参      - 记录：用户画像、编码偏好、项目硬约束
- 特性：不可变、支持时间旅行回滚         - 特性：异步提取、语义检索 (Vector/BM25)
```

---

## 短期工作记忆：基于 Checkpointer 的快照回滚

单次任务内部的记忆，在 LangGraph 中由 **Checkpointer** 统一接管。

每当 Agent 执行完图中的一个节点，Checkpointer 会自动生成一条包含时间戳、`thread_id` 和当前全量状态的快照：

```python
# 后端挂载持久化 Checkpointer
from langgraph.checkpoint.postgres import PostgresSaver

checkpointer = PostgresSaver(conn_pool)
app = workflow.compile(checkpointer=checkpointer)

# 执行时传入线程标识
config = {"configurable": {"thread_id": "session-user-1024"}}
app.invoke({"messages": [...]}, config=config)
```

### 短期记忆的杀手级功能：Time-Travel 回退

因为每一次状态更新都有独立的 Checkpoint ID，当 Agent 在第 10 步做出愚蠢的决策时，用户不需要推翻重来。

前端可以直接调取历史快照树：

```text
Checkpoint #1 (用户提问) ➔ Checkpoint #2 (检索文档) ➔ Checkpoint #3 (修改代码，失败)
                                    │
                         【从 Checkpoint #2 重新拉出分支】
                                    ▼
                         Checkpoint #3' (人工修改提示词后重新推理)
```

这种回滚能力是让长链路 Agent 具备工程可用性的关键基础。

---

## 长期语义记忆：基于 Store API 的知识提取

如果说短期记忆记录的是“刚才发生了什么细节”，长期记忆关心的则是**“从过去的经历中总结出什么一般规律”**。

在开启新的会话线程（Thread）时，短期记忆会清空，但 Agent 依然能通过 **Store API** 调取关于该用户的长期偏好：

```python
# 长期存储命名空间：(用户ID, 记忆类别)
user_memory_key = ("users", "user_1024")

# 1. 存储长期事实
store.put(
    user_memory_key,
    "tech_preferences",
    {
        "framework": "React 19 + Astro",
        "style": "Tailwind CSS v4",
        "typescript_mode": "strict",
        "avoid_libraries": ["lodash", "moment"]
    }
)

# 2. 在新会话中快速检索
preferences = store.get(user_memory_key, "tech_preferences")
```

### 记忆如何沉淀？不要让主链路阻塞

优秀的工程实践绝不会在用户发送消息时同步调用模型去总结记忆。

通常采用**后台影子提取器（Background Memory Extractor）**：

1. 用户正常与 Agent 交流，会话正常结束；
2. 调度一个低优先级的轻量级模型，异步分析刚刚的对话记录；
3. 提取出有持久价值的事实（例如：“用户明确提到他们禁止在生产代码中使用 `any`”）；
4. 将该事实通过语义嵌入存入长期 Store，静默完成知识沉淀。

---

## 前端全栈实践：浏览器与服务端的记忆协同

在前端工程中，我们如何与后端的两层记忆体系对接？

```text
┌─────────────────────────┐             ┌─────────────────────────┐
│        浏览器前端        │             │        Agent 服务端      │
│                         │             │                         │
│  [ IndexedDB 本地缓存 ] ─── 刷新页面恢复 ──> [ Checkpoint 线程快照 ] │
│  (离线状态/草稿暂存)     │             │ (精确到节点级执行栈)     │
│                         │             │                         │
│  [ 本地 LocalStorage ] ──── 用户偏好同步 ─> [ Store API 长期存储 ]  │
│  (UI 主题/语言偏好)     │             │ (跨设备跨会话用户画像)   │
└─────────────────────────┘             └─────────────────────────┘
```

1. **会话级恢复（Thread Hydration）**：
   在前端单页应用（SPA）中，把当前激活的 `thread_id` 保存在 URL Query 参数中（如 `?thread=xyz`）。即便用户刷新网页，前端只需请求 `/api/threads/xyz/state`，就能在 100ms 内复原包括中间工具时间线在内的全部执行状态。
2. **轻重结合的数据沉淀**：
   对于 UI 级偏好（如深色模式、面板折叠比例），直接由前端在客户端维护；对于业务级决策与编码偏好，由后端 Store API 统一提供，确保用户在 Web、终端 CLI 或 IDE 插件中使用同一套个性化配置。

---

## 结语：让智能具备时间的厚度

没有记忆的智能体，只是无根的计算器；缺乏分层的记忆系统，又会沦为信息的垃圾场。

通过将记忆解耦为**聚焦当前闭环的 Checkpoint 快照**与**跨越时间周期的语义 Store**，我们赋予了 Agent 既能精细推演当下、又能伴随用户长期共同成长的真正工程智能。
