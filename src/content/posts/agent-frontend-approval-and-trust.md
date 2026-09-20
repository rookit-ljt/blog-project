---
author: 李金涛
pubDatetime: 2026-07-29T10:00:00+08:00
title: Agent 产品的信任感，来自前端的三个确认点
slug: agent-frontend-approval-and-trust
featured: false
draft: false
tags:
  - 前端
  - Agent
  - 产品体验
  - 安全
description: 从来源、权限和结果三个确认点出发，讨论 Agent 前端如何让用户知道系统做了什么并敢于继续使用。
timezone: Asia/Shanghai
---

Agent 产品经常被描述成“自动完成任务”。但自动化程度越高，用户越容易产生悬空感：它依据什么得出这个推论？它刚才以谁的名义调用了外部接口？改完这几行代码或发完这封邮件后，我能不能撤销？

信任感不是在页面上贴一句“AI 生成的内容仅供参考”就能获得的，而是由前端界面持续提供清晰、可核验的确认点。把一次黑盒调用拆解为有据可查、有界可控、有果可验的过程，用户才敢把真实业务交给它。

## 第一个确认点：它参考了什么（来源可核实）

涉及知识库检索、网络搜索或项目工程分析时，模型输出的核心断言必须伴随溯源凭据。直接在正文中用蓝色文字模拟超链接是极其不可靠的，界面应当将模型返回的 Citation 结构化，并提供预览抽屉或悬浮卡片。

### 引用数据结构与前端展示

```ts
export type CitationSource = {
  id: string;
  title: string;
  url?: string;
  excerpt: string;
  sourceType: "file" | "web" | "doc" | "database";
  updatedAt?: string;
  confidenceScore?: number;
};

export type MessageWithCitations = {
  id: string;
  role: "assistant";
  content: string;
  citations: CitationSource[];
};
```

当正文中出现引用标记（如 `[^1]`）时，前端渲染器应将其映射为可交互的引用徽标，并在底部或右侧抽屉展示原文对照：

```tsx
import React, { useState } from "react";

export function CitationSourceList({ sources }: { sources: CitationSource[] }) {
  const [activeId, setActiveId] = useState<string | null>(null);

  if (sources.length === 0) {
    return (
      <div className="mt-2 flex items-center gap-1.5 text-xs text-neutral-400">
        <span className="h-1.5 w-1.5 rounded-full bg-amber-400" />
        当前回答由模型通用知识生成，未检索到特定外部来源
      </div>
    );
  }

  return (
    <div className="mt-3 border-t border-neutral-100 pt-2 dark:border-neutral-800">
      <div className="mb-1.5 flex items-center justify-between text-xs font-medium text-neutral-500">
        <span>参考依据（{sources.length} 处来源）</span>
      </div>
      <div className="flex flex-wrap gap-2">
        {sources.map((source, index) => (
          <button
            key={source.id}
            type="button"
            onClick={() =>
              setActiveId(activeId === source.id ? null : source.id)
            }
            className={`flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs transition-all ${
              activeId === source.id
                ? "border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-700 dark:bg-blue-950/40 dark:text-blue-300"
                : "border-neutral-200 bg-neutral-50 text-neutral-600 hover:border-neutral-300 dark:border-neutral-700 dark:bg-neutral-900 dark:text-neutral-300"
            }`}
          >
            <span className="font-mono text-[10px] opacity-70">
              [{index + 1}]
            </span>
            <span className="max-w-[140px] truncate">{source.title}</span>
          </button>
        ))}
      </div>

      {activeId && (
        <div className="animate-fadeIn mt-2.5 rounded-lg border border-neutral-200 bg-neutral-50 p-3 text-xs dark:border-neutral-800 dark:bg-neutral-900">
          {(() => {
            const current = sources.find(s => s.id === activeId);
            if (!current) return null;
            return (
              <>
                <div className="mb-1 flex items-center justify-between font-medium text-neutral-500">
                  <span className="capitalize">
                    来源类型: {current.sourceType}
                  </span>
                  {current.updatedAt && (
                    <span>更新时间: {current.updatedAt}</span>
                  )}
                </div>
                <blockquote className="my-1.5 rounded border-l-2 border-blue-500 bg-white p-2 pl-2 text-neutral-700 italic dark:bg-neutral-950 dark:text-neutral-300">
                  “{current.excerpt}”
                </blockquote>
                {current.url && (
                  <a
                    href={current.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="mt-1 flex items-center gap-1 text-blue-600 hover:underline dark:text-blue-400"
                  >
                    查看原文 ↗
                  </a>
                )}
              </>
            );
          })()}
        </div>
      )}
    </div>
  );
}
```

没有可靠来源时，明确显示“未找到可验证来源”，好过渲染一段假链接。前端的职责不是替模型掩盖无据推论，而是把事实依据暴露在阳光下。

---

## 第二个确认点：它准备以谁的身份做什么（动作与权限预审）

绝大部分自动化故障发生在“产生副作用”的瞬间：向生产环境推送代码、给外部客户发邮件、直接修改数据库记录。只读查询与修改操作有着本质不同的风险等级。

前端应当把抽象的模型函数调用（`tool_call`）转换成具备明确语义的审批卡片，并在关键操作发生前阻断执行流程。

### 风险分级与审批卡片实现

```tsx
export type RiskLevel = "low" | "medium" | "high" | "destructive";

export type ApprovalRequest = {
  callId: string;
  actionName: string;
  riskLevel: RiskLevel;
  summary: string;
  targetResource: string;
  diffPayload?: {
    filename: string;
    additions: number;
    deletions: number;
    preview: string;
  };
  expiresAt: number;
};

export function ActionApprovalCard({
  request,
  onApprove,
  onReject,
}: {
  request: ApprovalRequest;
  onApprove: (callId: string) => void;
  onReject: (callId: string, reason: string) => void;
}) {
  const [rejectReason, setRejectReason] = useState("");
  const [showRejectInput, setShowRejectInput] = useState(false);

  const riskBadgeStyles: Record<RiskLevel, string> = {
    low: "bg-emerald-50 text-emerald-700 border-emerald-200",
    medium: "bg-amber-50 text-amber-700 border-amber-200",
    high: "bg-orange-50 text-orange-700 border-orange-200",
    destructive: "bg-rose-50 text-rose-700 border-rose-200 font-semibold",
  };

  return (
    <div className="my-3 rounded-xl border-2 border-amber-300 bg-amber-50/30 p-4 dark:border-amber-700 dark:bg-amber-950/20">
      <div className="mb-2 flex items-start justify-between gap-2">
        <div className="flex items-center gap-2">
          <span className="text-lg">🛡️</span>
          <div>
            <h4 className="text-sm font-bold text-neutral-900 dark:text-neutral-100">
              需要操作授权：{request.actionName}
            </h4>
            <p className="text-xs text-neutral-500">
              目标资源：{request.targetResource}
            </p>
          </div>
        </div>
        <span
          className={`rounded-full border px-2 py-0.5 text-[11px] ${riskBadgeStyles[request.riskLevel]}`}
        >
          {request.riskLevel.toUpperCase()}
        </span>
      </div>

      <p className="mb-3 text-xs text-neutral-700 dark:text-neutral-300">
        {request.summary}
      </p>

      {request.diffPayload && (
        <div className="mb-3 overflow-x-auto rounded-lg bg-neutral-900 p-3 font-mono text-xs text-neutral-200">
          <div className="mb-2 flex justify-between border-b border-neutral-700 pb-1 text-[11px] text-neutral-400">
            <span>{request.diffPayload.filename}</span>
            <span>
              <span className="text-emerald-400">
                +{request.diffPayload.additions}
              </span>{" "}
              <span className="text-rose-400">
                -{request.diffPayload.deletions}
              </span>
            </span>
          </div>
          <pre className="whitespace-pre">{request.diffPayload.preview}</pre>
        </div>
      )}

      {showRejectInput ? (
        <div className="mt-2 flex items-center gap-2">
          <input
            type="text"
            placeholder="说明拒绝或修改原因（可选）..."
            value={rejectReason}
            onChange={e => setRejectReason(e.target.value)}
            className="flex-1 rounded-md border border-neutral-300 bg-white px-2.5 py-1.5 text-xs dark:border-neutral-700 dark:bg-neutral-900"
          />
          <button
            type="button"
            onClick={() => onReject(request.callId, rejectReason)}
            className="rounded-md bg-rose-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-rose-700"
          >
            确认拒绝
          </button>
          <button
            type="button"
            onClick={() => setShowRejectInput(false)}
            className="px-2 py-1.5 text-xs text-neutral-500 hover:text-neutral-700"
          >
            取消
          </button>
        </div>
      ) : (
        <div className="flex items-center justify-end gap-2.5 pt-1">
          <button
            type="button"
            onClick={() => setShowRejectInput(true)}
            className="rounded-md px-3 py-1.5 text-xs font-medium text-neutral-600 transition-colors hover:bg-neutral-100 dark:text-neutral-400 dark:hover:bg-neutral-800"
          >
            拒绝 / 修改指示
          </button>
          <button
            type="button"
            onClick={() => onApprove(request.callId)}
            className="flex items-center gap-1.5 rounded-md bg-blue-600 px-4 py-1.5 text-xs font-medium text-white shadow-sm transition-all hover:bg-blue-700"
          >
            <span>批准执行</span>
          </button>
        </div>
      )}
    </div>
  );
}
```

确认按钮文案一定要精准：“批准修改 3 个文件”、“发送邮件至 hr@company.com”，绝不能用模糊的“确认”、“好的”、“继续”。只有把操作客体具体化，用户才会认真阅读并审慎授权。

---

## 第三个确认点：它最终交付了什么（交付物与变更核验）

完成一次复杂的 Agent Run 之后，界面绝不能仅留下一行“任务已完成”和一堆无从核实的散落文字。高质量的交付形态，必须包含一份结构化的**成果核验卡片（Delivery Checklist）**。

```tsx
type ChecklistItem = {
  label: string;
  status: "verified" | "warning" | "manual_check_required";
  detail?: string;
};

export function ResultSummaryCard({
  title,
  summary,
  items,
  artifacts,
}: {
  title: string;
  summary: string;
  items: ChecklistItem[];
  artifacts?: { name: string; type: string; downloadUrl: string }[];
}) {
  const iconMap = {
    verified: "✅",
    warning: "⚠️",
    manual_check_required: "🔍",
  };

  return (
    <div className="mt-4 rounded-xl border border-neutral-200 bg-white p-4 shadow-sm dark:border-neutral-800 dark:bg-neutral-900">
      <h3 className="mb-1 text-sm font-semibold text-neutral-900 dark:text-neutral-100">
        {title}
      </h3>
      <p className="mb-3 text-xs text-neutral-600 dark:text-neutral-400">
        {summary}
      </p>

      <div className="space-y-1.5 rounded-lg border border-neutral-100 bg-neutral-50 p-2.5 dark:border-neutral-800 dark:bg-neutral-950">
        {items.map((item, i) => (
          <div key={i} className="flex items-start gap-2 text-xs">
            <span>{iconMap[item.status]}</span>
            <div className="flex-1">
              <span className="font-medium text-neutral-800 dark:text-neutral-200">
                {item.label}
              </span>
              {item.detail && (
                <span className="ml-1.5 text-neutral-500">({item.detail})</span>
              )}
            </div>
          </div>
        ))}
      </div>

      {artifacts && artifacts.length > 0 && (
        <div className="mt-3 flex items-center gap-2 border-t border-neutral-100 pt-3 dark:border-neutral-800">
          <span className="text-xs font-medium text-neutral-500">
            生成产物:
          </span>
          {artifacts.map((art, idx) => (
            <a
              key={idx}
              href={art.downloadUrl}
              className="flex items-center gap-1 rounded bg-neutral-100 px-2 py-1 text-xs text-neutral-700 hover:bg-neutral-200 dark:bg-neutral-800 dark:text-neutral-300"
            >
              📄 {art.name}
            </a>
          ))}
        </div>
      )}
    </div>
  );
}
```

这份核验清单把“哪些通过了自动化校验”、“哪些存在未捕获的风险”、“哪些必须由人工最终确认”清晰隔开。这赋予了用户明确的边界感——他们知道自己还需要对什么负责。

---

## 不要把安全边界托付给前端代码

前端组件负责展示与收集决策，但**真正的权限防线永远在服务端**：

1. **防重放与一次性审批令牌（One-Time Approval Token）**：前端点击“批准执行”时，发送的不能是简单的布尔值 `{ approved: true }`，而必须携带服务端签发的包含 `callId`、`riskHash` 和过期时间的短期签名 Token。服务端校验 Token 且只允许消费一次。
2. **服务端鉴权再核实（Re-Authorization）**：即使用户在界面上点了批准，服务端在真正调用底层执行器时，必须重新确认当前 Session 用户的 RBAC/ABAC 权限，确保其有权操作目标分支或生产资源。
3. **内容安全沙箱（Sanitized Output）**：模型输出的 Markdown 包含的外链链接必须强制添加 `rel="noopener noreferrer nofollow"`；代码块与富文本禁止执行内联脚本，防止 Prompt 注入诱导执行跨站攻击。

---

## 允许回退与分支纠错：Human-in-the-Loop 的闭环

信任不仅来自开始时的授权，更来自发生偏差时的补救能力：

- **单步撤销（Step Rollback）**：如果一个由 5 个工具串联的复合任务在第 4 步执行错误，界面应允许用户回退到第 3 步重新输入修正指令，而不是强制推倒全部会话重新来过。
- **状态快照持久化**：每次工具执行和确认事件，都应记录包含 `runId`、`stepIndex`、`timestamp` 的不可变快照。即使页面意外刷新或网络短暂中断，前端仍能从服务端拉取当前的挂起状态，恢复待审批卡片。

---

## 权威参考与演进方向

在近期的技术发展中，AI 工作流编排正在全面拥抱人类在环（Human-in-the-loop）协议：

- **Vercel AI SDK 7 Tool Approvals**：官方将 `approval` 纳入了一等公民模型协议。支持在模型决定调用高危工具时自动阻断流水线，触发 `execute({ ... }, { approvalRequested: true })`，并在客户端授权后无缝恢复流式传输。
- **OWASP Top 10 for LLM Applications (LLM08: Excessive Agency)**：安全指南明确指出，禁止授予 Agent 过宽的自主执行权，必须在敏感写操作前强制引入带上下文的人工核验环节。

## 结语

Agent 时代的前端工程师，工作重心正在从“如何把文字漂亮地排版在气泡里”，转向“如何建立人机协同的契约与边界”。

来源可核实、动作可预审、成果可核验——把这三个确认点做扎实，Agent 产品才会真正脱离“玩具”的范畴，成为工程师和业务人员日常信赖的生产力搭档。
