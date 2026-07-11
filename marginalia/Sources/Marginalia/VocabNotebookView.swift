import SwiftUI
import JournalKit
import SwiftData

/// 生词本 tab（CR-3）：书里收的词全在这（sourceBookRef 非空 = 收词）。
/// 表格式列表，按最近收/标时间倒序；tap 行跳学习卡定位该词。
/// 拟物本子是远景，这是 MVP 表格形态。
struct VocabNotebookView: View {
    @Bindable var store: VocabSessionStore
    @Environment(\.modelContext) private var modelContext

    struct Entry: Identifiable {
        let word: String
        let definition: String     // 词库 join；custom 词为空
        let status: VocabStatus
        let sourceLabel: String?   // 《书》· 第 N 章
        let markedAt: Date
        var id: String { word }
    }

    @State private var entries: [Entry] = []
    @State private var loaded = false
    /// R3.3：复习牌堆词面集合（行 🔁 实/虚 + toggle 状态；reload 时刷一次）。
    @State private var deckWords: Set<String> = []

    /// 行内📜按钮点开的词详情（考古笔记 + AI 注解）。
    @State private var detailEntry: Entry? = nil

    /// 搜索收词（✨ 直接添：词库匹配 top10，词库外允许 custom 收录）。
    @State private var searchText = ""
    @State private var searchResults: [VocabWord] = []

    /// R3.1：+ 号直接加新词（粟粟点的——搜索收词藏得深，要显式入口）。
    @State private var showAddSheet = false
    @State private var addDraft = ""

    /// tag 滤条：nil = all。已有 tag 列表随 reload 刷新。
    @State private var activeTag: String? = nil
    @State private var allTags: [String] = []
    @State private var taggedWords: Set<String> = []

    var body: some View {
        // A-2 拟物手账：整页活页纸（mockup v6 定稿）
        // 蕾丝底由容器统一铺（页面内 ignoresSafeArea 在 HC 里物理溢出——R7c）
        ZStack {
            journalPage
        }
        .task { await reload() }
        .sheet(item: $detailEntry) { entry in
            VocabWordDetailSheet(word: entry.word)
        }
        .sheet(isPresented: $showAddSheet) { addWordSheet }
    }

    // MARK: - A-2 活页纸页

    private var journalPage: some View {
        ZStack(alignment: .topLeading) {
            // 纸本体（四角圆角，零顶边距贴 tab）
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(JournalTheme.paper)
                PaperNoise()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        searchLine
                        if !allTags.isEmpty {
                            tagFilterLine
                        }
                        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            searchResultRows
                        } else if loaded {
                            ForEach(filteredEntries) { entry in
                                journalRow(entry)
                            }
                            inviteLine
                        }
                    }
                    .padding(.leading, 64)
                    .padding(.trailing, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 72)
                    .background(alignment: .topLeading) {
                        // 格线/边线随内容滚动（真本子行为）
                        ZStack(alignment: .topLeading) {
                            RuledLines(topOffset: 12)
                            RoseMarginLines(x: 50)
                        }
                    }
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.immediately)
                #endif

                PunchHoles()

                // 手写页脚
                VStack { Spacer()
                    HStack { Spacer()
                        Text("\(entries.count) words ✦")
                            .font(JournalTheme.serifItalic(15))
                            .foregroundColor(JournalTheme.pencil.opacity(0.75))
                            .rotationEffect(.degrees(-3))
                            .padding(.trailing, 26).padding(.bottom, 18)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: JournalTheme.shadowInk.opacity(0.13), radius: 8, y: 3)

            // 星星贴纸压角（出血，clip 外）
            StarSticker(color: JournalTheme.rose, size: 32)
                .offset(x: -9, y: 560)
            StarSticker(color: JournalTheme.mint, size: 21, rotation: 18)
                .offset(x: 15, y: 582)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .top) {
            WashiTape(color: JournalTheme.mint)
                .rotationEffect(.degrees(-2.5))
                .offset(y: -12)
        }
    }

    /// 搜索行：写在第一行格线上（无框）
    private var searchLine: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(JournalTheme.faint)
            TextField("search, or write a new word…", text: $searchText)
                .textFieldStyle(.plain)
                .font(JournalTheme.serifItalic(14))
                .foregroundColor(JournalTheme.ink)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: searchText) { _, _ in
                    Task { await runSearch() }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(JournalTheme.faint)
                }
                .buttonStyle(.plain)
            }
            Button {
                addDraft = ""
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(JournalTheme.pencil)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: JournalTheme.ruleGap, alignment: .bottom)
        .padding(.bottom, 2)
    }

    /// 空白邀请行
    private var inviteLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
            Text(entries.isEmpty ? "first word goes here…" : "next word goes here…")
                .font(JournalTheme.serifItalic(12.5))
            Spacer()
        }
        .foregroundColor(JournalTheme.faint.opacity(0.8))
        .frame(height: JournalTheme.ruleGap, alignment: .bottom)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            addDraft = ""
            showAddSheet = true
        }
    }


    // MARK: - R3.1 加新词 sheet（复习页加词同款）

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
                    Text(t("Add to notebook", "收进生词本"))
                        .foregroundColor(JournalTheme.faint)
                } footer: {
                    Text(t("Any word, any list — whatever you picked up today. Phrases work too.", "不限词表，今天学到什么收什么。词组也可以。"))
                        .font(.system(size: JournalTheme.F.caption))
                        .foregroundColor(JournalTheme.faint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JournalTheme.sage)
            .navigationTitle(t("Add word", "加词"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { showAddSheet = false }
                        .foregroundColor(JournalTheme.pencil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Add", "收入")) { confirmAdd() }
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
        if let word = VocabCollector.collectManually(rawText: raw, context: modelContext) {
            ToastCenter.shared.show(t("Added “\(word)” ✨", "已收「\(word)」✨"))
            Task { await reload() }
        } else {
            ToastCenter.shared.show(t("That doesn’t look like a word", "这个不适合收词"))
        }
    }

    /// 搜全部单词（13k 词库全量，前缀命中排前，不截断——LazyVStack lazy 渲染）。
    private func runSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            searchResults = []
            return
        }
        let words = await VocabLibrary.shared.words
        let prefix = words.filter { $0.word.lowercased().hasPrefix(q) }
        let sub = words.filter { !$0.word.lowercased().hasPrefix(q) && $0.word.lowercased().contains(q) }
        searchResults = prefix + sub
    }

    /// A-2：搜索结果行（挂主滚动流；词库外词允许 custom 收录）
    @ViewBuilder
    private var searchResultRows: some View {
        let collected = Set(entries.map(\.word))
        let normalized = VocabCollector.normalize(searchText)
        let exactInLibrary = searchResults.contains { $0.word == normalized }

        HStack {
            Text("\(searchResults.count) matches")
                .font(JournalTheme.serifItalic(11))
                .foregroundColor(JournalTheme.faint)
            Spacer()
        }
        .frame(height: JournalTheme.ruleGap, alignment: .bottom)
        .padding(.bottom, 6)

        if !normalized.isEmpty && !exactInLibrary {
            searchRow(word: normalized, definition: t("not in library · added as custom entry", "词库外 · 收为自定义词条"), alreadyIn: collected.contains(normalized))
        }
        ForEach(searchResults) { w in
            searchRow(word: w.word, definition: w.definition, alreadyIn: collected.contains(w.word))
        }
    }

    /// 行 tap 看词详情（释义/考古/注解），✨ 收藏 ⇄ 移出。
    private func searchRow(word: String, definition: String, alreadyIn: Bool) -> some View {
        Button {
            detailEntry = Entry(word: word, definition: definition, status: .unknown, sourceLabel: nil, markedAt: Date())
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(word)
                    .font(JournalTheme.serif(15.5, .semibold))
                    .foregroundColor(JournalTheme.ink)
                    .lineLimit(1)
                    .layoutPriority(2)
                Text(definition.isEmpty ? "…" : definition)
                    .font(.system(size: 12))
                    .foregroundColor(JournalTheme.pencil)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button {
                    collectFromSearch(word: word, alreadyIn: alreadyIn)
                } label: {
                    Image(systemName: alreadyIn ? "sparkles" : "sparkle")
                        .font(.system(size: 13))
                        .foregroundColor(alreadyIn ? JournalTheme.mint : JournalTheme.faint)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: JournalTheme.ruleGap, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func collectFromSearch(word: String, alreadyIn: Bool) {
        if alreadyIn {
            // R3.3 toggle：再按 = 移出生词本（三态标记保留）
            let w = word
            let desc = FetchDescriptor<VocabProgress>(predicate: #Predicate { $0.word == w })
            if let progress = (try? modelContext.fetch(desc))?.first {
                progress.sourceBookRef = nil
                progress.anchorText = nil
                try? modelContext.save()
            }
            ToastCenter.shared.show(t("Removed “\(word)”", "已移出「\(word)」"))
            Task { await reload() }
        } else if VocabCollector.collectManually(rawText: word, context: modelContext) != nil {
            ToastCenter.shared.show(t("Added “\(word)” ✨", "已收「\(word)」✨"))
            // 不清搜索——查词心智下收完继续浏览，行上 ✨ 随 reload 变实心
            Task { await reload() }
        }
    }


    /// R3.1：移出生词本（sourceBookRef 置 nil；刷词的三态标记保留）+ 复习堆同词卡一并删。
    private func removeFromNotebook(_ entry: Entry) {
        let word = entry.word
        let desc = FetchDescriptor<VocabProgress>(predicate: #Predicate { $0.word == word })
        if let progress = (try? modelContext.fetch(desc))?.first {
            progress.sourceBookRef = nil
            progress.anchorText = nil
            try? modelContext.save()
        }
        var cards = VocabCardStore.load()
        if cards.contains(where: { $0.word == word }) {
            cards.removeAll { $0.word == word }
            VocabCardStore.save(cards)
        }
        ToastCenter.shared.show(t("Removed “\(word)”", "已移出「\(word)」"))
        Task { await reload() }
    }

    /// A-2 活页行：一行一词写在格线上（word 衬线 + 释义铅笔灰 + 出处斜体英文 + 两个静音小钮）。
    private func journalRow(_ entry: Entry) -> some View {
        Button {
            Task { await store.jumpToWord(entry.word) }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .strokeBorder(statusColor(entry.status), lineWidth: 2.5)
                    .frame(width: 9, height: 9)

                Text(entry.word)
                    .font(JournalTheme.serif(15.5, .semibold))
                    .foregroundColor(JournalTheme.ink)
                    .lineLimit(1)
                    .layoutPriority(2)

                Text(entry.definition.isEmpty ? "…" : entry.definition)
                    .font(.system(size: 12))
                    .foregroundColor(JournalTheme.pencil)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(entry.sourceLabel != nil ? "book" : "manual")
                    .font(JournalTheme.serifItalic(10.5))
                    .foregroundColor(JournalTheme.rose.opacity(0.9))

                Button {
                    detailEntry = entry
                } label: {
                    Image(systemName: "scroll")
                        .font(.system(size: 11))
                        .foregroundColor(
                            VocabCorpusStore.hasCorpus(for: entry.word) ? JournalTheme.mint : JournalTheme.faint
                        )
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    if deckWords.contains(entry.word) {
                        var cards = VocabCardStore.load()
                        cards.removeAll { $0.word == entry.word }
                        VocabCardStore.save(cards)
                        deckWords.remove(entry.word)
                        ToastCenter.shared.show(t("Removed from review deck", "已从复习牌堆移除"))
                    } else if VocabCardStore.addIfAbsent(word: entry.word, source: "notebook") {
                        deckWords.insert(entry.word)
                        ToastCenter.shared.show(t("“\(entry.word)” added to review 🔁", "「\(entry.word)」已进复习 🔁"))
                    }
                } label: {
                    Image(systemName: "repeat")
                        .font(.system(size: 11))
                        .foregroundColor(deckWords.contains(entry.word) ? JournalTheme.mint : JournalTheme.faint)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: JournalTheme.ruleGap, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            tagMenu(for: entry)
            Button(role: .destructive) {
                removeFromNotebook(entry)
            } label: {
                Label(t("Remove from notebook (also deletes review card)", "移出生词本（复习卡一并删）"), systemImage: "trash")
            }
        }
    }

    /// tag 过滤后的词列表。
    private var filteredEntries: [Entry] {
        guard activeTag != nil else { return entries }
        return entries.filter { taggedWords.contains($0.word) }
    }

    /// tag 滤条（写在一条格线上，斜体微标签，选中=薄荷下划线）。
    private var tagFilterLine: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                tagFilterItem(label: "all", tag: nil)
                ForEach(allTags, id: \.self) { t in
                    tagFilterItem(label: t, tag: t)
                }
            }
            .padding(.trailing, 8)
        }
        .frame(height: JournalTheme.ruleGap, alignment: .center)
    }

    private func tagFilterItem(label: String, tag: String?) -> some View {
        Button {
            activeTag = tag
            taggedWords = tag.map { VocabTagStore.words(tag: $0) } ?? []
        } label: {
            Text(label)
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(activeTag == tag ? JournalTheme.ink : JournalTheme.faint)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    if activeTag == tag {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(JournalTheme.mint.opacity(0.7))
                            .frame(height: 2)
                            .rotationEffect(.degrees(-0.8))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 行长按「标签…」子菜单：已有 tag 打勾切换（横向 tap 防手滑分裂），新建走词详情。
    @ViewBuilder
    private func tagMenu(for entry: Entry) -> some View {
        Menu(t("Tags…", "标签…")) {
            ForEach(allTags, id: \.self) { t in
                Button {
                    VocabTagStore.toggle(word: entry.word, tag: t)
                    refreshTags()
                } label: {
                    if VocabTagStore.tags(word: entry.word).contains(t) {
                        Label(t, systemImage: "checkmark")
                    } else {
                        Text(t)
                    }
                }
            }
            if allTags.isEmpty {
                Text(t("No tags yet — make one from a word’s detail page", "还没有标签，去词详情建一个"))
            }
        }
    }

    private func refreshTags() {
        allTags = VocabTagStore.allTags()
        if let t = activeTag {
            taggedWords = VocabTagStore.words(tag: t)
            if !allTags.contains(t) { activeTag = nil }
        }
    }

    private func statusColor(_ status: VocabStatus) -> Color {
        switch status {
        case .known:   return JournalTheme.mint
        case .slow:    return Color(hex: 0xE89B47)
        case .unknown: return JournalTheme.clay
        }
    }

    // MARK: - 数据

    /// 全量 fetch VocabProgress（量级 = 用户标过/收过的词）+ 内存 filter 收词条目。
    /// optional 谓词有静默不匹配坑，不用 #Predicate 过滤 sourceBookRef。
    private func reload() async {
        refreshTags()
        let all = (try? modelContext.fetch(FetchDescriptor<VocabProgress>())) ?? []
        let collected = all.filter { $0.sourceBookRef != nil }
        deckWords = Set(VocabCardStore.load().map(\.word))

        let words = await VocabLibrary.shared.words
        let defMap = Dictionary(words.map { ($0.word, $0.definition) },
                                uniquingKeysWith: { first, _ in first })

        // 书名解析按 safeName 缓存，一本书只读一次 index.json
        let pid = "default"

        entries = collected.map { p in
            var label: String? = nil
            if let ref = p.sourceBookRef,
               let parsed = VocabStudyView.parseSourceBookRef(ref) {
                label = t("\(parsed.safe) · ch.\(parsed.chapter)", "\(parsed.safe) · 第 \(parsed.chapter) 章")
            }
            return Entry(
                word: p.word,
                definition: defMap[p.word] ?? "",
                status: p.status,
                sourceLabel: label,
                markedAt: p.markedAt
            )
        }
        .sorted { $0.markedAt > $1.markedAt }
        loaded = true
    }

}
