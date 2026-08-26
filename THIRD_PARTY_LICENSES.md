# 第三方组件与许可

记忆花园 · Mneme Atrium 本身以 [AGPL-3.0](LICENSE) 发布。下列第三方组件随 app 一起分发或在构建时链入，各自保留其原许可证；版权声明与许可证文本随各组件源码/包一同保留。核对日期 2026-08-26（以当时 `project.yml` 与 SPM 锁定版本为准）。

## Swift Package（静态链入 app）

| 组件 | 用途 | 许可 |
|---|---|---|
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown 渲染（macOS） | MIT |
| [NetworkImage](https://github.com/gonzalezreal/NetworkImage)（swift-markdown-ui 依赖） | 图片加载 | MIT |
| [swift-cmark](https://github.com/swiftlang/swift-cmark)（swift-markdown-ui 依赖） | CommonMark 解析 | BSD-2-Clause（含部分 MIT 文件，见其 COPYING） |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | Markdown 语法树 | Apache-2.0 |
| [Grape](https://github.com/swiftgraphs/Grape) | 记忆图可视化 | MIT |
| [VariableBlur](https://github.com/nikstar/VariableBlur) | 渐变模糊 | MIT |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 备份/导入的 zip 读写 | MIT |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 终端视图（含 xterm.js 派生代码） | MIT |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML 解析 | MIT |
| [HighlightSwift](https://github.com/appstefan/HighlightSwift) | 代码高亮 | MIT |
| [iosMath](https://github.com/kostub/iosMath) | 数学公式渲染 | MIT |
| SwiftStreamingMarkdown（本地 fork，上游 Microsoft） | iOS 流式 Markdown | MIT |

仅测试/构建期用到、不进产品二进制的传递依赖（swift-argument-parser、swift-custom-dump、swift-snapshot-testing、swift-syntax、xctest-dynamic-overlay）均为 Apache-2.0 / MIT。

## 打进 bundle 的脚本与资源

| 组件 | 用途 | 许可 |
|---|---|---|
| [CodeMirror 6](https://codemirror.net)（`codemirror.bundle.js`：@codemirror/state·view·language·search·lang-markdown、@lezer/highlight，esbuild 打包） | 文件库 Markdown 编辑器 | MIT |
| [Readability.js](https://github.com/mozilla/readability)（`readability.min.js`，Arc90 / Mozilla） | 网页正文抽取 | Apache-2.0 |
| [Turndown](https://github.com/mixmark-io/turndown)（`turndown.min.js`） | HTML → Markdown | MIT |
| [霞鹜文楷 LXGW WenKai](https://github.com/lxgw/LxgwWenKai) | 界面/正文字体 | SIL OFL 1.1 |
| [思源宋体 Source Han Serif](https://github.com/adobe-fonts/source-han-serif) | 正文字体 | SIL OFL 1.1 |
| [Silkscreen](https://github.com/googlefonts/silkscreen) | 像素风顶栏字体 | SIL OFL 1.1 |
| [ECDICT](https://github.com/skywind3000/ECDICT)（`ecdict_subset.json` 子集） | 单词释义 | MIT |

`ielts_wordlist.txt` 与 `vocab-corpus/` 生词语料为项目自建/整理，来源若含第三方词表将在此补注。

## cc-bridge（随 macOS 版打包的 Mac 端桥接进程）

见 [`cc-bridge/ATTRIBUTION.md`](https://github.com/replica882/mneme-atrium)（随 app 一起放在 `Contents/Resources/cc-bridge/`）：Bun（MIT）、@modelcontextprotocol/sdk（MIT）、ws（MIT）、pi（@earendil-works）；tmux 与 Claude Code CLI 不随 app 分发，按用户本机已装为准。

## 计划中（尚未随 app 分发）

| 组件 | 用途 | 许可 |
|---|---|---|
| [iSH](https://github.com/ish-app/ish) 的 ARM64 fork [OpenMinis/ish-arm64](https://github.com/OpenMinis/ish-arm64) | iOS 离线沙箱内核（用户态 Linux） | GPL-3.0（`0e3a4144` 之后的贡献额外 GPL-2.0），附 `LICENSE.IOS` App Store 分发豁免声明 |
| Alpine Linux minirootfs（aarch64） | 沙箱根文件系统 | 各软件包自身许可的聚合（musl MIT、BusyBox GPL-2.0 等） |

嵌入 iSH 后整个 app 二进制按 GPL-3.0 兼容方式分发（AGPL-3.0 与 GPL-3.0 互相兼容，见 GPL-3.0 §13）；这也是本项目 2026-08-26 去掉 Commons Clause 附加条款的原因——GPL 系许可证不允许对被授予的权利施加进一步限制。
