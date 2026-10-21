---
author: 李金涛
pubDatetime: 2026-10-21T10:55:00+08:00
title: 告别上下文腐化：Deep Agents 如何用上下文工程实现“轻量记忆”
slug: deep-agents-context-engineering-memory
featured: true
draft: false
tags:
  - Agent
  - 上下文工程
  - Deep Agents
  - 架构
  - 内存机制
  - LangChain
description: 深度解析 LangChain 最新的 Deep Agents 上下文工程实践：通过 Offloading、可恢复摘要、渐进式技能揭示、子智能体隔离与基于文件的长效记忆，彻底解决长任务中的 Context Rot 问题。
timezone: Asia/Shanghai
---

如果你曾在期末考试前通宵死记硬背，一定体验过这种感觉：**随着塞进大脑的考点越来越多，前面刚复习过的内容反而开始迅速模糊**。

在大语言模型与自主智能体（Agent）的实际工程落地中，LLM 同样面临一模一样的困扰。在长链路任务中，随着指令、中间推理历史、海量工具返回（Tool Results）以及用户修改意见的持续累加，模型的上下文窗口被迅速占满。

在 Agent 工程领域，这种现象被称为 **上下文腐化（Context Rot）**：**模型携带的历史、噪声与无用工具数据越多，它的推理精准度、指令遵循能力与准确率就会出现断崖式下跌**。

近期，LangChain 在官方深度长文《Context Engineering with Deep Agents: How To Remember Without Keeping Everything In Context》中，系统性阐述了其开源 Agent 脚手架 **Deep Agents** 在上下文工程（Context Engineering）上的架构解法。

本文将深入剖析其核心设计模式，探讨如何在不让上下文爆炸的前提下，构建具备持久记忆与长任务规划能力的可靠 Agent。

---

## 一、 什么是上下文工程？从“全部塞入”到“动态调度”

从本质上讲：**一个 Agent 就是一个大语言模型（Model）套上一层脚手架（Harness）**。

面对 Context Rot，许多初学者的第一反应是：“换一个支持 1M 或 2M 超长上下文的模型不就行了？”
但在生产实战中，超长上下文从来不是免费的午餐：
1. **注意力分散（Needle In A Haystack 衰减）**：即使模型能处理 1M tokens，随着上下文噪声增加，注意力机制被高度稀释，漏掉关键指令的概率急剧攀升；
2. **延迟与成本激增**：每多带 10 万 tokens 进行一次思考，首字延迟（TTFT）和每轮 API 账单都在成倍飙升。

因此，**上下文工程（Context Engineering）的核心哲学在于：只在合适的时间，将最合适的上下文递给模型**。

它主要划分为两个作战方向：
- **前置拦截（Keep it out）**：阻止非必要的冗余信息进入活跃上下文窗口；
- **动态治理（Manage & filter inside）**：对窗口内已经存在的内容进行治理、分层沉淀与有损/无损压缩。

```mermaid
flowchart TD
    subgraph Harness["Deep Agents 上下文治理脚手架 (Middleware 架构)"]
        RawTool["外部工具大输出 (>20k tokens)"] -->|1. Offloading 截断外置| FileStorage[("磁盘文件系统<br/>/large_tool_results/")]
        RawTool -->|只保留 Preview + 指针| ActiveContext["活跃上下文窗口 (Active Window)"]

        SubTask["高噪声调研任务"] -->|2. Subagent 独立窗口隔离| SubAgent["子智能体 Subagent<br/>(独立执行，消耗廉价模型)"]
        SubAgent -->|只返回提炼结论| ActiveContext

        SkillsRepo["技能仓库 (SKILL.md)"] -->|3. Progressive Disclosure| SkillMenu["System Prompt: 技能菜单 (单行描述)"]
        SkillMenu --> ActiveContext
        ActiveContext -.->|按需主动读取完整实现| SkillsRepo

        ActiveContext -->|4. 水位线检测 (>85%)| Summarizer["滚动可恢复摘要 (Summarization)"]
        Summarizer -->|历史消息沉淀| SessionHistory[("会话归档<br/>/conversation_history/")]
        Summarizer -->|注入 Summary + 最近几轮消息| ActiveContext

        UserPref["用户偏好 / 长期教训"] -->|5. 文件长效记忆| MarkdownMemory[("Markdown 文件<br/>/memories/AGENTS.md")]
        MarkdownMemory -->|每次启动注入| ActiveContext
    end
```

---

## 二、 核心机制实现：洋葱模型与 Middleware 中间件

在 Deep Agents 中，所有的上下文治理策略并不是散落写死在业务代码里的，而是依托于 **Middleware（中间件）** 架构。

一个 Agent 的核心驱动本质是一个循环：
$$\text{模型决策} \longrightarrow \text{调用工具} \longrightarrow \text{获取结果} \longrightarrow \text{再推理}$$

Deep Agents 允许在模型的每次调用前后、工具调用执行前后插入拦截逻辑。正是通过这套洋葱结构，实现了以下五项上下文工程武器。

---

## 三、 Deep Agents 的五大上下文治理武器

### 1. Offloading：外置大对象，拒绝有损截断

在调用查询接口（如检索财报、拉取数万行日志）时，工具返回的数据极其庞大。但实际上，Agent 本轮决策往往只需要其中的一两项核心指标。

传统做法要么全部放进 Prompt 导致窗口爆掉，要么直接暴力 `slice(0, 1000)` 截断。**暴力截断是有损的，一旦截掉了关键信息，后续决策就会彻底失败。**

Deep Agents 的 `FilesystemMiddleware` 提供了优雅的**指针式外置（Offloading）**：
- 当工具返回值超过阈值（如 **20,000 tokens**）时，脚手架在结果进入对话前，自动将其完整写入底层文件系统的 `/large_tool_results/{tool_call_id}`；
- 传递给模型上下文的，只有该文件的**前几行、后几行摘要预览，以及一个文件路径指针**；
- 后续如果 Agent 发现需要分析中间的某项特定指标，它可以像工程师一样，主动调用 `read_file` 配合分页/行号去按需检索。

> [!TIP]
> 超长用户输入（例如用户一次性粘贴了长达 50,000 tokens 的客服通话录音）同样会触发该机制，自动存入 `/conversation_history/`，让模型保持清爽。

---

### 2. Recoverable Summarization：可回溯的滚动摘要压缩

即使拦截了巨型工具输出，在数十轮复杂推演后，上下文依然会逼近上限。

Deep Agents 的 `SummarizationMiddleware` 会在每次 LLM 调用前监控 Token 水位：
- 当 Token 消耗达到模型最大上下文的 **85%** 时，自动触发压缩流程；
- 启动一个单独的 LLM 调用，将较早的历史消息压缩为精炼的 Summary；
- **保留最近几轮对话的完整原文字样**，确保最新的上下文细节不会因摘要泛化而失真；
- **关键设计：必须具备可恢复性（Recoverable）**。被摘要丢弃的早期原始消息并不会永久丢失，而是被落盘归档到 `/conversation_history/{session_id}.md`。当模型在后续阶段突然需要追溯“最开始 Company A 的某个细节”时，依然有据可循。

---

### 3. Progressive Disclosure：基于 Skills 的按需渐进式揭示

很多开发者习惯把系统可能用到的全部业务规则、几十种操作流程全部写在 System Prompt 里。
例如：销售团队每个季度才需要格式化一次的“季度业务回顾（QBR）报告模板”，如果常驻在 System Prompt 中，意味着**每一轮调用的每个 Token 都在为此付费，并且干扰其他日常任务的注意力**。

Deep Agents 引入了 **Skills（技能机制）** 与 **渐进式揭示（Progressive Disclosure）**：
1. **技能封装**：每个技能是一个包含 `SKILL.md`（包含使用说明、脚本、参考文档）的独立目录；
2. **菜单注入**：启动时，`SkillsMiddleware` 只解析每个技能的 Header 元数据，在 System Prompt 中只追加类似菜单一样的名称与单行简述；
3. **按需装载**：常驻上下文只需消耗几十个 Token。当且仅当用户提出相关需求、模型判定需要运用该技能时，模型才会主动触发文件读取工具把完整的 `SKILL.md` 装载进当前任务；
4. **效果**：十个专业级复杂技能的常驻上下文开销，仅仅等同于十行简短的菜单文本。

---

### 4. Subagents：为高噪声子任务划定独立上下文边界

有些任务天然就是“高噪声”的。例如：“深入调研某家竞品最近半年的五大产品更新，并阅读相关资讯”。
如果让主 Agent 亲自去执行，十几轮 Google 搜索、翻看网页、纠错过滤产生的上百条无用片段会把主上下文严重污染。

`SubAgentMiddleware` 允许主 Agent 将特定重负荷任务派发给**子智能体（Subagent）**：

```python
market_researcher = {
    "name": "market-researcher",
    "description": "深入调研某公司动态，并返回最值得注意的 3 点结论",
    "system_prompt": "使用 pull_market_report 并抓取资讯，最终返回 3 条核心 Bullet points。严禁直接返回大篇幅原始文本。",
    "tools": [pull_market_report, search_web],
}

agent = create_deep_agent(model=model, subagents=[market_researcher])
```

- **上下文物理隔离**：Subagent 在一个全新且干净的独立上下文窗口中执行繁复的搜集与过滤；
- **极简回传**：最终仅将提炼好的 3 条精炼要点返回给主 Agent，主流程几乎感受不到中间几十轮翻页搜索的 Token 冲击；
- **降本增效**：子任务由于边界清晰，还可以并行派发给更便宜、更快速的模型执行。

---

### 5. File-based Long-term Memory：真正属于你的文件式记忆

记忆不应该被锁在某一家云厂商的专有黑盒数据库里。

Deep Agents 采用最质朴却最坚固的方案：**基于纯 Markdown 文件的长效记忆**（例如 `/memories/AGENTS.md`）：
- **加载与注入**：每次会话启动时，`MemoryMiddleware` 读取该文件，并注入 System Prompt；
- **自适应沉淀**：当用户在对话中表明了习惯与准则（例如“以后生成报告请用无序列表，不要写成大段落”），Agent 会主动在文件末尾追加这条偏好；
- **解耦模型提供商（Provider Agnostic）**：

```python
agent = create_deep_agent(
    model="openai:gpt-6",  # 哪怕下周切换了底层大模型提供商
    memory=["/memories/AGENTS.md"],  # 长期记忆文件与私有存储完好无损
    backend=backend,
    store=store,
)
```

即使底层大模型从 Claude 切换到了 GPT-6 乃至本地私有化部署的模型，由于记忆是一份属于你自己的普通文本文件，新模型读入后依然能完美遵循你以往调教的全部习惯。

---

## 四、 生产落地实践军规

无论是使用 Deep Agents，还是在自主的 LangGraph、AutoGen 架构中构建 Harness，以下五条法则是规避上下文陷阱的核心工程准绳：

| 工程法则 | 核心主张 | 为什么关键 |
| :--- | :--- | :--- |
| **Offload not Truncate** | 外置卸载，而非盲目暴力截断 | 暴力截断是不可逆的有损丢失，外置存储保留了随时回溯的能力 |
| **Recoverable Compaction** | 压缩机制必须可回溯还原 | 摘要丢失细节时，Agent 必须拥有按需捞回历史原始记录的手段 |
| **On-demand Know-how** | 领域专业知识必须按需动态装载 | 将海量规则死塞在 System Prompt 中是 Token 浪费和注意力稀释的根源 |
| **Isolated Noise** | 高噪声探索过程必须划定独立子图 | 保护主 Agent 上下文的纯净度，让核心逻辑始终聚焦在核心目标上 |
| **Owned Memory** | 掌控长期记忆的基础存储所有权 | 采用结构化/文本化存储，避免与单一云端闭源模型强绑定 |

---

## 五、 结语

在构建严肃的工业级 Agent 系统时，“大模型本身的能力”固然决定了系统的智商上限，但**脚手架（Harness）对上下文的工程调度能力，才真正决定了 Agent 在复杂长任务中能否稳定着陆**。

通过 Offloading、可逆摘要、技能揭示、子图隔离与文件记忆，Deep Agents 为我们展示了一套极为成熟的上下文工程范式。未来的 Agent 开发，必将从粗放式的“堆砌 Prompt”全面转向精细化的“上下文分层流转”。
