import SwiftUI
import JournalKit
import SwiftData
#if os(iOS)
import UIKit
#endif

/// 学习卡片（核心交互）。
///
/// 结构：顶部进度条 + 计时器 → 中央 word/释义/forms/note → 底部 3 档按钮 + 显隐/跳过。
/// 键盘（D5=A）：1=认识 / 2=反应慢 / 3=不认识 / Space=显隐释义 / N=跳过。
/// blur 未 reveal 的释义，点卡片或 Space 揭示——先猜后看是这工具的核心体验。
private struct StudyJumpWord: Identifiable {
    let word: String
    var id: String { word }
}

struct VocabStudyView: View {
    @Environment(\.vocabBridge) private var bridge
    @Bindable var store: VocabSessionStore
    @Environment(\.modelContext) private var modelContext

    @AppStorage("assistantName") private var assistantName = "the assistant"
    @AppStorage("vocabAskPromptTemplate") private var promptTemplate = VocabPromptDefaults.template

    /// 计时器秒数（每秒 tick），mark 时用 sessionStart 算真实秒数（不依赖这个 UI 值）。
    @State private var elapsed: TimeInterval = 0

    /// 当前词的旧笔记（VocabProgress.note，R2-2 迁移 seed 用；切词时随 loadSourceRef 刷新）。
    @State private var progressNote: String? = nil


    /// CR-3 出处 chip：当前词的收词出处（sourceBookRef 解析后），nil = 词库刷词无出处。
    @State private var sourceRef: VocabSourceRef? = nil
    /// 聊天收词的原消息 node（预检存在才设，chip 点击跳回对话）。
    @State private var chatJumpNodeId: String? = nil
    /// 思考链收词标记（跳回自动弹思考链+闪词）。
    @State private var chatJumpIsThinking = false
    /// 词详情里收的词：来源词（chip 点击打开它的词详情）。
    @State private var vocabJumpWord: String? = nil

    /// CR-3 P3 词详情 sheet（考古笔记 + AI 注解）。
    @State private var showWordDetail = false
    /// 出处跳转打开的来源词详情。
    @State private var jumpDetailWord: String? = nil

    /// B-1：筛选从 tab 收进刷词页（sheet）。
    @State private var showFilter = false

    /// 当前词是否已在生词本（✨ 按钮状态，切词时随 loadSourceRef 刷新）。
    @State private var isInNotebook = false

    /// 当前词是否已在复习牌堆（🔁 按钮状态，切词时随 loadSourceRef 刷新）。
    @State private var isInReviewDeck = false

    struct VocabSourceRef: Equatable {
        let safeName: String
        let displayName: String
        let chapter: Int
        let offset: Int?
    }


    var body: some View {
        // A-5 拟物手账：刷词页同款活页纸底
        // 蕾丝底由 VocabPanelView 容器统一铺（页面内再铺会在 UIKit HC 里
        // ignoresSafeArea 物理溢出盖住书签行——R7c 缺角真凶）
        ZStack {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(JournalTheme.paper)
                    PaperNoise()
                    RuledLines(topOffset: 12)
                    RoseMarginLines(x: 34)
                    PunchHoles()

                    Group {
                        if store.filtered.isEmpty {
                            emptyState
                        } else if store.idx >= store.filtered.count {
                            completedState
                        } else if let word = store.currentWord {
                            studyContent(word: word)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: JournalTheme.shadowInk.opacity(0.13), radius: 8, y: 3)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .task(id: store.currentWord?.word) {
            loadSourceRef()
        }
        .sheet(isPresented: $showFilter) {
            NavigationStack { VocabFilterView(store: store) }
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 520)
                #endif
        }
        .sheet(isPresented: $showWordDetail) {
            if let w = store.currentWord {
                VocabWordDetailSheet(word: w.word)
            }
        }
        .sheet(item: Binding(
            get: { jumpDetailWord.map { StudyJumpWord(word: $0) } },
            set: { if $0 == nil { jumpDetailWord = nil } }
        )) { j in
            VocabWordDetailSheet(word: j.word)
        }

    }

    // MARK: - 出处 chip 数据（CR-3 书词打通）

    /// 切词时读当前词的收词出处。progress 单词 predicate 查询，量级小。
    private func loadSourceRef() {
        sourceRef = nil
        chatJumpNodeId = nil
        chatJumpIsThinking = false
        vocabJumpWord = nil
        isInNotebook = false
        isInReviewDeck = false
        progressNote = nil
        guard let word = store.currentWord?.word else { return }
        isInReviewDeck = VocabCardStore.load().contains { $0.word == word }
        let desc = FetchDescriptor<VocabProgress>(predicate: #Predicate { $0.word == word })
        let progress = (try? modelContext.fetch(desc))?.first
        if let old = progress?.note, !old.isEmpty { progressNote = old }
        let ref = progress?.sourceBookRef
        isInNotebook = ref != nil
        if let ref, let srcWord = VocabCollector.parseVocabRef(ref) {
            vocabJumpWord = srcWord
            return
        }
        if let ref, let nid = VocabCollector.parseThinkingRef(ref) ?? VocabCollector.parseChatRef(ref) {
            // 组件库版：无消息库可预检，接了桥即可点
            if bridge.openChatSource != nil {
                chatJumpNodeId = nid
                chatJumpIsThinking = VocabCollector.parseThinkingRef(ref) != nil
            }
            return
        }
        guard let ref, let parsed = Self.parseSourceBookRef(ref), bridge.openBookSource != nil else { return }
        sourceRef = VocabSourceRef(
            safeName: parsed.safe,
            displayName: parsed.safe,
            chapter: parsed.chapter,
            offset: parsed.offset
        )
    }

    /// 解析 `<safeName>#chapter<N>[#<offset>]`（VocabCollector 写入格式，offset 段可缺）。
    static func parseSourceBookRef(_ ref: String) -> (safe: String, chapter: Int, offset: Int?)? {
        let parts = ref.split(separator: "#")
        guard parts.count >= 2, !parts[0].isEmpty,
              parts[1].hasPrefix("chapter"),
              let n = Int(parts[1].dropFirst("chapter".count)) else { return nil }
        let offset = parts.count >= 3 ? Int(parts[2]) : nil
        return (String(parts[0]), n, offset)
    }

    // MARK: - 主学习态

    @ViewBuilder
    private func studyContent(word: VocabWord) -> some View {
        VStack(spacing: 16) {
            progressHeader

            ScrollView {
                VStack(spacing: 18) {
                    wordCard(word: word)
                        // 动效：切词 = 新卡片落桌（同复习页语言）
                        .id(word.word)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.05).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: word.word)
                    if !word.forms.isEmpty {
                        formsRow(forms: word.forms)
                    }
                    // R2-2 笔记合并：揭示后就地展示词条笔记（复习卡/词详情同一篇 md）
                    if store.revealed {
                        VocabNoteSection(word: word.word, legacySeed: progressNote)
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 4)
            }
            .scrollDismissesKeyboard(.immediately)

            actionButtons
        }
        .onChange(of: store.idx) { _, _ in
            elapsed = 0
        }
        .task(id: store.idx) {
            // 计时 tick；切词时 .task 重启
            elapsed = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1000))
                elapsed = Date().timeIntervalSince(store.sessionStart)
            }
        }
    }

    // MARK: - 顶部进度 + 计时

    private var progressHeader: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("\(store.idx + 1) of \(store.filtered.count)")
                .font(JournalTheme.serif(14, .semibold))
                .foregroundColor(JournalTheme.ink) +
            Text("  ·  \(timerLabel)")
                .font(JournalTheme.mono(11))
                .foregroundColor(JournalTheme.faint)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            // B-1：筛选按钮（原筛选 tab 收编）
            Button {
                showFilter = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(JournalTheme.pencil)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    private var progressFraction: CGFloat {
        guard !store.filtered.isEmpty else { return 0 }
        return CGFloat(store.idx + 1) / CGFloat(store.filtered.count)
    }

    private var timerLabel: String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - 单词卡

    private func wordCard(word: VocabWord) -> some View {
        VStack(spacing: 0) {
            // word 大字（衬线）
            Text(word.word)
                .font(JournalTheme.serif(38, .bold))
                .foregroundColor(JournalTheme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .padding(.top, 32)

            // band · 词表（斜体微标签一行）
            Text("\(word.band) · \(word.categories.first ?? "")")
                .font(JournalTheme.serifItalic(11))
                .tracking(1)
                .foregroundColor(JournalTheme.faint)
                .lineLimit(1)
                .padding(.top, 10)

            // 释义（blur 先猜后看——刷词高频，比撕胶带快）；词库外雅思词 ECDICT 兜底
            Text(word.definition.isEmpty
                 ? (VocabDictStore.entry(for: word.word)?.t ?? "no definition yet — check full entry")
                 : word.definition)
                .font(.system(size: 16))
                .foregroundColor(store.revealed ? JournalTheme.ink : JournalTheme.pencil)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 72)
                .blur(radius: store.revealed ? 0 : 6)
                .animation(.easeInOut(duration: 0.2), value: store.revealed)

            // 出处 / 发音 / 词详情（复习卡同款语言）
            HStack(spacing: 14) {
                if let src = sourceRef {
                    sourceChip(src)
                }
                if chatJumpNodeId != nil {
                    chatSourceChip
                }
                if vocabJumpWord != nil {
                    vocabSourceChip
                }
                pronounceChip(word: word.word)
                detailChip(word: word)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 14)
        .paperCard(cornerRadius: 14, rotation: 0.6, roseEdge: true)
        .overlay(alignment: .top) {
            WashiTape(color: JournalTheme.rose)
                .rotationEffect(.degrees(-1.8))
                .offset(y: -13)
        }
        .padding(.top, 16)
        .padding(.horizontal, 6)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            store.toggleReveal()
            hapticSelection()  // 揭示瞬间轻 tick
        }
        // ✨ 加入生词本 + 🔁 进复习（右上角；已收/已在=薄荷实心，无移除操作）
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                Button {
                    addCurrentToReview(word: word)
                } label: {
                    PixelIcon(bitmap: PixelGlyph.repeatArrows, size: 15,
                              color: isInReviewDeck ? JournalTheme.mint : JournalTheme.faint.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    addCurrentToNotebook(word: word)
                } label: {
                    PixelIcon(bitmap: isInNotebook ? PixelGlyph.starFilled : PixelGlyph.starOutline, size: 15,
                              color: isInNotebook ? JournalTheme.mint : JournalTheme.faint.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(4)
        }
    }

    /// 🔁 当前词进复习牌堆 ⇄ 再按撤回（R3.3 toggle）。
    private func addCurrentToReview(word: VocabWord) {
        if isInReviewDeck {
            var cards = VocabCardStore.load()
            cards.removeAll { $0.word == word.word }
            VocabCardStore.save(cards)
            isInReviewDeck = false
            ToastCenter.shared.show("Removed from review deck")
        } else if VocabCardStore.addIfAbsent(word: word.word, source: "screening") {
            isInReviewDeck = true
            ToastCenter.shared.show("Added to review 🔁")
        }
    }

    /// ✨ 收当前词进生词本 ⇄ 再按撤回（R3.3 toggle；三态标记保留）。
    private func addCurrentToNotebook(word: VocabWord) {
        if isInNotebook {
            let w = word.word
            let desc = FetchDescriptor<VocabProgress>(predicate: #Predicate { $0.word == w })
            if let progress = (try? modelContext.fetch(desc))?.first {
                progress.sourceBookRef = nil
                progress.anchorText = nil
                try? modelContext.save()
            }
            isInNotebook = false
            ToastCenter.shared.show("Removed from notebook")
        } else if VocabCollector.collectManually(rawText: word.word, context: modelContext) != nil {
            isInNotebook = true
            hapticAsk()
            ToastCenter.shared.show("Added to notebook ✨")
        }
    }

    /// 发音——像素喇叭，小图标统一规格（15pt 裸图标 + 40 hit 区，无坨）。
    private func pronounceChip(word: String) -> some View {
        Button { SpeechService.shared.speakWord(word) } label: {
            PixelIcon(bitmap: PixelGlyph.speaker, size: 15, color: JournalTheme.pencil)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 词详情入口——复习卡同款 full entry →（跨页统一）。
    private func detailChip(word: VocabWord) -> some View {
        Button { showWordDetail = true } label: {
            Text("full entry →")
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(
                    VocabCorpusStore.hasCorpus(for: word.word) ? JournalTheme.mint : JournalTheme.faint
                )
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 聊天收词出处：点一下跳回收词的对话原处。
    private var chatSourceChip: some View {
        Button {
            guard let nid = chatJumpNodeId else { return }
            bridge.openChatSource?(nid, chatJumpIsThinking ? store.currentWord?.word : nil)
        } label: {
            Text(chatJumpIsThinking ? "thinking →" : "chat →")
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(JournalTheme.rose)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 词详情里收的词出处：点开来源词的详情。
    private var vocabSourceChip: some View {
        Button {
            if let w = vocabJumpWord { jumpDetailWord = w }
        } label: {
            Text("dig notes · \(vocabJumpWord ?? "") →")
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(JournalTheme.rose)
                .lineLimit(1)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sourceChip(_ src: VocabSourceRef) -> some View {
        Button {
            if let src = sourceRef { bridge.openBookSource?(src.safeName, src.chapter, src.offset) }
        } label: {
            Text("\(src.displayName) · ch.\(src.chapter)")
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(JournalTheme.rose)
                .lineLimit(1)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - forms 词形变化

    private func formsRow(forms: [String]) -> some View {
        Text(forms.joined(separator: "  ·  "))
            .font(JournalTheme.serifItalic(12))
            .foregroundColor(JournalTheme.faint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }

    // MARK: - 底部按钮

    private var actionButtons: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 34) {
                markButton(label: "know", color: JournalTheme.mint, status: .known, key: "1")
                markButton(label: "slow", color: JournalTheme.amber, status: .slow, key: "2")
                markButton(label: "unknown", color: JournalTheme.clay, status: .unknown, key: "3")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            if bridge.askAI != nil {
                askButton
            }

            HStack(spacing: 28) {
                secondaryButton(label: store.revealed ? "hide" : "reveal", key: " ") {
                    store.toggleReveal()
                }
                secondaryButton(label: "skip →", key: "n") {
                    store.nextWithoutMark()
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - 「问 {{char}}」按钮 + 发送（D5=A 浅薄荷次级）

    private var askButton: some View {
        Button {
            askInChat()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11))
                Text("ask \(assistantName)")
                    .font(JournalTheme.serif(13, .medium))
            }
            .foregroundColor(JournalTheme.ink.opacity(0.85))
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(JournalTheme.mint.opacity(0.22))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.currentWord == nil)  // D6=A 跟三档同步
    }

    /// 组件库版：问 AI 经 bridge（宿主接对话管线）。
    private func askInChat() {
        guard let word = store.currentWord, let ask = bridge.askAI else { return }
        let prompt = buildPrompt(word: word)
        if ask(word.word, prompt) {
            hapticAsk()
            ToastCenter.shared.show("Sent to \(assistantName) — check chat for the reply")
        } else {
            ToastCenter.shared.show("Failed to send")
        }
    }

    /// 渲染 @AppStorage("vocabAskPromptTemplate") 模板。
    private func buildPrompt(word: VocabWord) -> String {
        let snap = store.readProgressSnapshot(context: modelContext)
        let statusZh: String = {
            guard let st = snap[word.word]?.status else { return "" }
            switch st {
            case .known:   return "known"
            case .slow:    return "slow"
            case .unknown: return "unknown"
            }
        }()

        return VocabPromptDefaults.render(template: promptTemplate, vars: [
            "word": word.word,
            "definition": word.definition,
            "band": word.band,
            "categories": word.categories.joined(separator: "、"),
            "forms": word.forms.joined(separator: ", "),
            "status": statusZh,
            "assistantName": assistantName,
        ])
    }


    /// v3 定稿风：衬线彩字 + 微斜手绘下划线（复习页评分行同款语言）。快捷键 1/2/3 保留。
    private func markButton(label: String, color: Color, status: VocabStatus, key: KeyEquivalent) -> some View {
        Button {
            hapticForStatus(status)  // 三档不同震感（认识 light / 反应慢 medium / 不认识 heavy）
            store.markCurrent(status: status, context: modelContext)
        } label: {
            Text(label)
                .font(JournalTheme.serif(16, .semibold))
                .tracking(1)
                .foregroundColor(color)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.35))
                        .frame(height: 2)
                        .rotationEffect(.degrees(-0.8))
                        .padding(.horizontal, 1)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
    }

    private func secondaryButton(label: String, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(JournalTheme.faint)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
    }

    // MARK: - 边界态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("nothing under this filter")
                .font(JournalTheme.serifItalic(15))
                .foregroundColor(JournalTheme.pencil)
            Button {
                showFilter = true
            } label: {
                Text("adjust filter →")
                    .font(JournalTheme.serifItalic(13))
                    .foregroundColor(JournalTheme.mint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 触觉反馈

    private func hapticForStatus(_ status: VocabStatus) {
        #if os(iOS)
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch status {
        case .known:   style = .light
        case .slow:    style = .medium
        case .unknown: style = .heavy
        }
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
        #endif
    }

    private func hapticSelection() {
        #if os(iOS)
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        g.selectionChanged()
        #endif
    }

    /// 「问 {{char}}」按钮专用软震（区别于三档的硬震）。
    private func hapticAsk() {
        #if os(iOS)
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        g.impactOccurred()
        #endif
    }

    private var completedState: some View {
        VStack(spacing: 12) {
            StarSticker(color: JournalTheme.amber, size: 34, rotation: -8)
            Text("round complete")
                .font(JournalTheme.serif(19, .semibold))
                .foregroundColor(JournalTheme.ink)
            Text("\(store.filtered.count) words · ✦")
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(JournalTheme.faint)
            Button {
                store.resetIndex()
            } label: {
                Text("one more round →")
                    .font(JournalTheme.serifItalic(13))
                    .foregroundColor(JournalTheme.mint)
                    .padding(.top, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
