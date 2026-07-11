import SwiftUI
import JournalKit

/// 筛选 tab。
///
/// - 9 个 categories prill 多选 + 词数小字
/// - 快捷按钮：全选 / 核心 5 / 清空 / 随机
/// - band 下拉
/// - hideKnown / onlyGap 两个 toggle
/// - search 输入框
/// - 改任意一项 → 立即 applyFilters（7090 词内存 filter <10ms 不需 debounce）
struct VocabFilterView: View {
    @Bindable var store: VocabSessionStore
    @Environment(\.modelContext) private var modelContext

    @State private var allCategories: [String] = []
    @State private var allBands: [String] = []
    @State private var coreCats: [String] = []
    @State private var catCounts: [String: Int] = [:]
    /// 雅思 4000 虚拟词表词数（bundle txt）。
    @State private var ieltsCount: Int = 0
    /// 全库已有 tag（VocabTagStore）。
    @State private var allTags: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // R2-1 模型 A：语义钉死，避免与复习词书混淆
                Text(t("Filters only affect the words tab — the review wordbook is picked on the review tab", "筛选只影响刷词；复习的词书在复习页选"))
                    .font(.system(size: JournalTheme.F.caption))
                    .foregroundColor(JournalTheme.faint)
                searchSection
                categoriesSection
                if !allTags.isEmpty {
                    tagsSection
                }
                bandSection
                togglesSection
                Color.clear.frame(height: 16)
            }
            .padding(16)
        }
        .task {
            await loadMeta()
        }
    }

    private func loadMeta() async {
        let lib = VocabLibrary.shared
        allCategories = await lib.categories
        allBands = await lib.bands
        coreCats = lib.coreCategories
        // 计算每个 category 的词数
        var counts: [String: Int] = [:]
        for c in allCategories {
            counts[c] = await lib.count(in: c)
        }
        catCounts = counts
        ieltsCount = VocabReviewStore.loadIELTSWords().count
        allTags = VocabTagStore.allTags()
    }

    private func reapply() {
        Task { await store.applyFilters(context: modelContext) }
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(t("Search", "搜索"))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(JournalTheme.faint)
                TextField("word / definition / category / forms", text: $store.search)
                    .textFieldStyle(.plain)
                    .foregroundColor(JournalTheme.ink)
                    .onChange(of: store.search) { _, _ in reapply() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(JournalTheme.wash.opacity(0.5), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader(t("Word lists (multi-select)", "词表（多选）"))
                Spacer()
                Text("\(store.selectedCats.count) / \(allCategories.count)")
                    .font(.system(size: JournalTheme.F.caption))
                    .foregroundColor(JournalTheme.faint)
            }

            // 快捷按钮
            HStack(spacing: 8) {
                quickBtn(t("all", "全选")) {
                    store.selectedCats = Set(allCategories)
                    store.ieltsOn = true
                    reapply()
                }
                quickBtn(t("core 5", "核心 5")) {
                    store.selectedCats = Set(coreCats)
                    reapply()
                }
                quickBtn(t("clear", "清空")) {
                    store.selectedCats = []
                    store.ieltsOn = false
                    reapply()
                }
                quickBtn(t("shuffle", "随机")) {
                    store.shuffleFiltered()
                }
            }

            // 9 个 category pill + 雅思虚拟词表（bundle txt，不在 NGSL categories 里）
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(allCategories, id: \.self) { c in
                    catPill(c)
                }
                ieltsPill
            }
        }
    }

    private func catPill(_ c: String) -> some View {
        let selected = store.selectedCats.contains(c)
        let count = catCounts[c] ?? 0
        return Button {
            if selected { store.selectedCats.remove(c) } else { store.selectedCats.insert(c) }
            reapply()
        } label: {
            HStack(spacing: 4) {
                Text(c)
                    .font(.system(size: JournalTheme.F.secondary, weight: .medium))
                Text("\(count)")
                    .font(.system(size: JournalTheme.F.caption))
                    .foregroundColor(selected ? Color.white.opacity(0.8) : JournalTheme.faint)
            }
            .foregroundColor(selected ? .white : JournalTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selected ? JournalTheme.mint : JournalTheme.wash.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var ieltsPill: some View {
        Button {
            store.ieltsOn.toggle()
            reapply()
        } label: {
            HStack(spacing: 4) {
                Text(t("IELTS 4000", "雅思 4000"))
                    .font(.system(size: JournalTheme.F.secondary, weight: .medium))
                Text("\(ieltsCount)")
                    .font(.system(size: JournalTheme.F.caption))
                    .foregroundColor(store.ieltsOn ? Color.white.opacity(0.8) : JournalTheme.faint)
            }
            .foregroundColor(store.ieltsOn ? .white : JournalTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(store.ieltsOn ? JournalTheme.mint : JournalTheme.wash.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tags

    /// 标签节（tag 系统打的分组：雅思 a 话题…），多选，词至少带其中一个。
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader(t("Tags (multi-select)", "标签（多选）"))
                Spacer()
                if !store.selectedTags.isEmpty {
                    Button(t("clear", "清空")) {
                        store.selectedTags = []
                        reapply()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: JournalTheme.F.caption))
                    .foregroundColor(JournalTheme.faint)
                }
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(allTags, id: \.self) { t in
                    tagPill(t)
                }
            }
        }
    }

    private func tagPill(_ t: String) -> some View {
        let selected = store.selectedTags.contains(t)
        return Button {
            if selected { store.selectedTags.remove(t) } else { store.selectedTags.insert(t) }
            reapply()
        } label: {
            Text(t)
                .font(.system(size: JournalTheme.F.secondary, weight: .medium))
                .foregroundColor(selected ? .white : JournalTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selected ? JournalTheme.mint : JournalTheme.wash.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Band

    private var bandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(t("Band (single-select)", "频段（单选）"))
            Picker(t("Band", "频段"), selection: Binding(
                get: { store.band ?? "" },
                set: { v in
                    store.band = v.isEmpty ? nil : v
                    reapply()
                }
            )) {
                Text(t("all", "全部")).tag("")
                ForEach(allBands, id: \.self) { b in
                    Text(b).tag(b)
                }
            }
            .pickerStyle(.menu)
            .tint(JournalTheme.mint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(JournalTheme.wash.opacity(0.5), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(t("What to do with known words", "学过的怎么处理"))
            Toggle(t("Hide words you know", "隐藏已认识的词"), isOn: $store.hideKnown)
                .onChange(of: store.hideKnown) { _, _ in reapply() }
                .toggleStyle(SwitchToggleStyle(tint: JournalTheme.mint))
            Toggle(t("Only show gaps (slow / unknown)", "只看缺口（反应慢 / 不认识）"), isOn: $store.onlyGap)
                .onChange(of: store.onlyGap) { _, _ in reapply() }
                .toggleStyle(SwitchToggleStyle(tint: JournalTheme.mint))
            Toggle(t("Only show notebook words", "只看生词本"), isOn: $store.onlyCollected)
                .onChange(of: store.onlyCollected) { _, _ in reapply() }
                .toggleStyle(SwitchToggleStyle(tint: JournalTheme.mint))
        }
        .foregroundColor(JournalTheme.ink)
        .font(.system(size: JournalTheme.F.body))
    }

    // MARK: - 小工具

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: JournalTheme.F.sectionHeader, weight: .semibold))
            .foregroundColor(JournalTheme.pencil)
    }

    private func quickBtn(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: JournalTheme.F.caption, weight: .medium))
                .foregroundColor(JournalTheme.pencil)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .stroke(JournalTheme.wash.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
