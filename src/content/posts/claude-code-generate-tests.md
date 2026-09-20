---
author: 李金涛
pubDatetime: 2026-07-16T10:00:00+08:00
title: 让 Claude Code 补测试之前，先把“应该测什么”说清楚
slug: claude-code-generate-tests
featured: false
tags: [Claude Code, 前端, 测试, Agent]
description: 使用 Claude Code 为前端函数补充测试，并识别生成测试中的常见陷阱。
timezone: Asia/Shanghai
---

在日常研发中，很多团队会尝试让 AI“把测试覆盖率刷到 80%”。

如果你只是简单对 Claude Code 说一句“给这个文件补充单测”，你通常会收获一堆看似很绿、实则极其脆弱的“伪测试”（Tautological Tests）：它们过度 Mock 了所有内部函数，导致断言的只是 Mock 本身；或者它们死板地锁定了内部私有变量名，代码稍微重构一下测试就全部报红。

**测试代码的生成可以交给 Agent，但测试契约的设计必须由工程师牢牢把控。**

真正高质量的测试生成，依赖于一套清晰的**行为驱动提示法（Behavior-Driven Prompting, BDP）**。

---

## 警惕 AI 生成测试的三大“坏味道”

在审查 Agent 编写的测试代码时，先用这面“照妖镜”扫一遍：

```text
❌ 坏味道 1：过度 Mock，测了个寂寞
   // 把所有的辅助函数、工具库全 Mock 掉，最后只验证了 mockFn 是否被调用了一次
   expect(mockHelper).toHaveBeenCalledWith("foo");

❌ 坏味道 2：侵入内部实现细节
   // 测试断言了组件内部 state 的命名或私有方法，阻碍了后续任何合理的代码重构
   expect(instance.state._internalCounter).toBe(1);

❌ 坏味道 3：巨型快照污染
   // 遇到复杂结构直接 expect(result).toMatchSnapshot()
   // 几百行的快照无人细看，上线发生回归也直接更新快照蒙混过关
```

---

## 行为驱动提示法（BDP）实战

让 Claude Code 编写高价值测试，核心是将需求拆解为**“输入边界矩阵 + 业务不变式 + 异常契约”**。

以本博客系统中博文过滤与排序的工具函数 `src/utils/postFilter.ts` 为例，我们给出如下严谨的提示：

```text
请为 src/utils/postFilter.ts 编写 Vitest 单元测试。
请先阅读该文件的实现，遵循以下测试契约，不要编写快照测试：

【输入边界矩阵】
1. 空数组输入：返回空数组，不抛出异常。
2. 包含草稿文章：当 draft: true 时，生产环境下必须被过滤剔除。
3. 未到发布时间：pubDatetime 晚于当前系统时间的文章必须被过滤（未来文章暂不发布）。
4. 混合排序：发布时间不同的文章，必须严格按照 pubDatetime 降序（最新在前）排列。
5. 脏数据容错：如果文章缺少 pubDatetime 或为非法 Date 字符串，能够优雅降级排在最后，不能崩溃。

【执行要求】
- 遵循 Arrange-Act-Assert (AAA) 结构。
- 编写完成后在终端执行测试，确保全部通过。
```

---

## 生成的工业级单测代码

Claude Code 根据上述契约生成的测试代码结构清晰、断言精准：

```ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { filterAndSortPosts } from "./postFilter";
import type { CollectionEntry } from "astro:content";

// 构造模拟文章数据的 Factory 函数
function createMockPost(
  overrides: Partial<CollectionEntry<"posts">["data"]> = {}
): CollectionEntry<"posts"> {
  return {
    id: `post-${Math.random()}`,
    slug: "mock-slug",
    body: "Mock content",
    collection: "posts",
    data: {
      title: "测试文章",
      pubDatetime: new Date("2026-01-01T00:00:00Z"),
      description: "描述文本",
      tags: ["前端"],
      draft: false,
      ...overrides,
    },
  } as CollectionEntry<"posts">;
}

describe("postFilter / filterAndSortPosts", () => {
  beforeEach(() => {
    // 锁定系统时间至 2026-06-01，消除动态时间对未来文章判断的副作用
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-01T00:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("当输入为空数组时应返回空列表", () => {
    const result = filterAndSortPosts([]);
    expect(result).toEqual([]);
  });

  it("应正确过滤掉标记为 draft 的草稿博文", () => {
    const postNormal = createMockPost({ title: "正式发布", draft: false });
    const postDraft = createMockPost({ title: "草稿暂存", draft: true });

    const result = filterAndSortPosts([postNormal, postDraft]);
    expect(result.length).toBe(1);
    expect(result[0].data.title).toBe("正式发布");
  });

  it("应过滤掉 pubDatetime 晚于当前时间的未来预定文章", () => {
    const pastPost = createMockPost({
      title: "已过时间",
      pubDatetime: new Date("2026-05-01"),
    });
    const futurePost = createMockPost({
      title: "未来发布",
      pubDatetime: new Date("2026-07-01"),
    });

    const result = filterAndSortPosts([pastPost, futurePost]);
    expect(result.length).toBe(1);
    expect(result[0].data.title).toBe("已过时间");
  });

  it("多篇有效文章应按发布时间严格降序排列", () => {
    const p1 = createMockPost({
      title: "文章 1 月",
      pubDatetime: new Date("2026-01-10"),
    });
    const p2 = createMockPost({
      title: "文章 3 月",
      pubDatetime: new Date("2026-03-15"),
    });
    const p3 = createMockPost({
      title: "文章 2 月",
      pubDatetime: new Date("2026-02-20"),
    });

    const result = filterAndSortPosts([p1, p2, p3]);
    expect(result.map(p => p.data.title)).toEqual([
      "文章 3 月",
      "文章 2 月",
      "文章 1 月",
    ]);
  });
});
```

---

## 建立“执行—失败—自愈”的闭环

在执行测试时，如果由于时区偏移或边界条件出现了测试失败，**严禁为了变绿而让 Agent 去降低测试断言的严格度**。

正确的闭环指令：

```text
测试运行失败：请先仔细阅读 Vitest 抛出的具体报错信息。
判断失败原因属于哪一类：
A. 业务实现存在未考虑的时区偏移 Bug；
B. 测试用例中的 Mock 数据不符合真实类型定义。
如属于 A，请修改业务源码并说明原因；如属于 B，请修正测试准备数据。
严禁删除测试用例或降低断言要求！
```

通过把红线明确在前，Claude Code 会在终端内反复调试并自我修正，直至业务实现与测试断言达成完全一致。

---

## 结语

写单元测试不是为了取悦静态分析工具或应付代码覆盖率报表。

测试的本质是对软件行为的不变式承诺。把“测什么、输入边界是什么、怎么判定成功”讲得清清楚楚，再让 Claude Code 去完成机械性的样板编写和断言校验，你就能在极短时间内为前端关键业务建立起坚不可摧的回归安全网。
