---
author: 李金涛
pubDatetime: 2026-06-25T11:20:00+08:00
title: 人在回路（HITL）：用 Interrupt 与 Command 构建可控 Agent
slug: agent-human-in-the-loop-interrupt-command
featured: false
draft: false
tags:
  - Agent
  - HITL
  - LangGraph
  - 安全
  - 前端架构
description: 译述 LangGraph 的 Human-in-the-loop 核心设计：如何利用 interrupt 挂起运行、持久化 Checkpoint，并通过 Command 与前端审批流无缝恢复。
timezone: Asia/Shanghai
---

在 AI Agent 落地真实业务的过程中，最大的恐惧永远是**“失控”**：

- Agent 自主决定给 1000 位客户发送了未经审查的推销邮件；
- Agent 在数据库迁移任务中意外执行了带有 `DROP TABLE` 的语句；
- Agent 在前端重构时删除了未提交的关键业务代码。

为了解决这个问题，业界早期往往采用简单的“在循环里阻塞终端”或“弹出一个无上下文的确认弹窗”。但在分布式 Web 环境下，用户可能在两小时后才打开手机审批，或者在第二天上班时才点同意——底层的服务进程不可能一直保持内存连接等待。

LangGraph 团队发布的《Making it easier to build human-in-the-loop agents with interrupt》一文，提出了生产级 **Human-in-the-loop (HITL)** 的权威范式：基于 **`interrupt()`** 与 **`Command()`** 原语的有状态挂起与恢复机制。

---

## 传统阻塞模式的致命缺陷

传统的“人在回路”实现通常基于长轮询或线程阻塞：

```text
❌ 传统反模式：同步线程等待 (Blocking Thread)
后端执行 ────> 执行到高危步骤 ────> 线程 sleep / 等待 HTTP 确认 ────> 服务超时挂掉 / 内存泄漏
```

这种方案在生产环境中极易崩溃：

1. **进程隔离失效**：一旦后端容器自动扩缩容重启，等待中的内存状态全部丢失；
2. **多终端体验割裂**：用户在电脑上发起任务，无法在手机审批后台接续；
3. **不可回滚与编辑**：用户只能点“同意”或“取消”，无法在恢复前微调 Agent 的中间状态。

---

## LangGraph 的 HITL 状态机范式：Interrupt 与 Checkpoint

现代的人在回路架构建立在**可持久化状态机**之上。核心由两部分组成：

```text
┌────────────────────────────────────────────────────────┐
│                   HITL 挂起与恢复生命周期               │
└────────────────────────────────────────────────────────┘
                          │
         1. 运行中：生成 Checkpoint 001
                          │
         2. 触发 interrupt({ action: "send_email", ... })
            - 立即将当前全量 State 序列化落盘 (Postgres/Redis)
            - 主动向前端抛出中断事件并优雅终止当前执行线程
                          │
         3. 异步等待：可长达数秒、数小时或数天
            - 前端界面渲染审批卡片，等待人类决策
                          │
         4. 用户决策触发恢复：Command(resume={ approved: true })
            - 从数据库拉取 Checkpoint 001 快照
            - 将人类输入合并入 State，从挂起点继续向下流转
```

### 1. 后端定义中断断点（Python / LangGraph）

```python
from langgraph.types import interrupt, Command

def sensitive_action_node(state):
    action = state["pending_action"]

    # 当遇到写操作或高危动作时，主动调用 interrupt
    # 该函数会直接将入参暴露给调用方，并挂起当前图的执行
    human_decision = interrupt({
        "question": "是否批准该变更？",
        "action": action["type"],
        "payload": action["payload"],
        "risk_level": "high"
    })

    # 当用户通过 Command 恢复时，interrupt 会直接返回 human_decision 的值！
    if not human_decision.get("approved"):
        return {"status": "rejected", "messages": ["用户拒绝了该操作"]}

    # 用户已授权，继续安全执行
    execute_side_effect(action)
    return {"status": "success"}
```

在这里，`interrupt()` 的语法设计精妙绝伦：**对于编写节点逻辑的开发者来说，代码看起来就像是同步获取了人类的输入，而底层的状态序列化、线程挂起和跨机器恢复全由框架自动完成。**

---

## 前端协同层：如何接住并恢复 Interrupt？

很多文章只讲后端如何挂起，却忽略了**前端如何承接这一交互闭环**。

前端在接收到服务端推送的 `interrupt` 事件时，工作流如下：

### 1. 前端状态捕获与卡片渲染

```tsx
import React, { useState } from "react";

export type InterruptPayload = {
  threadId: string;
  interruptId: string;
  action: string;
  payload: Record<string, unknown>;
};

export function HumanApprovalBanner({
  data,
  onResume,
}: {
  data: InterruptPayload;
  onResume: (
    threadId: string,
    approved: boolean,
    note?: string
  ) => Promise<void>;
}) {
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const handleDecision = async (approved: boolean) => {
    setSubmitting(true);
    try {
      await onResume(data.threadId, approved, note);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="my-4 rounded-xl border-2 border-amber-400 bg-amber-50/50 p-4 dark:bg-amber-950/20">
      <div className="mb-2 flex items-center gap-2">
        <span className="text-xl">⚠️</span>
        <h4 className="text-sm font-bold text-neutral-800 dark:text-neutral-200">
          Agent 申请高危操作权限：{data.action}
        </h4>
      </div>

      <pre className="mb-3 overflow-x-auto rounded bg-neutral-900 p-2.5 font-mono text-xs text-neutral-200">
        {JSON.stringify(data.payload, null, 2)}
      </pre>

      <input
        type="text"
        placeholder="批注或修正指令（可选）..."
        value={note}
        onChange={e => setNote(e.target.value)}
        className="mb-3 w-full rounded-md border bg-white px-2.5 py-1.5 text-xs dark:bg-neutral-900"
      />

      <div className="flex justify-end gap-2">
        <button
          disabled={submitting}
          onClick={() => handleDecision(false)}
          className="rounded border border-neutral-300 px-3 py-1.5 text-xs hover:bg-neutral-100"
        >
          拒绝动作
        </button>
        <button
          disabled={submitting}
          onClick={() => handleDecision(true)}
          className="rounded bg-blue-600 px-4 py-1.5 text-xs font-medium text-white shadow-sm hover:bg-blue-700"
        >
          批准并继续 (Command.Resume)
        </button>
      </div>
    </div>
  );
}
```

### 2. 通过 Command API 唤醒恢复

当用户在前端界面点击“批准并继续”时，向后端 API 发送恢复指令：

```ts
export async function resumeAgentRun(
  threadId: string,
  approved: boolean,
  userNote?: string
) {
  const response = await fetch(`/api/threads/${threadId}/resume`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      // 这里的结构会作为后端 interrupt() 函数的返回值直接注入
      resume: { approved, userNote, approvedAt: Date.now() },
    }),
  });

  if (!response.ok) throw new Error("恢复执行失败");
  // 此时服务端重新开启 SSE 流，继续下发后续的生成事件
}
```

---

## 进阶能力：时间旅行与状态篡改（State Editing）

基于快照持久化的 HITL 不仅仅能做简单的“放行 / 拦截”，它还解锁了传统架构无法企及的能力：

1. **时间旅行（Time-Travel Debugging）**：
   任务一共执行了 6 步，在第 4 步因为参数不理想被挂起。用户可以在时间线点击历史第 2 步的 Checkpoint，基于第 2 步的状态拉出一个“分叉（Branch）”重新推理，而不需要从零重新跑一遍前面昂贵的检索。
2. **就地编辑状态（State Mutation）**：
   在审批邮件内容时，用户不仅可以点同意，还可以在界面上直接修改邮件文本。恢复时通过 `Command(update={"email_body": "修正后的文案"}, resume=True)` 直接覆写状态树，模型会基于修正后的事实继续执行。

---

## 结语：可预测性是 Agent 产品的生死线

用户不害怕 Agent 拥有强大的执行能力，用户害怕的是**不可见、不可停、不可挽回的黑盒操作**。

通过将中断提升为一等公民协议（`interrupt`），结合持久化的状态快照与结构化的恢复指令（`Command`），Agent 真正实现了从“脱缰野马”到“训练有素的副驾驶”的跨越。
