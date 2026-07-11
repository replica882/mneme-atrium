import Foundation

/// 词 tag 分组（雅思 a 话题 / b 话题…）。vocab-tags.json（word → [tag]）原子写，
/// 与复习堆 cards.json 同目录同姿势；`dir` 可注入（测试换 tmp，别碰真库的红线）。
enum VocabTagStore {
    static var defaultDir: URL { VocabCardStore.defaultDir }

    /// 缺文件 / 坏 JSON → [:]（tag 是增强功能，存储坏了不炸 app）。
    static func load(dir: URL = defaultDir) -> [String: [String]] {
        let url = dir.appendingPathComponent("vocab-tags.json")
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return map
    }

    static func save(_ map: [String: [String]], dir: URL = defaultDir) {
        let url = dir.appendingPathComponent("vocab-tags.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(map) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func tags(word: String, dir: URL = defaultDir) -> [String] {
        load(dir: dir)[word] ?? []
    }

    /// 全部已有 tag（打标点选用，防"雅思a"/"雅思 a"手滑分裂），按名排序。
    static func allTags(dir: URL = defaultDir) -> [String] {
        Set(load(dir: dir).values.flatMap { $0 }).sorted()
    }

    /// 打上 ⇄ 撤掉（toggle）。tag 两端去空白；空 tag 忽略。
    static func toggle(word: String, tag: String, dir: URL = defaultDir) {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !tag.isEmpty else { return }
        var map = load(dir: dir)
        var tags = map[word] ?? []
        if let idx = tags.firstIndex(of: tag) {
            tags.remove(at: idx)
        } else {
            tags.append(tag)
        }
        map[word] = tags.isEmpty ? nil : tags
        save(map, dir: dir)
    }

    /// 有该 tag 的所有词（滤条过滤用）。
    static func words(tag: String, dir: URL = defaultDir) -> Set<String> {
        Set(load(dir: dir).filter { $0.value.contains(tag) }.keys)
    }
}
