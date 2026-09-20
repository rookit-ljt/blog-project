---
author: 李金涛
pubDatetime: 2026-08-04T16:15:00+08:00
title: Agent 流式输出的三种粒度：Token、Step 与全局 State
slug: agent-streaming-tokens-steps-state
featured: false
draft: false
tags:
  - Agent
  - Streaming
  - 前端
  - LangGraph
  - 用户体验
description: 译述 LangGraph 流式通信精要：从单一文本 Token 流升级到中间步骤 Step 与全图 State 快照流，解决复杂 Agent 界面渲染抖动。
timezone: Asia/Shanghai
---

在普通聊天机器人的时代，前端工程师对“流式输出（Streaming）”的理解非常朴素：

> “起一个 SSE 或 HTTP 分块连接，服务端吐一个字的 Token，前端就往页面追加一个字。”

但在构建现代 Agent（特别是包含思考规划、并行工具调用、多步回溯的复杂系统）时，只支持 Token 流会立刻让前端陷入混乱：

- 模型正在调用 `web_search`，页面上静默无声长达 10 秒，用户以为连接已断开；
- 两个并发工具同时返回数据，终端打印的输出与模型正文相互交叉打架；
- 前端只拿到碎片的字符流，无法感知整个任务的拓扑进度与阶段完成度。

LangGraph 团队发布的《Streaming in LangGraph》一文，系统性梳理了生产级 Agent 系统的**三层流式传输粒度**。理解这三种粒度，是前端工程师搭建专业级 Agent 工作台的必修课。

---

## Agent 流式通信的三种粒度

在 LangGraph 架构中，流式输出被清晰解耦为三种不同职责的数据通道：

```text
┌────────────────────────────────────────────────────────┐
│                   Agent 流式通信的三种粒度              │
└────────────────────────────────────────────────────────┘
                          │
         1. Token 级流 (LLM Generation Chunk)
            - 关注微观文字呈现（打字机效果）
                          │
         2. Step / Node 级流 (Intermediate Steps)
            - 关注行为推进（哪个工具正在运行、耗时、出参入参）
                          │
         3. State 级流 (State Values & Updates Snapshot)
            - 关注宏观业务状态（全局进度树、审批状态、数据快照）
```

---

## 粒度一：Token 级流（LLM Generation Token）

这是最基础的流式层级，由大模型底层 API 原生派发（例如 OpenAI 的 `delta.content` 或 Anthropic 的 `content_block_delta`）。

- **传输内容**：`"你"`, `"好"`, `"！"`, `"我正在"`……
- **前端职责**：负责打字机动效、平滑滚动定位与增量 Markdown 围栏保护。
- **局限性**：Token 流只存在于大模型输出文本的瞬间。当图进入非 LLM 节点（如纯 Python 数据清洗、外部 API 请求、数据库查询）时，Token 流会完全中断。如果界面只监听 Token，就会出现假死态。

---

## 粒度二：Step / Node 级流（中间执行步骤）

当 Agent 决定调用工具或图流转到某个特定节点时，框架会派发 Step 级别的事件。

在 LangGraph 中对应 `stream_mode="updates"`：

```json
// 后端发出的 Step 增量事件
{
  "event": "on_tool_start",
  "data": {
    "tool": "github_pull_request_check",
    "input": { "pr_id": 412 },
    "started_at": 1722759300120
  }
}
```

```json
// 2 秒后工具完成的事件
{
  "event": "on_tool_end",
  "data": {
    "tool": "github_pull_request_check",
    "output": { "status": "approved", "mergeable": true },
    "duration_ms": 2040
  }
}
```

- **传输内容**：节点的进入、退出、入参快照与执行耗时。
- **前端职责**：驱动**工具调用时间线（Execution Timeline）**。在这一层，页面可以展示动画齿轮、实时耗时计数器以及参数折叠面板，即便模型此时没有生成任何自然语言，用户也能直观感知到“系统正在努力跑检查”。

---

## 粒度三：State 级流（全局状态投影快照）

这是最适合复杂前端产品形态的高级流式模式。在 LangGraph 中对应 `stream_mode="values"`。

每当图中的任何一个节点执行完毕并返回 State Update 时，框架会自动将当前合并后的**完整状态树（Full Graph State Snapshot）**推送到客户端：

```ts
// 客户端收到的完整 State 快照
export type FullAgentStateSnapshot = {
  activeNode: "code_reviewer";
  phase: "analyzing" | "waiting_approval" | "done";
  progressPercentage: number;
  openFiles: string[];
  findings: Array<{ line: number; issue: string }>;
  messages: Array<{ role: string; content: string }>;
};
```

### 为什么前端极度需要 State 级流？

1. **彻底消除前端状态拼装的脆弱性**：
   如果只给前端推碎片事件，前端需要写大量极其复杂的 Reducer 试图“脑补”出后端当前的全貌，一旦中间丢失一个包，整个 UI 就会状态错乱。
   拥有 State 级流后，前端只需要把接收到的最新对象执行一次 `setState(newSnapshot)`，即可永远与服务端保持绝对一致。
2. **多终端多组件解耦**：
   左侧的“文件树组件”、右侧的“审查报告组件”和底部的“进度条组件”，可以直接各自订阅 State 快照的局部字段，不需要彼此通过全局事件总线艰难通信。

---

## 前端实战：三合一消费 Hook 设计

在生产级 React 应用中，我们需要在一条 SSE 连接上统一消费这三类混合数据：

```tsx
import { useEffect, useState } from "react";

export function useAgentMultiStream(runId: string) {
  const [tokens, setTokens] = useState("");
  const [timelineSteps, setTimelineSteps] = useState<any[]>([]);
  const [globalState, setGlobalState] = useState<any>(null);

  useEffect(() => {
    const es = new EventSource(`/api/runs/${runId}/mixed-stream`);

    // 1. 监听微观 Token
    es.addEventListener("token", e => {
      const { text } = JSON.parse(e.data);
      setTokens(prev => prev + text);
    });

    // 2. 监听中间工具步骤
    es.addEventListener("step", e => {
      const step = JSON.parse(e.data);
      setTimelineSteps(prev => [...prev, step]);
    });

    // 3. 监听宏观状态快照
    es.addEventListener("state_snapshot", e => {
      const fullState = JSON.parse(e.data);
      setGlobalState(fullState);
    });

    return () => es.close();
  }, [runId]);

  return { tokens, timelineSteps, globalState };
}
```

---

## 结语：让“思考的新陈代谢”清晰可见

大模型的思考耗时不会在一夜之间缩短至零。在长达数十秒的复杂推理任务中，**可见性就是最好的用户体验**。

通过将流式能力解耦为 **微观文字（Token）**、**行为中枢（Step）** 与 **宏观全局（State）** 三个层次，前端工程师得以将复杂、黑盒的 Agent 运算，重构为层次分明、动静皆宜的可视化交互现场。
