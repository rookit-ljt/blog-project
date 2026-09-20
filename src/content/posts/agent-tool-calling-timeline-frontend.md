---
author: 李金涛
pubDatetime: 2026-08-12T10:00:00+08:00
title: 把 Agent 工具调用做成前端时间线
slug: agent-tool-calling-timeline-frontend
featured: false
draft: false
tags:
  - 前端
  - Agent
  - UX
  - TypeScript
description: 设计工具调用时间线的事件模型、加载状态、输入输出折叠和错误恢复，让 Agent 的执行过程清晰可读。
timezone: Asia/Shanghai
---

当 Agent 调用搜索、数据库或代码执行工具时，用户最关心的不是一串冰冷的 JSON，而是三个朴素的问题：**它现在在做什么？为什么要做这一步？结果是否可信？**

如果把工具调用直接塞在聊天气泡里，长篇的入参和返回值会迅速淹没真正的对话内容；如果单独做一个黑盒式的“日志抽屉”，用户又很难把工具操作和当前生成的回答建立因果对应。

更符合直觉的交互方案，是把工具执行抽象为**内嵌于对话流中的交互式时间线（Execution Timeline）**：摘要默认简洁易读，关键参数与原始返回值按需折叠展开，局部失败允许独立重试，高频调用支持自适应折叠。

---

## 状态与事件协议设计

工具事件不应当只是一段粗糙的 log 文本。前端需要完整的生命周期、精确到毫秒的时间戳、工具元信息以及可渲染的业务摘要：

```ts
export type ToolStatus =
  "queued" | "running" | "success" | "error" | "requires_approval";

export type ToolRunItem = {
  callId: string;
  toolName: string;
  humanReadableLabel: string;
  status: ToolStatus;
  input: Record<string, unknown>;
  output?: Record<string, unknown> | string;
  error?: string;
  startedAt: number;
  finishedAt?: number;
  isRetrying?: boolean;
};
```

其中 `humanReadableLabel` 至关重要：由后端或客户端工具映射表根据入参生成，例如当工具名为 `web_search`、入参为 `{ query: "Astro 5.0 breaking changes" }` 时，展示的标题应为 `检索 “Astro 5.0 breaking changes”`，而不是暴露底层的函数签名。

---

## 时间线节点组件与动态耗时

工具执行过程中，一个静态的转圈动画很容易让用户怀疑“是不是死锁了”。展示动态增加的运行耗时并配合呼吸态微动效，能极大缓解等待焦虑：

```tsx
import React, { useState, useEffect } from "react";

function useElapsedTime(startedAt: number, finishedAt?: number) {
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    if (finishedAt) {
      setElapsed(finishedAt - startedAt);
      return;
    }
    const interval = setInterval(() => {
      setElapsed(Date.now() - startedAt);
    }, 100);
    return () => clearInterval(interval);
  }, [startedAt, finishedAt]);

  return (elapsed / 1000).toFixed(1);
}

export function ToolTimelineNode({
  run,
  onRetry,
}: {
  run: ToolRunItem;
  onRetry?: (callId: string) => void;
}) {
  const [isOpen, setIsOpen] = useState(
    run.status === "error" || run.status === "running"
  );
  const seconds = useElapsedTime(run.startedAt, run.finishedAt);
  const [copied, setCopied] = useState(false);

  const statusIcons: Record<ToolStatus, React.ReactNode> = {
    queued: <span className="text-neutral-400">⏳</span>,
    running: (
      <span className="inline-block animate-spin text-blue-500">⚙️</span>
    ),
    success: <span className="text-emerald-500">✓</span>,
    error: <span className="text-rose-500">✕</span>,
    requires_approval: <span className="text-amber-500">✋</span>,
  };

  const copyPayload = () => {
    navigator.clipboard.writeText(
      JSON.stringify({ input: run.input, output: run.output }, null, 2)
    );
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="group relative pb-4 pl-6 last:pb-1">
      {/* 时间线轴线 */}
      <div className="absolute top-3 bottom-0 left-2.5 w-0.5 bg-neutral-200 group-last:hidden dark:bg-neutral-800" />

      {/* 状态徽标锚点 */}
      <div className="absolute top-1 left-0 flex h-5 w-5 items-center justify-center rounded-full border border-neutral-300 bg-white text-xs shadow-sm dark:border-neutral-700 dark:bg-neutral-900">
        {statusIcons[run.status]}
      </div>

      <div className="rounded-lg border border-neutral-200 bg-white p-3 text-xs shadow-sm dark:border-neutral-800 dark:bg-neutral-900">
        <div
          className="flex cursor-pointer items-center justify-between select-none"
          onClick={() => setIsOpen(!isOpen)}
        >
          <div className="flex items-center gap-2">
            <span className="rounded bg-neutral-100 px-1.5 py-0.5 font-mono text-[11px] font-semibold text-neutral-800 dark:bg-neutral-800 dark:text-neutral-200">
              {run.toolName}
            </span>
            <span className="text-neutral-700 dark:text-neutral-300">
              {run.humanReadableLabel}
            </span>
          </div>

          <div className="flex items-center gap-2 text-neutral-400">
            <span>{seconds}s</span>
            <span
              className="inline-block transform text-[10px] transition-transform duration-200"
              style={{ transform: isOpen ? "rotate(90deg)" : "rotate(0deg)" }}
            >
              ▶
            </span>
          </div>
        </div>

        {isOpen && (
          <div className="mt-3 space-y-2 border-t border-neutral-100 pt-2.5 font-mono dark:border-neutral-800">
            <div>
              <div className="mb-1 flex justify-between font-sans text-[10px] font-medium text-neutral-400">
                <span>参数（Input Payload）</span>
                <button
                  type="button"
                  onClick={copyPayload}
                  className="text-blue-600 hover:underline dark:text-blue-400"
                >
                  {copied ? "已复制 ✓" : "复制 JSON"}
                </button>
              </div>
              <pre className="max-h-40 overflow-x-auto rounded bg-neutral-50 p-2 text-[11px] text-neutral-700 dark:bg-neutral-950 dark:text-neutral-300">
                {JSON.stringify(run.input, null, 2)}
              </pre>
            </div>

            {run.output && (
              <div>
                <div className="mb-1 font-sans text-[10px] font-medium text-neutral-400">
                  返回值（Output Result）
                </div>
                <pre className="max-h-48 overflow-x-auto rounded bg-neutral-50 p-2 text-[11px] text-neutral-700 dark:bg-neutral-950 dark:text-neutral-300">
                  {typeof run.output === "string"
                    ? run.output
                    : JSON.stringify(run.output, null, 2)}
                </pre>
              </div>
            )}

            {run.status === "error" && (
              <div className="flex items-center justify-between rounded border border-rose-200 bg-rose-50 p-2 font-sans text-rose-700 dark:border-rose-900 dark:bg-rose-950/40 dark:text-rose-300">
                <span className="max-w-[80%] truncate">
                  {run.error || "调用发生未知错误"}
                </span>
                {onRetry && (
                  <button
                    type="button"
                    onClick={() => onRetry(run.callId)}
                    className="rounded bg-rose-600 px-2 py-1 text-[10px] font-medium text-white hover:bg-rose-700"
                  >
                    重试该工具
                  </button>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
```

---

## 高频同类工具调用的折叠与聚类

在代码审查或跨文档扫描场景中，Agent 可能会在短时间内连续调用 20 次 `read_file` 或 `grep_search`。如果时间线被这 20 个节点完全撑开，用户就会迷失在无意义的滚动条中。

优秀的实践是在前端状态层实现**连续同类调用的自动折叠聚类（Call Grouping）**：

```ts
export type TimelineGroup =
  | { type: "single"; run: ToolRunItem }
  | {
      type: "group";
      toolName: string;
      runs: ToolRunItem[];
      isSuccess: boolean;
    };

export function groupConsecutiveToolRuns(runs: ToolRunItem[]): TimelineGroup[] {
  const groups: TimelineGroup[] = [];

  for (const run of runs) {
    const last = groups[groups.length - 1];
    if (last && last.type === "group" && last.toolName === run.toolName) {
      last.runs.push(run);
      if (run.status === "error") last.isSuccess = false;
    } else if (
      last &&
      last.type === "single" &&
      last.run.toolName === run.toolName
    ) {
      // 当连续出现两次以上同类调用时，自动升级为折叠组
      groups[groups.length - 1] = {
        type: "group",
        toolName: run.toolName,
        runs: [last.run, run],
        isSuccess: last.run.status !== "error" && run.status !== "error",
      };
    } else {
      groups.push({ type: "single", run });
    }
  }

  return groups;
}
```

在 UI 上，这个 Group 默认显示为：`📁 批量读取 12 个文件 (全部成功 · 耗时 3.4s)`。用户点击展开后，才会看到这 12 个文件的明细列表。这种自适应折叠策略让时间线在面对长周期任务时依然保持清爽。

---

## 局部错误恢复与单步重试

工具调用失败（例如搜索超时、外部 API 鉴权过期或临时 502）不应该一刀切地导致整个会话崩溃。

前端应提供局部的修复与重试协议：

1. **生成重试 callId**：重试时派发包含 `originalCallId` 和新 `retryCallId` 的指令，不要直接覆写原有的失败记录。保留失败节点有助于后续审查。
2. **支持参数就地微调**：对于因为参数校验失败（例如日期格式不对）的工具调用，允许用户点击“修改参数重试”，弹出一个轻量 JSON 编辑面板。
3. **向模型注入用户干预事件**：重试成功后，给模型的消息上下文中追加一条系统消息：`[Tool ${name} failed on attempt 1, succeeded on retry by user intervention]`，让模型明确感知执行状态的修正。

---

## 大数据量防护与安全沙箱

当工具返回的内容包含 2MB 的搜索 HTML 或庞大的 SQL 导出数据时，前端绝对不能直接一次性渲染到 DOM 中：

- **数据阈值截断**：超过 20KB 的输出内容，在界面仅展示前 500 个字符的预览，并提供“下载完整结果 (.json)”按钮。
- **XSS 防护**：工具返回的内容必须强制作为纯文本处理（使用 `textContent` 或纯文本 `pre` 标签），严禁使用 `dangerouslySetInnerHTML`。用户输入与外部网络结果都可能包含恶意的 Prompt 注入指令或挂马脚本。

---

## 权威参考与技术演进

- **Model Context Protocol (MCP)**：Anthropic 提出的 MCP 规范将工具与上下文解耦，定义了标准的工具调用、进度反馈（Progress Reporting）以及结果通知模式，为时间线提供了统一的协议基础。
- **Vercel AI SDK Core Tool Invocation**：现代 AI 框架在流式通道中直接传递 `tool-call` 与 `tool-result` 块，前端时间线直接消费该数据流即可实现无缝同步。

## 结语

工具调用时间线不是技术调试面板的简单搬运，而是人机协同过程中的“透明度中枢”。

通过清晰的状态抽象、可感知的动态耗时、同类聚类和局部重试机制，复杂且不可预测的 Agent 思考链路得以被驯化成可被人类理解、审查和纠错的可视化轨迹。
