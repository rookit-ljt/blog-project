---
author: 李金涛
pubDatetime: 2026-09-08T10:00:00+08:00
title: AI 聊天页面的流式输出：从能显示到好用
slug: llm-streaming-chat-frontend
featured: true
draft: false
tags:
  - 前端
  - LLM
  - Agent
  - TypeScript
description: 从浏览器读取服务端流，完成一个支持 Markdown、停止生成、自动滚动和错误重试的 AI 聊天页面。
timezone: Asia/Shanghai
---

第一次把 LLM 接进页面时，最容易实现的是“点击发送，等接口返回一整段文字”。真正影响体验的，却是等待过程：用户不知道模型是否还在工作，长回答要等很久才出现，代码块也可能在半截 Markdown 上被渲染得一团糟。

这篇文章从前端视角实现一个最小的流式聊天页面。目标不是做一个完整的 ChatGPT 克隆，而是把几个可以迁移到实际项目的交互细节讲清楚：流式读取、增量渲染、停止生成、滚动策略和错误恢复。

## 先理解一次请求发生了什么

页面不应该直接把模型密钥放进浏览器。推荐的调用链是：

```text
浏览器 ── POST /api/chat ──> 自己的服务端 ──> LLM API
浏览器 <─ text/event-stream ── 自己的服务端 <─ 模型增量结果
```

服务端收到完整的对话消息后，向模型 API 发起请求，并把模型生成的片段立即转发给浏览器。浏览器每收到一个片段，就更新当前消息的内容。

流式传输通常使用 Server-Sent Events（SSE）或普通的 HTTP chunk。两者的共同点是：响应不会一次性结束，客户端必须持续读取 `ReadableStream`。下面的客户端代码使用普通文本流，因此可以适配大多数后端实现。

## 客户端：读取 ReadableStream

先定义消息类型和一个提交函数。`AbortController` 同时负责取消浏览器请求和释放读取中的流。

```ts
type ChatMessage = {
  role: "user" | "assistant";
  content: string;
};

export async function streamChat(
  messages: ChatMessage[],
  onChunk: (text: string) => void,
  signal?: AbortSignal
) {
  const response = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ messages }),
    signal,
  });

  if (!response.ok || !response.body) {
    throw new Error(`请求失败：${response.status}`);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;

      // stream: true 可以避免一个汉字被拆在两个 chunk 中时出现乱码
      onChunk(decoder.decode(value, { stream: true }));
    }
  } finally {
    reader.releaseLock();
  }
}
```

这里有两个容易遗漏的点。第一，`response.body` 可能为空，必须先检查。第二，`TextDecoder` 要开启 `{ stream: true }`，因为网络分块不保证按照字符边界切割。

## 发送消息时，先插入一个空的助手消息

如果等完整结果返回后再添加助手消息，页面仍然会像普通请求一样卡住。更顺滑的做法是：用户发送后立即插入一条空的助手消息，后续只更新它的 `content`。

```ts
const controller = new AbortController();

async function sendMessage(input: string) {
  const userMessage = { role: "user" as const, content: input };
  const assistantMessage = { role: "assistant" as const, content: "" };
  const nextMessages = [...messages, userMessage, assistantMessage];

  setMessages(nextMessages);
  setIsGenerating(true);

  try {
    await streamChat(
      nextMessages.slice(0, -1),
      chunk => {
        setMessages(current => {
          const copy = [...current];
          const last = copy.length - 1;
          copy[last] = {
            ...copy[last],
            content: copy[last].content + chunk,
          };
          return copy;
        });
      },
      controller.signal
    );
  } catch (error) {
    if ((error as Error).name !== "AbortError") {
      setError("生成失败，请重试");
    }
  } finally {
    setIsGenerating(false);
  }
}
```

实际项目中，状态更新需要保证使用最新的 `current`，否则快速到达的多个 chunk 可能互相覆盖。React 的函数式 `setState` 正是为这种场景准备的。

## Markdown 不能在每个片段上直接“随便拼”

模型输出通常是 Markdown。增量内容可能正好停在代码围栏、链接或粗体标记中间。例如当前片段只有 `````ts`，下一片才是代码正文。如果直接把未完成的 Markdown 当成完整文档处理，渲染器可能频繁改变 DOM，造成闪烁。

一个实用策略是把“原始文本”和“展示内容”分开：原始文本持续累加，展示内容使用 Markdown 渲染器转换；正在生成时可以降低高亮频率，生成结束后再做一次完整高亮。无论使用哪一个 Markdown 库，都要开启 HTML 过滤，避免把模型返回的 HTML 直接插入页面。

```tsx
<article className="prose">
  <MarkdownContent content={message.content} allowHtml={false} />
</article>
```

如果你的产品只需要纯文本，先用 `textContent` 或安全的文本节点显示，等交互稳定后再加入 Markdown，是更容易排查问题的顺序。

## 自动滚动，但不要抢用户的滚动位置

“每个 chunk 都滚到底部”看起来简单，却会让用户无法向上查看前文。可以记录滚动容器与底部的距离，只在用户原本就在底部附近时自动滚动。

```ts
function shouldFollowBottom(element: HTMLElement) {
  const distance =
    element.scrollHeight - element.scrollTop - element.clientHeight;
  return distance < 80;
}

function followBottom(element: HTMLElement) {
  if (shouldFollowBottom(element)) {
    element.scrollTo({ top: element.scrollHeight, behavior: "smooth" });
  }
}
```

当用户主动向上滚动时，显示一个“回到底部”按钮；点击后再恢复跟随。这个小状态比强制滚动更符合阅读习惯。

## 停止、重试和重复提交

停止按钮只需要调用 `controller.abort()`，并把当前已生成的文字保留下来。不要清空它，否则用户无法判断模型已经完成了哪一部分。

```ts
function stopGenerating() {
  controller.abort();
  setIsGenerating(false);
}
```

发送按钮在生成期间应禁用，或者明确提供“停止”操作。请求失败时保留用户消息和已生成内容，给助手消息标记为失败，并提供“重试”按钮。重试时可以携带原始对话，也可以只重试最后一轮，取决于后端是否记录请求 ID。

## 服务端返回格式要稳定

前后端约定一个简单的格式，就能避免客户端到处写兼容逻辑。例如每行一个 JSON 片段：

```text
{"type":"text","value":"你好"}
{"type":"text","value":"，这是"}
{"type":"done"}
```

服务端还应该发送明确的错误事件，并在连接关闭前发送 `done`。生产环境中要设置超时、限制单次输入长度、记录 request id，并在日志中区分“用户主动停止”和“服务端异常”。

## 我会怎样验收这个组件

我不会只测试“能不能显示回答”，而会固定检查这些场景：短回答、长回答、中文被拆分、模型返回 Markdown、网络中断、用户点击停止、用户滚动到历史内容后继续生成，以及连续快速发送两次消息。每个场景都记录首字节时间、完整响应时间和是否出现内容丢失。

## 结语

流式输出的核心代码并不复杂，难点在于把网络状态翻译成用户能理解的界面状态：正在生成、已停止、失败、可重试。前端工程师的优势正是在这里——模型负责生成内容，页面负责让过程可见、可控、可恢复。

下一篇可以在这个聊天页面上继续增加工具调用：让模型查询文章、调用搜索接口，再把每一次工具执行以时间线展示出来。那时，聊天页面就从“回答框”开始接近真正的 Agent 界面。
