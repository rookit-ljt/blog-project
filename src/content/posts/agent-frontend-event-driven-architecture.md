---
author: 李金涛
pubDatetime: 2026-08-25T10:00:00+08:00
title: Agent 前端架构：用事件流和状态机接住不确定性
slug: agent-frontend-event-driven-architecture
featured: true
draft: false
tags:
  - 前端
  - Agent
  - React
  - TypeScript
description: 从消息列表升级到 Agent 工作台：用事件流、状态机和可恢复状态组织复杂的模型交互。
timezone: Asia/Shanghai
---

普通聊天页面只需要关心“用户说了什么”和“模型回答了什么”。Agent 页面还要展示规划意图、并发工具调用、权限审批、失败重试、嵌套子任务和最终产物。

如果继续把这些动态内容硬塞进一个平铺的 `messages` 状态数组，前端代码很快会充斥着各种不可调和的布尔状态：`isGenerating`、`isCallingTool`、`needsApproval`、`isRetrying`、`isPaused`……只要网络稍有抖动或事件微秒级乱序，UI 就会陷入不可恢复的“幽灵加载”或状态错乱。

真正稳健的解法，是把 Agent 前端构建为一个**基于事件驱动的有限状态机（Finite State Machine, FSM）**：后端通过流式通道派发不可变的事实事件（Fact Events），前端状态机通过纯函数 Reducer 计算出唯一的、确定性的视图投影。

---

## 强类型的 Agent 事件协议（Event Specification）

事件必须描述“发生了什么客观事实”，而不是描述“前端组件该怎么渲染”。同时，必须具备全局自增的 `eventId` 和关联任务的 `runId`：

```ts
export type AgentEvent =
  | { id: string; type: "run_started"; runId: string; timestamp: number }
  | { id: string; type: "thinking_delta"; runId: string; delta: string }
  | {
      id: string;
      type: "message_delta";
      runId: string;
      messageId: string;
      text: string;
    }
  | {
      id: string;
      type: "tool_started";
      runId: string;
      callId: string;
      name: string;
      input: Record<string, unknown>;
    }
  | {
      id: string;
      type: "tool_finished";
      runId: string;
      callId: string;
      output: unknown;
    }
  | {
      id: string;
      type: "tool_failed";
      runId: string;
      callId: string;
      error: string;
      retryable: boolean;
    }
  | {
      id: string;
      type: "approval_required";
      runId: string;
      callId: string;
      action: string;
      scope: string;
    }
  | {
      id: string;
      type: "run_completed";
      runId: string;
      stats: { durationMs: number; tokenUsage: number };
    }
  | { id: string; type: "run_failed"; runId: string; error: string };
```

每个事件都具备唯一幂等键 `id`，这使得客户端无论收到多少次重复事件，都不会造成状态污染。

---

## 幂等 Reducer 与视图投影

组件只订阅经过折叠后的最终状态树（Single Source of Truth），不直接理解底层的底层事件包传输细节：

```ts
export type AgentPhase =
  | "idle"
  | "thinking"
  | "executing_tool"
  | "awaiting_approval"
  | "completed"
  | "failed";

export type AgentState = {
  runId?: string;
  phase: AgentPhase;
  lastEventId?: string;
  thinkingContent: string;
  messages: Record<
    string,
    { id: string; role: "user" | "assistant"; content: string }
  >;
  tools: Record<
    string,
    {
      name: string;
      status: "running" | "completed" | "failed" | "requires_approval";
      input: Record<string, unknown>;
      output?: unknown;
      error?: string;
    }
  >;
  activeApprovalCallId?: string;
  error?: string;
};

export function agentReducer(state: AgentState, event: AgentEvent): AgentState {
  // 忽略已处理过的旧事件（幂等保证）
  if (state.lastEventId && event.id <= state.lastEventId) {
    return state;
  }

  const next = { ...state, lastEventId: event.id };

  switch (event.type) {
    case "run_started":
      return {
        ...next,
        runId: event.runId,
        phase: "thinking",
        thinkingContent: "",
        error: undefined,
      };

    case "thinking_delta":
      return {
        ...next,
        thinkingContent: next.thinkingContent + event.delta,
      };

    case "message_delta": {
      const prevMsg = next.messages[event.messageId]?.content ?? "";
      return {
        ...next,
        messages: {
          ...next.messages,
          [event.messageId]: {
            id: event.messageId,
            role: "assistant",
            content: prevMsg + event.text,
          },
        },
      };
    }

    case "tool_started":
      return {
        ...next,
        phase: "executing_tool",
        tools: {
          ...next.tools,
          [event.callId]: {
            name: event.name,
            status: "running",
            input: event.input,
          },
        },
      };

    case "tool_finished":
      return {
        ...next,
        phase: "thinking",
        tools: {
          ...next.tools,
          [event.callId]: {
            ...next.tools[event.callId],
            status: "completed",
            output: event.output,
          },
        },
      };

    case "approval_required":
      return {
        ...next,
        phase: "awaiting_approval",
        activeApprovalCallId: event.callId,
        tools: {
          ...next.tools,
          [event.callId]: {
            ...next.tools[event.callId],
            status: "requires_approval",
          },
        },
      };

    case "run_completed":
      return { ...next, phase: "completed" };

    case "run_failed":
      return { ...next, phase: "failed", error: event.error };

    default:
      return next;
  }
}
```

纯函数 Reducer 的最大价值是**可确定性（Determinism）与时间旅行回放能力**：只要把历史事件列表重新给 Reducer 跑一遍，页面就能在 1 毫秒内完全复原当时的状态，极其适合测试用例编写与问题复现。

---

## 工业级流式传输 Hook：心跳与断线自动重连

在生产环境中，移动端弱网、笔记本休眠合盖或代理服务超时经常会导致 SSE 连接静默中断。一个合格的前端流式消费器必须处理**心跳检测、指数退避重连与 `Last-Event-ID` 补发**：

```tsx
import { useReducer, useEffect, useRef } from "react";

export function useAgentStream(runId: string | null) {
  const [state, dispatch] = useReducer(agentReducer, {
    phase: "idle",
    thinkingContent: "",
    messages: {},
    tools: {},
  });

  const abortControllerRef = useRef<AbortController | null>(null);
  const reconnectAttempts = useRef(0);
  const heartbeatTimer = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (!runId) return;

    let isCancelled = false;

    async function connect() {
      abortControllerRef.current = new AbortController();
      const headers: Record<string, string> = { Accept: "text/event-stream" };
      if (state.lastEventId) {
        headers["Last-Event-ID"] = state.lastEventId;
      }

      try {
        const response = await fetch(`/api/runs/${runId}/stream`, {
          headers,
          signal: abortControllerRef.current.signal,
        });

        if (!response.ok || !response.body) {
          throw new Error(`连接失败 HTTP ${response.status}`);
        }

        reconnectAttempts.current = 0; // 重置重连计数
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        const resetHeartbeat = () => {
          if (heartbeatTimer.current) clearTimeout(heartbeatTimer.current);
          heartbeatTimer.current = setTimeout(() => {
            // 超过 15 秒未收到任何数据分块，判定为假死中断，主动断开重连
            abortControllerRef.current?.abort();
          }, 15000);
        };

        resetHeartbeat();

        while (!isCancelled) {
          const { value, done } = await reader.read();
          if (done) break;

          resetHeartbeat();
          buffer += decoder.decode(value, { stream: true });

          const lines = buffer.split("\n\n");
          buffer = lines.pop() ?? "";

          for (const rawChunk of lines) {
            const dataLine = rawChunk
              .split("\n")
              .find(l => l.startsWith("data: "));
            if (dataLine) {
              const payload: AgentEvent = JSON.parse(dataLine.slice(6));
              dispatch(payload);
            }
          }
        }
      } catch (err) {
        if (isCancelled) return;

        // 指数退避重连策略：1s, 2s, 4s, 最大 10s
        const delay = Math.min(1000 * 2 ** reconnectAttempts.current, 10000);
        reconnectAttempts.current += 1;

        if (reconnectAttempts.current <= 5) {
          setTimeout(connect, delay);
        } else {
          dispatch({
            id: `err-${Date.now()}`,
            type: "run_failed",
            runId,
            error: "网络连接已中断，请检查网络后手动重试",
          });
        }
      }
    }

    connect();

    return () => {
      isCancelled = true;
      if (heartbeatTimer.current) clearTimeout(heartbeatTimer.current);
      abortControllerRef.current?.abort();
    };
  }, [runId]);

  return { state, stop: () => abortControllerRef.current?.abort() };
}
```

---

## 前端会话持久化与状态恢复

为了让用户在刷新浏览器或切换路由时不丢失正在进行的任务：

1. **本地 IndexedDB 影子存储**：每当接收到关键状态变更（如 `approval_required` 或 `run_completed`），将当前 State 异步写入本地 IndexedDB。
2. **多标签页同步（BroadcastChannel）**：如果用户在同一浏览器的两个标签页中打开了同一个 Agent 工作台，通过 `BroadcastChannel("agent_sync")` 广播状态变更，避免双向并发调用引发数据撕裂。

---

## 权威参考与技术演进

- **W3C Server-Sent Events Specification**：明确规定了 `text/event-stream`、`id` 字段机制以及浏览器原生通过 `Last-Event-ID` 恢复连接的标准行为。
- **OpenAI Responses API & Assistant Stream**：主流大模型 API 均已演进为全事件流（Full Event Stream）协议，按顺序派发 `step_created`、`tool_calls` 与 `message_completed` 事件。
- **XState 与 Actor Model**：在高度复杂的前端 Agent 控制台中，使用成熟的状态图（Statechart）对 Agent 生命周期建模，能从形式化层面彻底消灭非法状态组合。

## 结语

从“无状态聊天框”升级到“事件驱动 Agent 工作台”，前端架构必须完成从**面向消息**到**面向事件流与状态机**的范式转移。

通过确定性的事件规范、纯函数 Reducer 状态折叠以及工业级的重连持久化引擎，前端不再是被动接收文本的气泡容器，而是成为了接住大模型执行不确定性、为人机协同保驾护航的稳固底座。
