---
author: 李金涛
pubDatetime: 2026-06-04T10:00:00+08:00
title: 当代码之外还有设计稿和工单，Claude Code 怎么拿到上下文
slug: claude-code-mcp-frontend-context
featured: false
tags: [Claude Code, MCP, 前端, Agent]
description: 理解 MCP 如何连接外部数据源，并用它补充前端 Agent 的项目上下文。
timezone: Asia/Shanghai
---

现代前端工程师的开发上下文，从来就不只存在于本地的 `src/` 文件夹里。

设计稿和组件规范在 **Figma**；产品需求与验收标准（Acceptance Criteria）在 **Linear** 或 **Jira**；接口契约在 **Swagger / Apifox**；业务术语定义在 **Notion**。

在过去，开发者不得不在这几个网页和终端之间来回反复横跳：复制几段 JSON、截图几张标注、手动粘贴需求描述。这种“人肉上下文搬运工”的模式不仅费时费力，还极易丢失边界信息。

**Model Context Protocol (MCP)** 的出现，从根本上改变了这一现状。它是 Anthropic 主导的一套开放协议标准，让 Claude Code 能够直接通过标准接口，与设计工具、工单系统和私有知识库实时对话。

---

## MCP 的核心架构：解耦工具与模型

MCP 在客户端（Claude Code）与外部服务之间建立了一个基于 JSON-RPC 2.0 的通用通信层：

```text
┌──────────────────────────────────────────────────────────┐
│                   Claude Code (MCP Client)               │
└──────────────────────────────────────────────────────────┘
                             │ (JSON-RPC over stdio / SSE)
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Figma MCP   │     │  Linear MCP  │     │ Custom Docs  │
│    Server    │     │    Server    │     │    Server    │
└──────────────際に   └──────────────┘     └──────────────┘
        │                    │                    │
   读取设计Token         拉取工单与验收标准     查询内部私有契约
```

通过 MCP，Claude Code 在启动时会自动注册这些外部能力，并在需要时像调用本地 `bash` 一样，自主发起对外部系统的结构化查询。

---

## 在 Claude Code 中配置与管理 MCP 服务

Claude Code 提供了原生命令来管理 MCP 连接。配置可以存在全局（`~/.claude/mcp.json`）或保存在具体项目（`.claude/mcp.json`）中。

### 1. 配置标准 MCP 服务示例

在项目根目录创建 `.claude/mcp.json`：

```json
{
  "mcpServers": {
    "linear": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-linear"],
      "env": {
        "LINEAR_API_KEY": "lin_api_xxxxxx"
      }
    },
    "filesystem-docs": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/Users/jt-lee/Desktop/company-specs"
      ]
    }
  }
}
```

### 2. 验证 MCP 状态

在终端中执行：

```bash
claude mcp list
```

终端会列出当前激活的 MCP 服务名称、可用 Tools 以及状态指示灯。

---

## 前端实战一：从 Linear 工单直达功能实现

当接手一个 Bug 修复或功能需求时，不再需要开发者在提示词里长篇大论地转述需求：

```text
> 目标：实现 Linear 工单 ENG-1048 对应的博文分享弹窗。
操作指引：
1. 调用 linear 工具获取 ENG-1048 的详细描述与验收标准（Acceptance Criteria）。
2. 只读检索项目现有组件库，查看是否有可复用的 Modal 组件。
3. 按照工单中列出的“支持复制链接、Twitter 与微信扫码”三项要求完成实现。
4. 运行 pnpm astro check 验证。
```

Claude Code 会首先调用 `linear.get_issue({ id: "ENG-1048" })`，自动解析出产品经理写下的边界条件与边缘用例，随后精准展开代码编写。这种无损传递上下文的能力，彻底消除了由于口头转述遗漏关键细节引发的返工。

---

## 前端实战二：用 40 行 Node.js 编写私有 API 文档 MCP

很多内部项目的接口文档由于内网隔离，无法使用公网 MCP。我们可以用官方 `@modelcontextprotocol/sdk`，在 10 分钟内写一个只读暴露内部 Swagger/OpenAPI 的微型 MCP Server：

```ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import fs from "node:fs/promises";
import path from "node:path";

const server = new Server(
  { name: "internal-api-docs", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

// 声明对外暴露的工具
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "get_api_schema",
      description: "查询内部微服务的 OpenAPI 接口定义与字段描述",
      inputSchema: {
        type: "object",
        properties: {
          endpoint: {
            type: "string",
            description: "接口路径，如 /api/v1/posts",
          },
        },
        required: ["endpoint"],
      },
    },
  ],
}));

// 处理具体工具执行
server.setRequestHandler(CallToolRequestSchema, async request => {
  if (request.params.name === "get_api_schema") {
    const rawDocs = await fs.readFile(
      path.resolve("./docs/swagger.json"),
      "utf-8"
    );
    const spec = JSON.parse(rawDocs);
    const endpoint = request.params.arguments?.endpoint as string;
    const match = spec.paths?.[endpoint];

    return {
      content: [
        {
          type: "text",
          text: match ? JSON.stringify(match, null, 2) : "未找到该接口契约",
        },
      ],
    };
  }
  throw new Error("Unknown tool");
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

将其注册进 `.claude/mcp.json` 后，Claude Code 就能够随时查阅最新字段规范，写出 100% 契合后端类型的 TypeScript 接口。

---

## 权限最小化与数据安全红线

引入外部上下文时，必须把好安全防线：

1. **只读优先（Read-Only Default）**：对文档库、需求系统默认仅开启 Read 权限。若授予写权限（如允许 Agent 自动修改工单状态或评论），必须强制开启人工确认弹窗。
2. **密钥隔离**：所有 API Key（如 `LINEAR_API_KEY`）必须通过环境变量传入，严禁明文保存在公共代码仓库的配置文件中。
3. **数据脱敏**：若公司内部数据库通过 MCP 接入，务必在 MCP Server 层对用户手机号、身份证、真实密钥等 PII 敏感信息进行正则脱敏，绝不让高危数据流入模型上下文。

---

## 结语

未来的软件工程，比拼的不再是谁敲键盘的速度更快，而是**谁的 Agent 拥有更全面、更精确的工程上下文**。

MCP 打破了代码仓库与外部生产力软件之间的孤岛，让 Claude Code 成为穿透设计、需求、接口与实现的真正复合型数字化工程师。
