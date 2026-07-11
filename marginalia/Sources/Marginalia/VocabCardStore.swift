import Foundation

/// 复习牌堆的一张卡。文件存储（非 SwiftData——schema 冻结令，CR-2 readingLog 同款先例）。
/// 词面 = id，`VocabCollector.normalize` 后写入。跨楼层（AppSupport 全局目录）。
struct VocabCard: Codable, Identifiable, Equatable {
    var word: String
    var source: String            // manual / quota / screening / notebook / reading
    var createdAt: Date
    var ease: Double = 2.5
    var intervalDays: Double = 0
    var reps: Int = 0
    var lapses: Int = 0
    var dueAt: Date
    var lastReviewedAt: Date? = nil
    /// 配额卡的词书来源（R3.1 换词书立即生效用；老数据/非配额卡 = nil）。
    var quotaSourceId: String? = nil

    var id: String { word }

    init(word: String, source: String, now: Date = Date()) {
        self.word = word
        self.source = source
        self.createdAt = now
        self.dueAt = now          // 新卡当天即到期
    }

    /// SM-2 调度字段的打包视图（SM2.review 进出用）。
    var sm2: SM2State {
        get { SM2State(ease: ease, intervalDays: intervalDays, reps: reps, lapses: lapses) }
        set {
            ease = newValue.ease
            intervalDays = newValue.intervalDays
            reps = newValue.reps
            lapses = newValue.lapses
        }
    }
}

/// 复习流水一行（append-only，保留率统计的原料——v1 只攒不算）。
struct VocabReviewLogEntry: Codable {
    var word: String
    var ts: Date
    var exercise: String
    var rating: String
    var intervalBefore: Double
}

/// cards.json 原子写 + review-log.jsonl append。`dir` 可注入（测试换 tmp 目录）。
enum VocabCardStore {
    static var defaultDir: URL {
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("MemoryPalace", isDirectory: true)
            .appendingPathComponent("vocab", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// 缺文件 / 坏 JSON → []（复习是增强功能，存储坏了不炸 app）。
    static func load(dir: URL = defaultDir) -> [VocabCard] {
        let url = dir.appendingPathComponent("cards.json")
        guard let data = try? Data(contentsOf: url),
              let cards = try? decoder().decode([VocabCard].self, from: data) else { return [] }
        return cards
    }

    static func save(_ cards: [VocabCard], dir: URL = defaultDir) {
        let url = dir.appendingPathComponent("cards.json")
        guard let data = try? encoder().encode(cards) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// 文件层直写加卡（阅读器收词 hook / 「进复习」按钮用——调用点没有 VocabReviewStore 实例，
    /// 复习 tab 下次 bootstrap 自然捞到）。word 需已 normalize。true = 新加。
    @discardableResult
    static func addIfAbsent(word: String, source: String, dir: URL = defaultDir,
                            now: Date = Date()) -> Bool {
        guard !word.isEmpty else { return false }
        var cards = load(dir: dir)
        guard !cards.contains(where: { $0.word == word }) else { return false }
        cards.append(VocabCard(word: word, source: source, now: now))
        save(cards, dir: dir)
        return true
    }

    static func appendLog(_ entry: VocabReviewLogEntry, dir: URL = defaultDir) {
        let url = dir.appendingPathComponent("review-log.jsonl")
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard var data = try? e.encode(entry) else { return }
        data.append(0x0A)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
