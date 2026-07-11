import Foundation
import SwiftData
import Observation

/// 单词学习会话的状态中心（@Observable 单 panel 生命周期）。
///
/// 负责：
/// - 筛选偏好（cats / band / hideKnown / onlyGap / search）
/// - 学习游标（filtered / idx / revealed / sessionStart）
/// - mark 写 SwiftData VocabProgress + idx 推进
///
/// 进度数据来源：SwiftData 的 `VocabProgress`，由调用方（VocabPanelView）持有 ModelContext 并传进来。
@Observable
@MainActor
final class VocabSessionStore {
    // MARK: - 筛选偏好

    var selectedCats: Set<String> = []   // empty = 全部
    /// 雅思 4000 虚拟词表（bundle txt，不在 NGSL categories 里）。
    var ieltsOn: Bool = false
    /// tag 过滤（多选，AND 语义：词至少带其中一个 tag）。
    var selectedTags: Set<String> = []
    var band: String? = nil
    var hideKnown: Bool = false
    var onlyGap: Bool = false
    var onlyCollected: Bool = false      // CR-3：只刷书里收的词
    var search: String = ""

    // MARK: - 学习态

    /// 当前应用筛选后的词库（外部触发 `applyFilters` 重算）。
    private(set) var filtered: [VocabWord] = []

    /// 当前词游标，filtered 里第几个。filtered 重算后回 0。
    private(set) var idx: Int = 0

    /// 释义是否已揭示（Space 切换）。
    var revealed: Bool = false

    /// 当前词显示开始时间，mark 时计算 seconds。
    private(set) var sessionStart: Date = Date()

    // MARK: - 全局

    /// 当前 tab（0 学习 / 1 筛选 / 2 统计 / 3 导出）。
    var tab: Int = 0

    /// 词库 actor 状态。
    var libraryLoaded: Bool = false
    var loadError: String? = nil

    // MARK: - Computed

    /// 当前词；filtered 空 / idx 越界返回 nil。
    var currentWord: VocabWord? {
        guard idx >= 0, idx < filtered.count else { return nil }
        return filtered[idx]
    }

    /// 进度比例（0.0–1.0），filtered 空时返回 0。
    var progressRatio: Double {
        guard !filtered.isEmpty else { return 0 }
        return Double(idx) / Double(filtered.count)
    }

    // MARK: - 数据加载

    /// 启动时一次性加载词库 + 初始化默认筛选（核心 5 表）。
    func bootstrap(context: ModelContext) async {
        do {
            try await VocabLibrary.shared.load()
            // 默认勾选核心 5 表（学原 NGSL 的 coreCats 首屏）
            let core = await VocabLibrary.shared.coreCategories
            selectedCats = Set(core)
            libraryLoaded = true
            await applyFilters(context: context)
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Filter

    /// 应用筛选条件，重算 `filtered`，重置游标。
    /// 设置开关「默认随机出词」(`vocabShuffleByDefault`) 开了的话，末尾洗一次牌——
    /// 每次重新筛选都是新的随机顺序。
    func applyFilters(context: ModelContext) async {
        let snapshot = readProgressSnapshot(context: context)
        let ielts = ieltsOn ? VocabReviewStore.loadIELTSWords() : []
        let taggedWords: Set<String>? = selectedTags.isEmpty ? nil :
            selectedTags.reduce(into: Set<String>()) { $0.formUnion(VocabTagStore.words(tag: $1)) }
        var result = await VocabLibrary.shared.filter(
            cats: selectedCats,
            ieltsWords: ielts,
            taggedWords: taggedWords,
            band: band,
            hideKnown: hideKnown,
            onlyGap: onlyGap,
            onlyCollected: onlyCollected,
            collected: Set(snapshot.filter { $0.value.hasSource }.keys),
            search: search,
            progress: snapshot.mapValues(\.status)
        )
        if UserDefaults.standard.bool(forKey: "vocabShuffleByDefault") {
            result.shuffle()
        }
        filtered = result
        idx = 0
        revealed = false
        sessionStart = Date()
    }

    /// 洗牌（"随机"按钮）—— 不重新筛选，只打乱当前 filtered 顺序。
    func shuffleFiltered() {
        filtered.shuffle()
        idx = 0
        revealed = false
        sessionStart = Date()
    }

    // MARK: - 学习交互

    /// 标记当前词。计算 seconds（首露 → mark 的耗时），写 VocabProgress（upsert），推进 idx。
    /// note 不传 = 不动老笔记（R2-2 修复：以前空 draft 覆盖会把旧 note 清空）。
    func markCurrent(status: VocabStatus, note: String? = nil, context: ModelContext) {
        guard let w = currentWord else { return }
        let seconds = Date().timeIntervalSince(sessionStart)

        // upsert：先查同 word 的 progress，有就改，没有就 insert
        let word = w.word
        let descriptor = FetchDescriptor<VocabProgress>(
            predicate: #Predicate { $0.word == word }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.statusRaw = status.rawValue
            existing.seconds = seconds
            if let note { existing.note = note }
            existing.markedAt = Date()
        } else {
            let new = VocabProgress(word: word, status: status, seconds: seconds, note: note ?? "")
            context.insert(new)
        }
        try? context.save()

        advance()
    }

    /// 不标记直接下一个（"N" / "跳过"）。
    func nextWithoutMark() {
        advance()
    }

    /// 揭示/隐藏释义（Space）。
    func toggleReveal() {
        revealed.toggle()
    }

    private func advance() {
        if idx < filtered.count {
            idx += 1
        }
        revealed = false
        sessionStart = Date()
    }

    /// 完成态时调用——重置游标到 0 重头扫一遍。
    func resetIndex() {
        idx = 0
        revealed = false
        sessionStart = Date()
    }

    /// Widget tap 跳进来时，把目标词**插到 filtered 第一个**，标完它继续扫原 filtered。
    /// 如果原 filtered 里本来就有这个词，去重；如果没有（被 hideKnown / onlyGap 排除）
    /// 也强行插进来——保证 widget 跳词不被筛选条件挡住。
    /// 词库查不到（书里收的库外词/词组）→ 造 custom 条目兜底，定义空等 AI 注解（CR-3 P3）。
    func jumpToWord(_ word: String) async {
        let words = await VocabLibrary.shared.words
        let target = words.first(where: { $0.word == word }) ?? VocabWord(
            word: word, definition: "", categories: [], forms: [],
            ranks: nil, priority: .max, notes: "", band: "", scanOrder: 0
        )
        var rest = filtered.filter { $0.word != target.word }
        rest.insert(target, at: 0)
        filtered = rest
        idx = 0
        revealed = false
        sessionStart = Date()
        tab = VocabTab.study.rawValue
    }

    // MARK: - 清空进度

    /// 清空所有 VocabProgress（"清空进度"按钮）。
    func wipeAllProgress(context: ModelContext) async {
        try? context.delete(model: VocabProgress.self)
        try? context.save()
        await applyFilters(context: context)
    }

    // MARK: - SwiftData snapshot

    /// 把 ModelContext 里所有 VocabProgress 抓出来转成 [word: snapshot]。
    /// 词库总量 7090，progress 量远小于此，全 fetch 不爆。
    func readProgressSnapshot(context: ModelContext) -> [String: VocabProgressSnapshot] {
        let descriptor = FetchDescriptor<VocabProgress>()
        guard let all = try? context.fetch(descriptor) else { return [:] }

        var map: [String: VocabProgressSnapshot] = [:]
        for p in all {
            map[p.word] = VocabProgressSnapshot(
                status: p.status,
                seconds: p.seconds,
                note: p.note,
                hasSource: p.sourceBookRef != nil
            )
        }
        return map
    }
}
