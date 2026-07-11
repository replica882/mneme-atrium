import Foundation

/// 词库单词条目（静态数据，bundle JSON 加载）。
///
/// 数据源：`Resources/ngsl/vocab_gap_words.json`（粟粟 NGSL 项目 build 产物）。
/// 7090 词 × 9 词表。**不进 SwiftData**——纯静态，由 `VocabLibrary` actor 加载缓存。
///
/// Schema 跟原 NGSL JSON 完全对应（保留英文字段名，方便比对/导出）。
struct VocabWord: Codable, Identifiable, Hashable {
    /// 词面（英文），同时作为唯一 id（数据保证 unique）。
    let word: String

    /// 释义（中或英，原数据混合）。
    let definition: String

    /// 该词所属的词表名（多对多），例 `["General NGSL", "Spoken NGSL"]`。
    let categories: [String]

    /// 词形变化（如 be 的 are/am/is/was…），可能为空数组。
    let forms: [String]

    /// 各词表里的排名 + SFI 频次指数 + 原始频次。MVP 阶段不展示，预留。
    let ranks: [String: VocabRank]?

    /// 推荐学习顺序数字（小到大优先），默认排序键。
    let priority: Int

    /// 备注（原数据多为空，重写后让用户写到 `VocabProgress.note`）。
    let notes: String

    /// 频段标签，例 `"NGSL 1-500"` / `"Specialized / overlap"`。
    let band: String

    /// 扫词全局序号（数据生成时的扫描顺序）。
    let scanOrder: Int

    var id: String { word }

    enum CodingKeys: String, CodingKey {
        case word, definition, categories, forms, ranks, priority, notes, band
        case scanOrder = "scan_order"
    }
}

/// 单个词表中该词的排名 + SFI（标准频次指数）+ 原始频次。
struct VocabRank: Codable, Hashable {
    let rank: Int?
    let sfi: Double?
    let freq: Double?
}
