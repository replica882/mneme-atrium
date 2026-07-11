import Foundation

/// 单词词库加载层（actor singleton）。
///
/// - 启动时一次性 load `Resources/ngsl/vocab_gap_words.json`（3.9MB，13k+ 词；注意旧注释曾写 7090 与实际不符）
/// - 从数据本身扫出 categories / bands 列表（不 hardcode）
/// - 提供 filter / stats / export 三个算法（照搬原 `app.js` 的 apply / renderStats / gapRows）
///
/// 词库静态不变，progress 由 SwiftData `VocabProgress` 管。两者在算法层 join。
actor VocabLibrary {
    static let shared = VocabLibrary()

    private(set) var words: [VocabWord] = []
    private(set) var categories: [String] = []  // 9 个，按词数降序
    private(set) var bands: [String] = []       // unique，保留首次出现顺序

    /// 「核心」5 表（原 NGSL coreCats 按钮 hardcode 的）。
    let coreCategories: [String] = [
        "General NGSL",
        "Academic NAWL",
        "TOEIC TSL",
        "Business BSL",
        "Spoken NGSL",
    ]

    private var loaded = false

    private init() {}

    /// 首次调用真加载，后续 no-op（idempotent）。
    /// 失败抛错让 UI 显示出错而不是空数据假装正常。
    func load() async throws {
        guard !loaded else { return }

        guard let url = Bundle.module.url(forResource: "vocab_gap_words", withExtension: "json", subdirectory: "ngsl")
                ?? Bundle.module.url(forResource: "vocab_gap_words", withExtension: "json") else {
            throw VocabLibraryError.resourceMissing
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([VocabWord].self, from: data)

        // 默认按 priority 升序（推荐学习顺序），数据本身已大致排好但保险一次
        words = decoded.sorted { $0.priority < $1.priority }

        // 抽 categories（去重 + 按词数降序，UI 显示用）
        var catCount: [String: Int] = [:]
        for w in words {
            for c in w.categories { catCount[c, default: 0] += 1 }
        }
        categories = catCount.sorted { $0.value > $1.value }.map(\.key)

        // 抽 bands（去重 + 保留首次出现顺序）
        var seenBand = Set<String>()
        var orderedBands: [String] = []
        for w in words where !seenBand.contains(w.band) {
            seenBand.insert(w.band)
            orderedBands.append(w.band)
        }
        bands = orderedBands

        loaded = true
    }

    /// 单词词数（每个 category）。
    func count(in category: String) -> Int {
        words.reduce(0) { $0 + ($1.categories.contains(category) ? 1 : 0) }
    }

    // MARK: - 算法（照搬原 app.js）

    /// 筛选 —— 镜像原 NGSL `apply()`。
    ///
    /// - cats 空集 = 全部（跟原 JS `cats.length && ...` 短路一致）
    /// - band nil = 全部
    /// - hideKnown: 排除 status == .known
    /// - onlyGap: 仅保留 status ∈ {.slow, .unknown}
    /// - search: word + definition + categories + (D4=A: forms) 拼成池，lowercase substring
    /// - 默认排序：跟 `words` 一致（priority 升序）
    func filter(
        cats: Set<String>,
        ieltsWords: [String] = [],
        taggedWords: Set<String>? = nil,
        band: String?,
        hideKnown: Bool,
        onlyGap: Bool,
        onlyCollected: Bool = false,
        collected: Set<String> = [],
        search: String,
        progress: [String: VocabStatus]
    ) -> [VocabWord] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ieltsSet = Set(ieltsWords)

        // 雅思虚拟词表：词库外的雅思词造 minimal 条目拼进池（释义空由 ECDICT 兜底显示）
        var pool = words
        if !ieltsSet.isEmpty {
            let have = Set(words.map(\.word))
            let extras = ieltsWords.enumerated()
                .filter { !have.contains($0.element) }
                .map { i, w in
                    VocabWord(word: w, definition: "", categories: [], forms: [],
                              ranks: nil, priority: 100_000 + i, notes: "",
                              band: "IELTS", scanOrder: 100_000 + i)
                }
            pool += extras
        }

        return pool.filter { w in
            let status = progress[w.word]

            // 词表 OR 雅思：任一命中即过（都空 = 全部）
            let catHit = !cats.isEmpty && w.categories.contains(where: cats.contains)
            let ieltsHit = !ieltsSet.isEmpty && ieltsSet.contains(w.word)
            if (!cats.isEmpty || !ieltsSet.isEmpty) && !catHit && !ieltsHit { return false }

            // tag 过滤（AND 叠加）
            if let taggedWords, !taggedWords.contains(w.word) { return false }
            if let band, w.band != band { return false }
            if hideKnown, status == .known { return false }
            if onlyGap, !(status == .slow || status == .unknown) { return false }
            // CR-3：只刷书里收的词（AND 叠加，与其他 toggle 语义一致）
            if onlyCollected, !collected.contains(w.word) { return false }

            if !q.isEmpty {
                // D4=A: forms 也进 search 池
                let pool = ([w.word, w.definition] + w.categories + w.forms).joined(separator: " ").lowercased()
                if !pool.contains(q) { return false }
            }
            return true
        }
    }

    /// 统计 —— 镜像原 NGSL `renderStats()` 的 group 聚合部分。
    ///
    /// 按 (categories ∪ band) 聚合，每个 group 含 total/seen/slow/unknown。
    /// 排序：(unknown + slow) 降序——找薄弱词表。
    func gapStats(filtered: [VocabWord], progress: [String: VocabStatus]) -> [GapGroup] {
        var groups: [String: GapGroupAcc] = [:]

        for w in filtered {
            let st = progress[w.word]
            for c in w.categories {
                groups[c, default: GapGroupAcc()].add(status: st)
            }
            groups[w.band, default: GapGroupAcc()].add(status: st)
        }

        return groups.map { GapGroup(name: $0.key, acc: $0.value) }
            .sorted { ($0.unknown + $0.slow) > ($1.unknown + $1.slow) }
    }

    /// 导出行 —— 镜像原 NGSL `gapRows()`。
    ///
    /// 仅 status ∈ {.slow, .unknown} 的词，字段：
    /// `[word, definition, categories(';' 连), forms(',' 连), status.raw, seconds, note]`。
    /// 第一行返回 header（方便 CSV/TSV 直接拼装）。
    func gapRows(progress: [String: VocabProgressSnapshot]) -> [[String]] {
        let header = ["word", "definition", "categories", "forms", "status", "seconds", "note"]
        var rows: [[String]] = [header]

        for w in words {
            guard let p = progress[w.word], p.status == .slow || p.status == .unknown else { continue }
            rows.append([
                w.word,
                w.definition,
                w.categories.joined(separator: "; "),
                w.forms.joined(separator: ", "),
                p.status.rawValue,
                String(format: "%.1f", p.seconds),
                p.note,
            ])
        }
        return rows
    }
}

// MARK: - 算法用的小数据结构

/// 缺口聚合行（statsView 展示）。
struct GapGroup: Identifiable, Hashable {
    let name: String
    let total: Int
    let seen: Int
    let slow: Int
    let unknown: Int

    var id: String { name }

    init(name: String, acc: GapGroupAcc) {
        self.name = name
        self.total = acc.total
        self.seen = acc.seen
        self.slow = acc.slow
        self.unknown = acc.unknown
    }
}

/// 聚合中间态（filter 时累加用）。
struct GapGroupAcc {
    var total = 0
    var seen = 0
    var slow = 0
    var unknown = 0

    mutating func add(status: VocabStatus?) {
        total += 1
        if status != nil { seen += 1 }
        if status == .slow { slow += 1 }
        if status == .unknown { unknown += 1 }
    }
}

/// 导出用的 progress 快照（从 SwiftData VocabProgress 读出来传给 actor，
/// 避免 actor 内直接访 ModelContext）。
struct VocabProgressSnapshot {
    let status: VocabStatus
    let seconds: Double
    let note: String
    /// 有收词出处（sourceBookRef 非空）= 生词本条目（CR-3「只看生词本」筛选用）。
    var hasSource: Bool = false
}

enum VocabLibraryError: Error, LocalizedError {
    case resourceMissing

    var errorDescription: String? {
        switch self {
        case .resourceMissing: return "word library resource missing (Resources/ngsl/vocab_gap_words.json)"
        }
    }
}
