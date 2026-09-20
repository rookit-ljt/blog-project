---
author: 李金涛
pubDatetime: 2026-07-29T10:00:00+08:00
title: 我不会直接让 Claude Code 修 Bug，而是先让它还原现场
slug: claude-code-fix-frontend-bugs
featured: false
draft: false
tags: [Claude Code, 前端, Debug, Agent]
description: 建立复现、定位、修改和验证的 Bug 修复闭环，避免 Agent 只改表面症状。
timezone: Asia/Shanghai
---

修复线上 Bug 时，最糟糕的做法是直接把控制台的报错截图或堆栈跟踪扔给 AI：“报了这个错，快帮我修一下”。

大语言模型最擅长根据报错做“表面打补丁”（Band-Aid Patching）：给每一个报错属性加上可选链 `?.`、给每个函数套上空的 `try...catch`、或者在页面里塞上乱七八糟的 `setTimeout`。

这种“治标不治本”的修改不仅无法根除隐患，还会把原本会在运行时抛错的异常静默吞掉，让后续调试变得极其痛苦。

高效且安全的做法，是建立**“复现现场 ➔ 根因溯源 ➔ 最小补丁 ➔ 回归锁死”的四步闭环排查法**。

---

## 避开 AI 修 Bug 的“创可贴陷阱”

在让 Claude Code 动代码前，必须警惕以下三类典型的不良修补模式：

```text
❌ 不良修补 1：过度防御可选链
   data?.user?.profile?.address?.city ?? "未知"
   // 根本原因其实是后端接口在特定状态下漏传了 user 实体，前端本应提前展示重试或空状态卡片

❌ 不良修补 2：静默吞噬错误
   try { ... } catch (e) { /* 空处理，仅 console.log */ }
   // 导致状态机死锁在 loading 状态无法自拔

❌ 不良修补 3：暴力延迟打架
   setTimeout(() => { triggerUpdate(); }, 300);
   // 试图用经验延迟解决 React 状态异步更新或 DOM 未就绪问题，在弱网设备上必死无疑
```

---

## 真实案例：排查与修复异步搜索竞态（Race Condition）

我们来看一个前端高频出现的经典 Bug：在文章搜索或分类切换时，用户快速点击“前端”然后立刻点击“Agent”。由于网络延迟的波动，“前端”请求耗时 800ms，“Agent”请求耗时 200ms。后发出的请求先返回，先发出的请求后返回，导致最终页面展示了错误的旧数据。

### 第一步：引导 Agent 还原现场，只读分析

不要让它直接改代码，先让它找出状态流转的破绽：

```text
Bug 现象：在快速切换标签筛选时，列表偶发性展示上一次旧标签的数据。
相关文件：src/components/SearchList.tsx

任务要求：
1. 只读分析代码，解释为什么会出现竞态条件。
2. 说明现有实现缺少了哪些清理或取消机制。
3. 暂时不要修改任何文件，只输出根因分析。
```

Claude Code 会精准指出：组件在 `useEffect` 中直接发起 `fetch`，但未持有 `AbortController`，也没有维护递增的请求序号（Request Token），导致 Promise 无法感知自身是否已经过时。

### 第二步：编写回归测试，红灯锁定现场

在修改代码之前，要求它先写一个必挂的单元测试（Red Test），复现网络延迟倒错的场景：

```text
请为 src/components/SearchList.tsx 编写一个 Vitest 测试用例：
模拟两个并发请求：请求 A (延迟 500ms，返回内容 A) 与请求 B (延迟 100ms，返回内容 B)。
验证在连续触发 A 和 B 后，最终渲染到 DOM 里的必须是内容 B，且内容 A 的结果被成功丢弃或中止。
运行测试并确认其失败（预期红灯）。
```

运行该测试，终端报红，证明我们成功将隐蔽的竞态问题捕获到了测试环境中。

### 第三步：生成最小外科手术式 Diff

此时再授权 Claude Code 进行代码修复：

```text
现在请实现最小改动修复该竞态 Bug：
1. 使用 AbortController 中止已过时的网络请求。
2. 保持现有的 Props 接口与组件公开 API 完全一致。
3. 给出修改 Diff 并运行刚刚编写的回归测试，确保测试通过（绿灯）。
```

Claude Code 生成的精准 Diff 如下：

```tsx
// [!code diff:15]
 export function SearchList({ activeTag }: { activeTag: string }) {
   const [items, setItems] = useState<Post[]>([]);

   useEffect(() => {
+    const controller = new AbortController();
+
     async function fetchPosts() {
       try {
-        const res = await fetch(`/api/posts?tag=${activeTag}`);
+        const res = await fetch(`/api/posts?tag=${activeTag}`, { signal: controller.signal });
         const data = await res.json();
         setItems(data);
       } catch (err) {
+        if ((err as Error).name !== "AbortError") {
           console.error("加载失败", err);
+        }
       }
     }

     fetchPosts();
+    return () => controller.abort();
   }, [activeTag]);
```

此时终端再次运行测试：`PASS src/components/SearchList.test.tsx`，Bug 被彻底斩杀。

---

## 审查 AI 生成修复补丁的“防腐清单”

当 Claude Code 给出修改 Diff 时，工程师必须执行以下人工审查：

1. **类型安全性**：是否为了图省事引入了 `as any` 或 `@ts-ignore`？
2. **生命周期清理**：定时器、事件监听器、`AbortSignal` 是否在卸载函数中被正确注销？
3. **边界与降级**：当请求被主动中止时，是否错误地把 `AbortError` 当作网络故障展示给了用户？
4. **性能影响**：改动是否引起了不必要的组件频繁重渲染（如未记忆的匿名回调）？

---

## 结语

使用 Claude Code 排查 Bug，切忌把它当作“碰运气的算命先生”，而是要把它当作“严谨的法医与外科医生”。

先通过精准提问让它指出病灶，再用可失败的测试用例锁定现场，最后用最小代价的补丁完成根治。具备这种严谨排查意识的工程师，才能真正发挥 AI 辅助工程的最大威力。
