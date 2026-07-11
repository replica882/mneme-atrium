import SwiftUI
import JournalKit
import SwiftData

/// 「复习」tab：SM-2 到期队列 + 题型阶梯（认读 → 拼写 → 造句）。
/// 与「刷词」（筛选机制）完全分开：独立牌堆 VocabCardStore，只单向读筛选的 known 集。
/// 样式语言照抄 VocabStudyView（大词卡/blur 释义/三档按钮），代码独立不共享。
struct VocabReviewView: View {
    @Environment(\.vocabBridge) private var bridge
    @Bindable var store: VocabReviewStore
    @Bindable var sessionStore: VocabSessionStore
    @Environment(\.modelContext) private var modelContext

    @AppStorage("vocabReviewDailyQuota") private var dailyQuota = 10
    /// 每日复习总量上限（新卡+到期都算，0 = 不限）。
    @AppStorage("vocabReviewDailyCap") private var dailyCap = 50
    @AppStorage("vocabReviewQuotaSource") private var quotaSourceRaw = VocabQuotaSource.ngsl.rawValue

    /// 认读题：释义是否已揭示（揭示后才出三档按钮）。
    @State private var revealed = false
    /// all done 星星贴纸 spring 弹入（动效层）。
    @State private var starLanded = false
    /// 拼写题状态机：答题中 / 答对闪 ✓ / 答错亮正确拼写。
    private enum SpellState { case answering, correct, wrong }
    @State private var spellState: SpellState = .answering
    @State private var spellDraft = ""
    /// 造句题状态机：写句子 / 判分中 / 出反馈（或降级自评）。
    private enum SentenceState { case writing, grading, feedback }
    @State private var sentenceState: SentenceState = .writing
    @State private var sentenceDraft = ""
    @State private var gradeOK: Bool? = nil
    @State private var gradeFeedback = ""
    @State private var showAddSheet = false
    @State private var addDraft = ""
    @State private var showWordDetail = false
    /// 当前词的词库条目 + 出处原句（出题材料，切词时重载）。
    @State private var libWord: VocabWord? = nil
    @State private var anchorText: String? = nil
    /// R3.4b 内嵌词典释义（材料链第二级；词表词基本全命中）。
    @State private var dictTranslation: String? = nil
    /// A-3 音标（索引卡显示）。
    @State private var phonetic: String? = nil

    var body: some View {
        // A-3 拟物手账：整页活页纸底（v4），索引卡贴纸上
        // 蕾丝底由 VocabPanelView 容器统一铺（页面内再铺会在 UIKit HC 里
        // ignoresSafeArea 物理溢出盖住书签行——R7c 缺角真凶）
        ZStack {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    // 四角圆角（缝的真凶是顶边距不是圆角——R5-2 粟粟点名圆角回归）
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(JournalTheme.paper)
                    PaperNoise()
                    RuledLines(topOffset: 12)
                    RoseMarginLines(x: 34)
                    PunchHoles()

                    Group {
                        if let card = store.currentCard {
                            exerciseContent(card: card)
                        } else if store.cards.isEmpty {
                            emptyDeckState
                        } else {
                            allDoneState
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
        .task { await bootstrap() }
        .task(id: store.currentCard?.word) {
            revealed = false
            spellState = .answering
            spellDraft = ""
            sentenceState = .writing
            sentenceDraft = ""
            gradeOK = nil
            gradeFeedback = ""
            await loadMaterial()
        }
        .sheet(isPresented: $showAddSheet) { addWordSheet }
        .sheet(isPresented: $showWordDetail) {
            if let word = store.currentCard?.word {
                VocabWordDetailSheet(word: word)
            }
        }
    }

    // MARK: - 启动 / 材料

    private func bootstrap() async {
        let snapshot = sessionStore.readProgressSnapshot(context: modelContext)
        let known = Set(snapshot.filter { $0.value.status == .known }.keys)
        var library: [VocabWord] = []
        if dailyQuota > 0 {
            let source = VocabQuotaSource(rawValue: quotaSourceRaw) ?? .ngsl
            let ngsl = await VocabLibrary.shared.words
            let gap = Set(snapshot.filter { $0.value.status == .slow || $0.value.status == .unknown }.keys)
            library = VocabReviewStore.quotaLibrary(
                source: source,
                ngsl: ngsl,
                ielts: source == .ielts ? VocabReviewStore.loadIELTSWords() : [],
                gapWords: gap,
                notebookWords: source == .notebook ? notebookWordsByRecency() : []
            )
        }
        store.bootstrap(knownWords: known, quota: dailyQuota, library: library,
                        quotaSourceId: (VocabQuotaSource(rawValue: quotaSourceRaw) ?? .ngsl).rawValue,
                        dailyCap: dailyCap)
    }

    /// 生词本词面按收词时间倒序（optional 谓词坑：全 fetch + 内存 filter，量级小）。
    private func notebookWordsByRecency() -> [String] {
        let all = (try? modelContext.fetch(FetchDescriptor<VocabProgress>())) ?? []
        return all.filter { $0.sourceBookRef != nil }
            .sorted { $0.markedAt > $1.markedAt }
            .map(\.word)
    }

    /// 出题材料：词库释义 + 内嵌词典 + 出处原句（书里收的词）。
    private func loadMaterial() async {
        libWord = nil
        anchorText = nil
        dictTranslation = nil
        guard let word = store.currentCard?.word else { return }
        libWord = await VocabLibrary.shared.words.first { $0.word == word }
        let dict = VocabDictStore.entry(for: word)
        dictTranslation = dict?.t
        phonetic = dict?.p
        let w = word
        let desc = FetchDescriptor<VocabProgress>(predicate: #Predicate { $0.word == w })
        anchorText = (try? modelContext.fetch(desc))?.first?.anchorText
    }

    // MARK: - 题目主体

    @ViewBuilder
    private func exerciseContent(card: VocabCard) -> some View {
        VStack(spacing: 0) {
            progressHeader
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 18) {
                    Group {
                        switch effectiveExercise(card: card) {
                        case .spell:
                            spellCard(card: card)
                        case .sentence:
                            sentenceCard(card: card)
                        case .read:
                            readCard(card: card)
                        }
                    }
                    // 动效：换卡 = 新纸片落到桌上（轻缩放进场，静态后零开销）
                    .id(card.id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.05).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.spring(response: 0.38, dampingFraction: 0.8), value: card.id)
                    // R3.2：牌堆删卡入口（手动加的/配额卡在生词本够不着）
                    .contextMenu {
                        Button(role: .destructive) {
                            let word = card.word
                            store.removeCurrentCard()
                            showToast("Removed “\(word)” from deck")
                        } label: {
                            Label("Remove from review deck", systemImage: "trash")
                        }
                    }
                    // 笔记：认读揭示后 / 拼写答完 / 造句全程可见（不泄题）
                    if noteVisible(card: card) {
                        VocabNoteSection(word: card.word)
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 4)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.immediately)
            #endif

            if effectiveExercise(card: card) == .read && revealed {
                ratingButtons(exercise: .read)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: revealed)
    }

    /// 题型阶梯 + 材料兜底：该出拼写但材料全无 → 降认读。
    private func effectiveExercise(card: VocabCard) -> VocabExercise {
        let ladder = SM2.exercise(reps: card.reps, intervalDays: card.intervalDays)
        if ladder == .spell && spellMaterialNow.degraded { return .read }
        return ladder
    }

    /// 笔记可见时机：认读要先揭示、拼写要先答完（笔记可能写着答案），造句不泄题全程可见。
    private func noteVisible(card: VocabCard) -> Bool {
        switch effectiveExercise(card: card) {
        case .read:     return revealed
        case .spell:    return spellState != .answering
        case .sentence: return true
        }
    }

    /// 当前卡的拼写材料（noteText Task 7 接入，目前 nil）。
    private var spellMaterialNow: (prompt: String, degraded: Bool) {
        VocabReviewStore.spellMaterial(
            word: store.currentCard?.word ?? "",
            definition: (libWord?.definition.isEmpty == false ? libWord?.definition : dictTranslation),
            anchorText: anchorText,
            note: nil
        )
    }

    private var progressHeader: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                Spacer()
                Text("\(min(store.idx + 1, store.queue.count)) of \(store.queue.count)")
                    .font(JournalTheme.serif(14, .semibold))
                    .foregroundColor(JournalTheme.ink)
                Text("·")
                    .font(JournalTheme.serifItalic(12))
                    .foregroundColor(JournalTheme.faint)
                // 词书名直接可点（books 小图标退役——粟粟找不到雅思表就是它藏太深）
                sourceMenu
                Spacer()
            }
            .overlay(alignment: .trailing) { addWordButton }

            progressPencilLine
        }
        .padding(.top, 10)
    }

    /// 词书选择：词书名文字即入口（R2-1 模型 A：只管配额供卡，与筛选页无关）。
    private var sourceMenu: some View {
        Menu {
            Picker("Wordbook", selection: $quotaSourceRaw) {
                ForEach(VocabQuotaSource.allCases) { s in
                    Text(s.title).tag(s.rawValue)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text((VocabQuotaSource(rawValue: quotaSourceRaw) ?? .ngsl).journalLabel)
                    .font(JournalTheme.serifItalic(12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(JournalTheme.pencil)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onChange(of: quotaSourceRaw) { _, _ in
            Task { await bootstrap() }
        }
    }

    /// T5 进度条：手绘铅笔线（薄荷，微斜），分母 = 今日队列（日上限截断后）。
    private var progressPencilLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(JournalTheme.faint.opacity(0.25))
                    .frame(height: 3.5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(JournalTheme.mint.opacity(0.75))
                    .frame(width: max(0, geo.size.width * progressFraction), height: 3.5)
                    .animation(.easeOut(duration: 0.3), value: progressFraction)
            }
        }
        .frame(height: 3.5)
        .rotationEffect(.degrees(-0.4))
        .padding(.horizontal, 30)
    }

    private var progressFraction: CGFloat {
        guard !store.queue.isEmpty else { return 0 }
        return CGFloat(store.idx) / CGFloat(store.queue.count)
    }

    // MARK: - 认读题

    /// A-3 索引卡（mockup v6）：衬线词面 + 音标喇叭 + 波点胶带遮释义（tap to peel）。
    private func readCard(card: VocabCard) -> some View {
        VStack(spacing: 0) {
            Text(card.word)
                .font(JournalTheme.serif(38, .bold))
                .foregroundColor(JournalTheme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .padding(.top, 34)

            HStack(spacing: 9) {
                if let phon = phonetic, !phon.isEmpty {
                    Text("/\(phon)/")
                        .font(JournalTheme.mono(13))
                        .foregroundColor(JournalTheme.pencil)
                }
                Button {
                    SpeechService.shared.speakWord(card.word)
                } label: {
                    PixelIcon(bitmap: PixelGlyph.speaker, size: 15, color: JournalTheme.pencil)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)

            Text(sourceLabel(card.source))
                .font(JournalTheme.serifItalic(11))
                .foregroundColor(JournalTheme.faint)
                .tracking(1)
                .padding(.top, 8)

            // 释义：波点胶带盖着，tap 撕开
            ZStack {
                if revealed {
                    Text(readMaterial)
                        .font(.system(size: 16))
                        .foregroundColor(JournalTheme.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    WashiTape(dotted: true, width: 250, height: 56)
                        .overlay(
                            Text("tap to peel")
                                .font(JournalTheme.serifItalic(14))
                                .foregroundColor(.white.opacity(0.92))
                                .shadow(color: JournalTheme.shadowInk.opacity(0.18), radius: 1, y: 1)
                        )
                        .rotationEffect(.degrees(-0.9))
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 76)
            .padding(.top, 18)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    revealed.toggle()
                }
            }

            Spacer(minLength: 12)

            // full entry → 右下角
            HStack {
                Spacer()
                Button {
                    showWordDetail = true
                } label: {
                    Text("full entry →")
                        .font(JournalTheme.serifItalic(11))
                        .foregroundColor(JournalTheme.faint)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 6)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 300)
        .paperCard(cornerRadius: 14, rotation: -0.7, roseEdge: true)
        .overlay(alignment: .top) {
            WashiTape(color: JournalTheme.amber)
                .rotationEffect(.degrees(1.8))
                .offset(y: -13)
        }
        .padding(.top, 16)
        .padding(.horizontal, 6)
    }

    /// 发音——像素喇叭（小图标统一规格）。
    private func pronounceChip(word: String) -> some View {
        Button { SpeechService.shared.speakWord(word) } label: {
            PixelIcon(bitmap: PixelGlyph.speaker, size: 15, color: JournalTheme.pencil)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 认读材料链：词库释义 → 出处原句 → 引导写笔记。
    private var readMaterial: String {
        if let def = libWord?.definition, !def.isEmpty { return def }
        if let anchor = anchorText, !anchor.isEmpty { return "“\(anchor)”" }
        return "no definition yet — write one in notes"
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "manual":    return "added by hand"
        case "quota":     return "new from wordbook"
        case "screening": return "from screening"
        case "notebook":  return "from notebook"
        case "reading":   return "found in a book"
        case "chat":      return "found in chat"
        default:          return source
        }
    }

    private var detailChip: some View {
        Button { showWordDetail = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "scroll")
                    .font(.system(size: 10))
                Text("Word details")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(JournalTheme.pencil)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(JournalTheme.wash.opacity(0.6))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 拼写题

    private func spellCard(card: VocabCard) -> some View {
        VStack(spacing: 14) {
            Text("spell it")
                .font(JournalTheme.serifItalic(12))
                .tracking(1.5)
                .foregroundColor(JournalTheme.faint)
                .padding(.top, 30)

            Text(spellMaterialNow.prompt)
                .font(.system(size: 18))
                .foregroundColor(JournalTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 70)

            if spellState == .wrong {
                Text("Correct spelling: \(card.word)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(JournalTheme.clay)
            } else if spellState == .correct {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(JournalTheme.mint)
            }

            TextField("type the spelling…", text: $spellDraft)
                .font(.system(size: 20, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .disabled(spellState != .answering)
                .onSubmit { submitSpelling(card: card) }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(JournalTheme.wash.opacity(0.5), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 12)

            Button {
                submitSpelling(card: card)
            } label: {
                Text("Submit")
                    .font(.system(size: JournalTheme.F.body, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(JournalTheme.mint)
                    )
            }
            .buttonStyle(.plain)
            .disabled(spellState != .answering
                      || spellDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            detailChip
                .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .paperCard(cornerRadius: 14, rotation: 0.5, roseEdge: true)
        .overlay(alignment: .top) {
            WashiTape(color: JournalTheme.mint)
                .rotationEffect(.degrees(-1.6))
                .offset(y: -13)
        }
        .padding(.top, 16)
        .padding(.horizontal, 6)
    }

    /// 机器判分：对 = 会（短暂 ✓ 后推进），错 = 展示正确拼写 2s 后记「错」。
    private func submitSpelling(card: VocabCard) {
        guard spellState == .answering else { return }
        let answer = spellDraft.trimmingCharacters(in: .whitespaces).lowercased()
        guard !answer.isEmpty else { return }
        if answer == card.word {
            spellState = .correct
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                store.submitRating(.good, exercise: .spell)
            }
        } else {
            spellState = .wrong
            Task {
                try? await Task.sleep(for: .seconds(2))
                store.submitRating(.again, exercise: .spell)
            }
        }
    }

    // MARK: - 造句题

    private func sentenceCard(card: VocabCard) -> some View {
        VStack(spacing: 14) {
            Text("use it in a sentence")
                .font(JournalTheme.serifItalic(12))
                .tracking(1.5)
                .foregroundColor(JournalTheme.faint)
                .padding(.top, 30)

            Text(card.word)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(JournalTheme.ink)
                .multilineTextAlignment(.center)

            if let def = libWord?.definition, !def.isEmpty {
                Text(def)
                    .font(.system(size: JournalTheme.F.secondary))
                    .foregroundColor(JournalTheme.pencil)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            TextEditor(text: $sentenceDraft)
                .font(.system(size: JournalTheme.F.body))
                .foregroundColor(JournalTheme.ink)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .disabled(sentenceState != .writing)
                .frame(minHeight: 90)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(JournalTheme.wash.opacity(0.5), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 12)

            switch sentenceState {
            case .writing:
                Button {
                    submitSentence(card: card)
                } label: {
                    Text("Submit for grading")
                        .font(.system(size: JournalTheme.F.body, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(JournalTheme.mint)
                        )
                }
                .buttonStyle(.plain)
                .disabled(sentenceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 12)

            case .grading:
                ProgressView()
                    .padding(.vertical, 8)

            case .feedback:
                VStack(spacing: 10) {
                    if let ok = gradeOK {
                        HStack(spacing: 6) {
                            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(ok ? JournalTheme.mint : JournalTheme.clay)
                            Text(gradeFeedback.isEmpty ? (ok ? "nice, that works" : "give it another look") : gradeFeedback)
                                .font(.system(size: JournalTheme.F.secondary))
                                .foregroundColor(JournalTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill((gradeOK == true ? JournalTheme.mint : JournalTheme.clay).opacity(0.12))
                        )
                        .padding(.horizontal, 12)
                    } else {
                        Text("AI grading unavailable — grade it yourself")
                            .font(.system(size: JournalTheme.F.caption))
                            .foregroundColor(JournalTheme.faint)
                    }
                    ratingButtons(exercise: .sentence, suggested: gradeOK.map { $0 ? .good : .again })
                        .padding(.horizontal, 12)
                }
                .padding(.bottom, 8)
            }

            detailChip
                .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .paperCard(cornerRadius: 14, rotation: -0.5, roseEdge: true)
        .overlay(alignment: .top) {
            WashiTape(color: JournalTheme.rose)
                .rotationEffect(.degrees(1.4))
                .offset(y: -13)
        }
        .padding(.top, 16)
        .padding(.horizontal, 6)
    }

    /// AI 判分 → 反馈 + 预选评分（可改）；判分不可用 → 降级自评。
    private func submitSentence(card: VocabCard) {
        let sentence = sentenceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        sentenceState = .grading
        let word = card.word
        let def = libWord?.definition
        Task {
            let result = await VocabSentenceGrader.grade(word: word, definition: def, sentence: sentence, via: bridge)
            gradeOK = result?.ok
            gradeFeedback = result?.feedback ?? ""
            sentenceState = .feedback
        }
    }

    // MARK: - 三档评分按钮

    /// v3 定稿：极简衬线文字评分行 again · hard · good（各色字+微斜手绘下划线）。
    /// suggested：AI 判分建议档（下划线加重），粟粟可点任意档改判。
    private func ratingButtons(exercise: VocabExercise, suggested: SM2Rating? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 38) {
            ratingButton(label: "again", color: JournalTheme.clay, rating: .again,
                         exercise: exercise, highlighted: suggested == .again)
            ratingButton(label: "hard", color: JournalTheme.amber, rating: .hard,
                         exercise: exercise, highlighted: suggested == .hard)
            ratingButton(label: "good", color: JournalTheme.mint, rating: .good,
                         exercise: exercise, highlighted: suggested == .good)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func ratingButton(label: String, color: Color, rating: SM2Rating,
                              exercise: VocabExercise, highlighted: Bool = false) -> some View {
        Button {
            store.submitRating(rating, exercise: exercise)
        } label: {
            Text(label)
                .font(JournalTheme.serif(16, .semibold))
                .tracking(1)
                .foregroundColor(color)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(highlighted ? 0.8 : 0.35))
                        .frame(height: 2)
                        .rotationEffect(.degrees(-0.8))
                        .padding(.horizontal, 1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 加词

    private var addWordButton: some View {
        Button {
            addDraft = ""
            showAddSheet = true
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(JournalTheme.pencil)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var addWordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("today, ephemeral, take off…", text: $addDraft)
                        .font(.system(size: JournalTheme.F.body))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .listRowBackground(JournalTheme.cream)
                        .onSubmit { confirmAdd() }
                } header: {
                    Text("Add to review deck")
                        .foregroundColor(JournalTheme.faint)
                } footer: {
                    Text("Any word, any list — whatever you picked up today. Phrases work too.")
                        .font(.system(size: JournalTheme.F.caption))
                        .foregroundColor(JournalTheme.faint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JournalTheme.sage)
            .navigationTitle("Add word")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                        .foregroundColor(JournalTheme.pencil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { confirmAdd() }
                        .foregroundColor(JournalTheme.mint)
                        .disabled(addDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 200)
        #endif
    }

    private func confirmAdd() {
        let raw = addDraft
        showAddSheet = false
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if store.addCard(rawWord: raw, source: "manual") {
            // R3.1：手动加词同步收进生词本——两边数量对齐心智（配额卡仍不进生词本）
            VocabCollector.collectManually(rawText: raw, context: modelContext)
            showToast("Added to review + notebook")
        } else {
            showToast("Already in the deck")
        }
    }

    private func showToast(_ msg: String) {
        ToastCenter.shared.show(msg)
    }

    // MARK: - 空态

    private var emptyDeckState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("a blank page")
                .font(JournalTheme.serifItalic(17))
                .foregroundColor(JournalTheme.pencil)
            Text("Add a word, send one in from words/notebook,\nor pick a wordbook to auto-supply daily new cards")
                .font(.system(size: JournalTheme.F.caption))
                .foregroundColor(JournalTheme.faint)
                .multilineTextAlignment(.center)
            HStack(spacing: 4) {
                sourceMenu
                Button {
                    addDraft = ""
                    showAddSheet = true
                } label: {
                    Text("first word →")
                        .font(JournalTheme.serifItalic(14))
                        .foregroundColor(JournalTheme.mint)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// T6 congratulation：三星弹入 + 大字 + 休息提醒（日上限达成/队列清空都走这）。
    private var allDoneState: some View {
        VStack(spacing: 14) {
            Spacer()
            HStack(spacing: 14) {
                StarSticker(color: JournalTheme.mint, size: 24, rotation: starLanded ? -12 : -20)
                    .scaleEffect(starLanded ? 1 : 0.3)
                    .opacity(starLanded ? 1 : 0)
                StarSticker(color: JournalTheme.amber, size: 36, rotation: starLanded ? 14 : 22)
                    .scaleEffect(starLanded ? 1 : 0.3)
                    .opacity(starLanded ? 1 : 0)
                StarSticker(color: JournalTheme.rose, size: 22, rotation: starLanded ? 8 : 16)
                    .scaleEffect(starLanded ? 1 : 0.3)
                    .opacity(starLanded ? 1 : 0)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.58)) {
                    starLanded = true
                }
            }
            .onDisappear { starLanded = false }

            Text("congratulations!")
                .font(JournalTheme.serif(22, .bold))
                .foregroundColor(JournalTheme.ink)
            Text(tomorrowHint)
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(JournalTheme.pencil)
            Text("take a break ✦ rest your eyes")
                .font(JournalTheme.serifItalic(13))
                .foregroundColor(JournalTheme.mint)
                .padding(.top, 2)
            HStack(spacing: 4) {
                sourceMenu
                addWordButton
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tomorrowHint: String {
        let done = store.reviewedTodayCount()
        let n = store.dueCount(within: 1)
        let tomorrow = n > 0 ? "\(n) due tomorrow" : "nothing due tomorrow"
        return done > 0 ? "\(done) cleared today · \(tomorrow)" : tomorrow
    }
}
