<h1 align="center">Marginalia · 页边集</h1>

<p align="center">一本长在页边的单词手帐 — 拟物手账 UI × SM-2 间隔复习 × AI 词源考古</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-8EBD9F?style=flat-square" alt="MIT">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B%20%7C%20macOS%2014%2B-333?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/SwiftUI-SPM-E7EEEC?style=flat-square" alt="SPM">
</p>

---

Marginalia 是[记忆花园](https://github.com/replica882/mneme-atrium)里的单词学习模块，现在单独拎出来当小甜品开源。名字取自 *marginalia*——书页边缘的批注，学词这件事本来就发生在页边。

## 它长什么样

一本活页手帐：薄荷格线、玫瑰边线、上下撕孔、和纸胶带、星星贴纸、像素蕾丝桌面。词写在格线上，复习卡是贴在纸上的索引卡，释义盖着一条灰色波点胶带——**tap to peel**。

> 设计过程：三张参考图 → design-dna 三维提取 → HTML 草稿六轮迭代 → SwiftUI 落地。
> 草稿就在 [`mockup/index.html`](mockup/index.html)——如果你的技术栈是 PWA 而不是原生，从它开始。

## 里面有什么

- **刷词**（words）：先猜后看的高频扫词，认识/反应慢/不认识三档，键盘 1/2/3/Space/N
- **复习**（review）：SM-2 间隔复习，题型随熟悉度爬坡（认读 → 拼写挖空 → 造句），每日新卡配额 + 每日总量上限 + congratulations 完成页
- **生词本**（notebook）：活页词表、双链笔记（`[[词]]` 跳词卡）、照片附件、tag 分组滤条
- **统计**（stats）：手写风统计、缺口热力表
- **内嵌词典**：ECDICT 26k 词子集（音标/中文释义/词形），系统词典与发音兜底
- **词形归一**：划 "switched" 收进来的是 "switch"（ECDICT 词形反查 + 系统 lemmatizer，歧义白名单保护 left/found）
- **AI 词源考古**：`scripts/vocab-daily.ts`——每晚用你自己的 Claude 给词表续写词源随笔（500+ 篇预置语料随包附带）
- **JournalKit**：以上所有手账视觉（纸页/书签 tab/胶带/贴纸/像素图标/蕾丝）是独立零依赖库，可单独引用

## 快速接入

```swift
// Package.swift
.package(url: "https://github.com/replica882/mneme-atrium", branch: "main")
// targets: "Marginalia"（全套）或只要视觉 "JournalKit"
```

```swift
import Marginalia
import SwiftData

MarginaliaPanel()
    .modelContainer(for: VocabProgress.self)
```

### 可选桥（VocabBridge）

模块自身闭环完整。宿主接了桥，对应入口才出现：

```swift
var bridge = VocabBridge()
bridge.askAI = { word, prompt in /* 交给你的对话管线 */ true }
bridge.openChatSource = { nodeId, flashWord in /* 跳回你的消息 */ }
bridge.openBookSource = { book, chapter, offset in /* 跳回你的阅读器 */ }
bridge.requestArcheology = { word in /* 交给你的生成管线 */ true }
bridge.gradeSentence = { system, user in /* 你的 LLM，返回 JSON 文本 */ nil }

MarginaliaPanel(bridge: bridge)
```

## 完整版在花园里

这个模块真正好用的部分，是它和日常聊天、阅读长在一起：聊天气泡和 AI 思考链里划词即收（出处可跳回原句原文并高亮闪词）、阅读器划词带出处跳回书页、AI 回答自动回填词卡注解、考古按钮实时回投。这些耦合层不在本包里——在[记忆花园](https://github.com/replica882/mneme-atrium)完整版里。

## 已知局限

- 无 Anki 兼容（导入/导出 apkg）
- 学习数据导出仅 JSON
- 无 iCloud 同步
- 语料与词形归一目前只支持英文
- 复习提醒 / 通知未做

## Roadmap（远期愿景）

- **时间感知**：AI 能看到你今天背了没、学了多久——学习数据成为 AI 在场感的一部分
- **对话里随时考你**：聊着天，AI 突然抽查一个你最近学的词
- Anki 互通、多语言词库

## 授权

代码 MIT。数据与素材见 [LICENSES.md](LICENSES.md)（NGSL CC BY-SA 4.0 / ECDICT MIT / Pixelarticons MIT）。
