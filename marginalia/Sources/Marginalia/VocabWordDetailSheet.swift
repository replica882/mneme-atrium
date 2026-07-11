import SwiftUI
import JournalKit
import SwiftData
import MarkdownUI

/// R3-3：考古请求 in-flight 全局集合（sheet 关了重开不丢"考古中"态；进程内存活即可）。
@MainActor
enum VocabArcheologyTracker {
    static var inFlight: Set<String> = []
}

private struct JumpWord: Identifiable {
    let word: String
    var id: String { word }
}

/// 词详情 sheet（CR-3 P3）：考古笔记 md 渲染 + AI 注解区块。
/// 两块内容独立可缺：aiNote（问{{char}} 回填）在上，考古语料在下；都没有显示空态。
struct VocabWordDetailSheet: View {
    @Environment(\.vocabBridge) private var bridge
    let word: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("assistantName") private var assistantName = "助手"

    @State private var corpus: String? = nil
    @State private var aiNote: String? = nil
    /// R3.4b 内嵌词典条目（ECDICT 子集）。
    @State private var dictEntry: VocabDictStore.Entry? = nil
    /// R3-3 考古按钮：本词考古请求进行中（全局 in-flight 集合的本地镜像）。
    @State private var archeologyRunning = false
    @State private var archeologyHint: String? = nil
    /// R3.4 系统词典 sheet（iOS）。
    @State private var showDictionary = false
    /// 出处跳转打开的来源词详情（嵌套 sheet）。
    @State private var jumpWord: String? = nil
    /// 收词出处原句（anchorText）+ 出处标签（《书》· 第 N 章）。
    @State private var anchorText: String? = nil
    @State private var sourceLabel: String? = nil
    /// 聊天收词的原消息 node（load 时预检存在才设——点出处跳回对话）。
    @State private var chatJumpNodeId: String? = nil
    /// 思考链收词：跳回后要自动弹思考链弹窗并闪词。
    @State private var jumpIsThinking = false
    /// 词详情里收的词：来源词（点出处打开它的词详情，嵌套 sheet 同 [[双链]]）。
    @State private var vocabJumpWord: String? = nil
    /// 词库条目（释义/词形/频段）——custom 词没有。
    @State private var libWord: VocabWord? = nil
    /// tag 分组（雅思 a 话题…）：本词已打 + 全库已有（点选防手滑分裂）。
    @State private var wordTags: [String] = []
    @State private var allTags: [String] = []
    @State private var showTagInput = false
    @State private var tagDraft = ""


    var body: some View {
        NavigationStack {
            // 纸页固定满屏（短词也整张纸、上下撕孔），内容在纸内滚动——
            // 格线/纹理随超高内容伸展会撞纹理上限断线（07-10 事故）
            ZStack {
                PixelLaceBackdrop(sparse: true).ignoresSafeArea()

                ZStack(alignment: .topLeading) {
                    CrumpledPaperPage(marginX: 42, showRules: false)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                    // R3.4b 内嵌词典（ECDICT 子集）优先；词表外的词降级 NGSL 释义/系统词典按钮
                    if let dict = dictEntry {
                        dictBlock(dict)
                    } else if let lw = libWord {
                        definitionBlock(lw)
                    }
                    tagRow
                    if let anchor = anchorText {
                        anchorBlock(anchor)
                    }
                    if let note = aiNote {
                        aiNoteBlock(note)
                    }
                    // 词条笔记（文件库 vocab/<word>.md，复习卡与此处共享同一篇）
                    VocabNoteSection(word: word, tone: Color(hex: 0xFDFDFB))
                    if let corpus {
                        pageOneMarkdown(corpus)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if corpus == nil && aiNote == nil {
                        emptyState
                    }
                    // R3-3：没考古过的词给一键考古（已考古不出按钮，⧫ 已拍）
                    if corpus == nil {
                        archeologyButton
                    }
                }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 30)
                        .padding(.leading, 58)
                        .padding(.trailing, 20)
                        .padding(.bottom, 34)
                        // R8 格线跟字走：格线红线随内容滚动（真本子），分段防纹理上限
                        .background(alignment: .topLeading) {
                            ScrollingRuledBackdrop(marginX: 42, topOffset: 12)
                        }
                    }
                    .clipShape(TornPaperShape())
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .navigationTitle(word)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                    }
                    .foregroundColor(JournalTheme.pencil)
                }
                // R3.4 快速查词：发音 + 系统词典（内置牛津，不用考古那么重）
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        SpeechService.shared.speakWord(word)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .foregroundColor(JournalTheme.pencil)

                    Button {
                        #if os(iOS)
                        showDictionary = true
                        #else
                        VocabQuickLookup.openSystemDictionary(word: word)
                        #endif
                    } label: {
                        Image(systemName: "character.book.closed")
                    }
                    .foregroundColor(JournalTheme.pencil)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showDictionary) {
                DictionarySheet(term: word)
                    .ignoresSafeArea()
            }
            #endif
        }
        .sheet(item: Binding(
            get: { jumpWord.map { JumpWord(word: $0) } },
            set: { if $0 == nil { jumpWord = nil } }
        )) { j in
            VocabWordDetailSheet(word: j.word)
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: VocabCorpusStore.corpusArrivedNotification)) { notif in
            guard notif.userInfo?["word"] as? String == word else { return }
            archeologyRunning = false
            VocabArcheologyTracker.inFlight.remove(word)
            if (notif.userInfo?["ok"] as? Bool) == true {
                archeologyHint = nil
                Task { await load() }
            } else {
                archeologyHint = "考古失败了，稍后再试"
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }

    // MARK: - R3-3 考古按钮（一键 -p，Mac 跑，全文回投即刻可见）

    private var archeologyButton: some View {
        VStack(spacing: 6) {

            Button {
                requestArcheology()
            } label: {
                HStack(spacing: 6) {
                    if archeologyRunning {
                        ProgressView().controlSize(.small)
                        Text("考古中…大约一两分钟")
                    } else {
                        Image(systemName: "scroll")
                        Text("考古这个词")
                    }
                }
                .font(JournalTheme.serifItalic(13.5))
                .foregroundColor(archeologyRunning ? JournalTheme.faint : JournalTheme.amber)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(archeologyRunning)

            if let hint = archeologyHint {
                Text(hint)
                    .font(JournalTheme.serifItalic(12))
                    .foregroundColor(JournalTheme.faint)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            archeologyRunning = VocabArcheologyTracker.inFlight.contains(word)
        }
    }

    private func requestArcheology() {
        guard !archeologyRunning else { return }
        guard let request = bridge.requestArcheology, request(word) else {
            archeologyHint = "宿主未接考古管线（脚本版见 scripts/vocab-daily.ts）"
            return
        }
        archeologyRunning = true
        archeologyHint = nil
        VocabArcheologyTracker.inFlight.insert(word)
    }

    /// 组件库版：MarkdownUI 渲染（完整版在记忆花园里用聊天同款渲染器，带划词收词/划线）。
    @ViewBuilder
    private func pageOneMarkdown(_ md: String) -> some View {
        Markdown(md).markdownTheme(.marginalia)
    }

    /// tag 行：已打 tag = 薄荷小贴纸（点=撤），"+ tag" 弹点选/新建。
    private var tagRow: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(wordTags, id: \.self) { t in
                Button {
                    VocabTagStore.toggle(word: word, tag: t)
                    refreshTags()
                } label: {
                    Text(t)
                        .font(JournalTheme.serif(11.5, .medium))
                        .foregroundColor(JournalTheme.mint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(JournalTheme.mint.opacity(0.13))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(allTags.filter { !wordTags.contains($0) }, id: \.self) { t in
                    Button(t) {
                        VocabTagStore.toggle(word: word, tag: t)
                        refreshTags()
                    }
                }
                Button("新标签…") { showTagInput = true }
            } label: {
                Text("+ tag")
                    .font(JournalTheme.serifItalic(11.5))
                    .foregroundColor(JournalTheme.faint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(JournalTheme.faint.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .alert("新标签", isPresented: $showTagInput) {
            TextField("比如：雅思a话题", text: $tagDraft)
            Button("取消", role: .cancel) { tagDraft = "" }
            Button("加上") {
                VocabTagStore.toggle(word: word, tag: tagDraft)
                tagDraft = ""
                refreshTags()
            }
        }
    }

    private func refreshTags() {
        wordTags = VocabTagStore.tags(word: word)
        allTags = VocabTagStore.allTags()
    }

    private func load() async {
        refreshTags()
        libWord = await VocabLibrary.shared.words.first { $0.word == word }
        dictEntry = VocabDictStore.entry(for: word)
        corpus = VocabCorpusStore.markdown(for: word)
        let w = word
        let desc = FetchDescriptor<VocabProgress>(predicate: #Predicate { $0.word == w })
        guard let progress = (try? modelContext.fetch(desc))?.first else { return }
        if let note = progress.aiNote, !note.isEmpty {
            aiNote = note
        }
        if let anchor = progress.anchorText, !anchor.isEmpty {
            anchorText = anchor
            if let ref = progress.sourceBookRef,
               let parsed = VocabStudyView.parseSourceBookRef(ref) {
                var name = parsed.safe
                sourceLabel = "\(name) · 第 \(parsed.chapter) 章"
            } else if let ref = progress.sourceBookRef,
                      let srcWord = VocabCollector.parseVocabRef(ref) {
                vocabJumpWord = srcWord
                sourceLabel = "考古笔记 · \(srcWord)"
            } else if let ref = progress.sourceBookRef,
                      let nid = VocabCollector.parseThinkingRef(ref) ?? VocabCollector.parseChatRef(ref) {
                // 组件库版：无消息库可预检，接了 openChatSource 桥即可点
                let isThinking = VocabCollector.parseThinkingRef(ref) != nil
                if bridge.openChatSource != nil {
                    chatJumpNodeId = nid
                    jumpIsThinking = isThinking
                    sourceLabel = isThinking ? "思考链 · 点击跳回" : "对话 · 点击跳回"
                } else {
                    sourceLabel = "来自对话"
                }
            }
        }
    }

    /// R3.4b 内嵌词典块：音标 + 中文释义（多行）+ 词形 + 词表信息（有的话）。
    private func dictBlock(_ dict: VocabDictStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let p = dict.p, !p.isEmpty {
                    Text("/\(p)/")
                        .font(JournalTheme.mono(13))
                        .foregroundColor(JournalTheme.pencil)
                }
                Button {
                    SpeechService.shared.speakWord(word)
                } label: {
                    PixelIcon(bitmap: PixelGlyph.speaker, size: 15, color: JournalTheme.pencil)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let t = dict.t, !t.isEmpty {
                Text(t)
                    .font(.system(size: 14.5))
                    .foregroundColor(JournalTheme.ink)
                    .lineSpacing(4)
            }

            let forms = VocabDictStore.forms(from: dict.x)
            if !forms.isEmpty {
                Text(forms.joined(separator: "  ·  "))
                    .font(JournalTheme.serifItalic(12))
                    .foregroundColor(JournalTheme.faint)
            }

            if let lw = libWord {
                Text("\(lw.band) · \(lw.categories.joined(separator: " / "))")
                    .font(JournalTheme.serifItalic(11))
                    .tracking(0.8)
                    .foregroundColor(JournalTheme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 词库信息：释义大字 + 词形 + 频段·词表小灰。
    private func definitionBlock(_ lw: VocabWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lw.definition)
                .font(.system(size: 14.5))
                .foregroundColor(JournalTheme.ink)
                .lineSpacing(4)
            if !lw.forms.isEmpty {
                Text(lw.forms.joined(separator: "  ·  "))
                    .font(JournalTheme.serifItalic(12))
                    .foregroundColor(JournalTheme.faint)
            }
            Text("\(lw.band) · \(lw.categories.joined(separator: " / "))")
                .font(JournalTheme.serifItalic(11))
                .tracking(0.8)
                .foregroundColor(JournalTheme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 收词时的原句——遇到它的那一刻（记忆锚点）。聊天收词整块可点跳回原对话。
    @ViewBuilder
    private func anchorBlock(_ anchor: String) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Label(sourceLabel ?? "出处", systemImage: chatJumpNodeId != nil ? "bubble.left" : "book.closed")
                .font(JournalTheme.serif(11, .semibold))
                .foregroundColor(JournalTheme.rose)
            Text("\u{201C}\(anchor)\u{201D}")
                .font(JournalTheme.serifItalic(14))
                .foregroundColor(JournalTheme.ink.opacity(0.9))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let nid = chatJumpNodeId {
            Button {
                dismiss()
                let thinkingWord = jumpIsThinking ? word : nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    bridge.openChatSource?(nid, thinkingWord)
                }
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let src = vocabJumpWord {
            Button {
                jumpWord = src
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func aiNoteBlock(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(assistantName)的注解", systemImage: "sparkles")
                .font(JournalTheme.serif(11, .semibold))
                .foregroundColor(JournalTheme.mint)
            pageOneMarkdown(note)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(JournalTheme.mint.opacity(0.13))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("no archaeology yet")
                .font(JournalTheme.serifItalic(15))
                .foregroundColor(JournalTheme.pencil)
            Text("夜里的考古触发器会慢慢补，也可以在学习卡点「问\(assistantName)」")
                .font(JournalTheme.serifItalic(12))
                .foregroundColor(JournalTheme.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}
