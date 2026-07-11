import Foundation
import Observation

/// 每日配额的词书来源（R2-1 模型 A：筛选页只管刷词，词书只管复习供卡）。
enum VocabQuotaSource: String, CaseIterable, Identifiable {
    case ngsl, ielts, gap, notebook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ngsl:     return t("NGSL wordlist", "NGSL 词表")
        case .ielts:    return t("IELTS dig list", "雅思考古表")
        case .gap:      return t("gaps (marked slow/unknown)", "缺口（标过慢/不认识）")
        case .notebook: return t("notebook", "生词本")
        }
    }

    /// A-3 复习页头的英文微标签。
    var journalLabel: String {
        switch self {
        case .ngsl:     return "NGSL"
        case .ielts:    return "IELTS list"
        case .gap:      return "gaps"
        case .notebook: return t("notebook", "生词本")
        }
    }
}

/// 「复习」tab 的会话中枢：牌堆内存持有（变更即落盘）+ 今日队列 + 评分推进。
/// 与筛选机制（VocabSessionStore/VocabProgress）完全分开，只单向读筛选的 known 集。
@Observable
@MainActor
final class VocabReviewStore {
    /// 全牌堆。任何变更调用方负责随手 persist()。
    var cards: [VocabCard] = []

    /// 今日队列（word 列表，due 升序）。bootstrap 时构建，submitRating 消费。
    private(set) var queue: [String] = []
    private(set) var idx: Int = 0

    /// 存储目录（测试注入 tmp）。
    let dir: URL

    init(dir: URL = VocabCardStore.defaultDir) {
        self.dir = dir
    }

    var currentCard: VocabCard? {
        guard idx >= 0, idx < queue.count else { return nil }
        let word = queue[idx]
        return cards.first { $0.word == word }
    }

    var currentExercise: VocabExercise {
        guard let c = currentCard else { return .read }
        return SM2.exercise(reps: c.reps, intervalDays: c.intervalDays)
    }

    /// 今日已复习张数（完成态成绩感）。
    func reviewedTodayCount(now: Date = Date()) -> Int {
        let startOfDay = Calendar.current.startOfDay(for: now)
        return cards.filter { ($0.lastReviewedAt ?? .distantPast) >= startOfDay }.count
    }

    /// 明日到期数（清完态的「明天见」文案用）。
    func dueCount(within days: Double, from now: Date = Date()) -> Int {
        let end = now.addingTimeInterval(days * 86_400)
        return cards.filter { $0.dueAt > now && $0.dueAt <= end }.count
    }

    // MARK: - 启动

    /// load 落盘牌堆 → 换词书回收 → 配额供新卡 → 建今日队列。
    /// - knownWords: 筛选机制标过 known 的词（配额跳过）
    /// - quota: 每日新卡配额（0 = 关）
    /// - library: 词表（priority 序）；quota 0 时不用
    /// - quotaSourceId: 当前词书（VocabQuotaSource.rawValue）——今天供的、还没碰过的
    ///   异词书配额卡回收重供（R3.1 换词书立即生效；复习过的劳动保留）
    /// - dailyCap: 每日复习总量上限（0 = 不限）。队列 = 到期卡取前 (cap - 今日已复习)，
    ///   截掉的到期卡明天照旧 due（SM-2 逾期答对间隔照常涨，无算法伤害，只是消化慢）。
    func bootstrap(knownWords: Set<String>, quota: Int, now: Date = Date(),
                   library: [VocabWord] = [],
                   quotaSourceId: String = VocabQuotaSource.ngsl.rawValue,
                   dailyCap: Int = 0) {
        cards = VocabCardStore.load(dir: dir)

        let startOfDay = Calendar.current.startOfDay(for: now)

        // 换词书立即生效：一次没复习过的异源配额卡 → 全部回收（不限哪天供的——
        // 没碰过的自动供卡不承载劳动；只清"今天供的"修窄过一次，昨天的旧供卡
        // 压在队列头让粟粟切了雅思还看到 Be）
        let before = cards.count
        cards.removeAll {
            $0.source == "quota" && $0.lastReviewedAt == nil && $0.quotaSourceId != quotaSourceId
        }
        let purged = before - cards.count

        // 配额供卡：今天已供数（回收后）不足则按词表序补
        let suppliedToday = cards.filter { $0.source == "quota" && $0.createdAt >= startOfDay }.count
        let need = max(0, quota - suppliedToday)
        if need > 0 {
            let picked = Self.quotaWords(
                library: library,
                existing: Set(cards.map(\.word)),
                known: knownWords,
                quota: need
            )
            for w in picked {
                var card = VocabCard(word: w, source: "quota", now: now)
                card.quotaSourceId = quotaSourceId
                cards.append(card)
            }
            if !picked.isEmpty || purged > 0 { persist() }
        } else if purged > 0 {
            persist()
        }

        rebuildQueue(now: now, dailyCap: dailyCap)
    }

    /// 今日队列 = dueAt ≤ 今天 23:59:59，due 升序，日上限截断。
    private func rebuildQueue(now: Date, dailyCap: Int = 0) {
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 - 1)
        var due = cards
            .filter { $0.dueAt <= endOfDay }
            .sorted { $0.dueAt < $1.dueAt }
            .map(\.word)
        if dailyCap > 0 {
            let remaining = Self.capRemaining(cap: dailyCap, reviewedToday: reviewedTodayCount(now: now))
            due = Array(due.prefix(remaining))
        }
        queue = due
        idx = 0
    }

    /// 今日还能复习几张（纯函数可测）。
    static func capRemaining(cap: Int, reviewedToday: Int) -> Int {
        max(0, cap - reviewedToday)
    }

    // MARK: - 供给

    /// 按词书来源构建配额词表。纯函数可测。
    /// - ngsl: 原表（priority 序）
    /// - ielts: 表内顺序；在 NGSL 里的词借它的释义，表外词造 minimal 条目（释义空等笔记/AI）
    /// - gap: NGSL 中筛选标过 slow/unknown 的词（priority 序）
    /// - notebook: 收过的词（调用方按收词时间倒序传入）
    static func quotaLibrary(source: VocabQuotaSource, ngsl: [VocabWord],
                             ielts: [String], gapWords: Set<String>,
                             notebookWords: [String]) -> [VocabWord] {
        switch source {
        case .ngsl:
            return ngsl
        case .ielts:
            let byWord = Dictionary(ngsl.map { ($0.word, $0) }, uniquingKeysWith: { a, _ in a })
            return ielts.enumerated().map { i, w in byWord[w] ?? minimalWord(w, order: i) }
        case .gap:
            return ngsl.filter { gapWords.contains($0.word) }
        case .notebook:
            let byWord = Dictionary(ngsl.map { ($0.word, $0) }, uniquingKeysWith: { a, _ in a })
            return notebookWords.enumerated().map { i, w in byWord[w] ?? minimalWord(w, order: i) }
        }
    }

    private static func minimalWord(_ word: String, order: Int) -> VocabWord {
        VocabWord(word: word, definition: "", categories: [], forms: [],
                  ranks: nil, priority: order, notes: "", band: "", scanOrder: order)
    }

    /// 雅思考古表（bundle txt 一行一词，就是夜跑考古用的那张表）。
    static func loadIELTSWords() -> [String] {
        guard let url = Bundle.module.url(forResource: "ielts_wordlist", withExtension: "txt", subdirectory: "ngsl")
                ?? Bundle.module.url(forResource: "ielts_wordlist", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.split(separator: "\n")
            .map { VocabCollector.normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// 词表序（priority 升序，调用方保证）取缺口词。纯函数可测。
    static func quotaWords(library: [VocabWord], existing: Set<String>,
                           known: Set<String>, quota: Int) -> [String] {
        guard quota > 0 else { return [] }
        var out: [String] = []
        for w in library where !existing.contains(w.word) && !known.contains(w.word) {
            out.append(w.word)
            if out.count == quota { break }
        }
        return out
    }

    /// 拼写题出题材料（不含词面）：释义 → 出处原句挖空 → 笔记摘录 → degraded（降认读）。
    /// 纯函数可测。挖空大小写不敏感；纯字母数字词加整词边界，词组直接匹配。
    static func spellMaterial(word: String, definition: String?, anchorText: String?,
                              note: String?) -> (prompt: String, degraded: Bool) {
        if let def = definition, !def.isEmpty { return (def, false) }

        if let anchor = anchorText, !anchor.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: word)
            let boundary = word.allSatisfy { $0.isLetter || $0.isNumber }
            let pattern = "(?i)" + (boundary ? "\\b\(escaped)\\b" : escaped)
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(anchor.startIndex..., in: anchor)
                if regex.firstMatch(in: anchor, range: range) != nil {
                    let blanked = regex.stringByReplacingMatches(
                        in: anchor, range: range, withTemplate: "____")
                    return ("\u{201C}\(blanked)\u{201D}", false)
                }
            }
        }

        if let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return (String(n.prefix(120)), false)
        }

        return ("", true)
    }

    /// 手动/送入加卡。归一词面 + 去重。true = 新加（同时进今日队列尾）。
    @discardableResult
    func addCard(rawWord: String, source: String, now: Date = Date()) -> Bool {
        let word = VocabCollector.canonicalize(rawWord)
        guard !word.isEmpty, word.count <= 64 else { return false }
        guard !cards.contains(where: { $0.word == word }) else { return false }
        cards.append(VocabCard(word: word, source: source, now: now))
        persist()
        if !queue.contains(word) { queue.append(word) }
        return true
    }

    // MARK: - 评分

    /// SM-2 推进当前卡 + 写流水 + 游标前进。
    func submitRating(_ rating: SM2Rating, exercise: VocabExercise, now: Date = Date()) {
        guard let card = currentCard,
              let i = cards.firstIndex(where: { $0.word == card.word }) else { return }

        VocabCardStore.appendLog(
            VocabReviewLogEntry(word: card.word, ts: now, exercise: exercise.rawValue,
                                rating: rating.rawValue, intervalBefore: card.intervalDays),
            dir: dir
        )

        var updated = cards[i]
        let next = SM2.review(updated.sm2, rating: rating)
        updated.sm2 = next
        updated.dueAt = SM2.nextDue(after: next, from: now)
        updated.lastReviewedAt = now
        cards[i] = updated
        persist()

        idx += 1
    }

    /// 从牌堆移除当前卡（R3.2：手动加的/配额卡在生词本够不着，复习卡长按删）。
    /// 队列同步剔除，游标自然指向下一张。
    func removeCurrentCard() {
        guard idx >= 0, idx < queue.count else { return }
        let word = queue[idx]
        cards.removeAll { $0.word == word }
        queue.remove(at: idx)
        persist()
    }

    private func persist() {
        VocabCardStore.save(cards, dir: dir)
    }
}
