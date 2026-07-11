import Foundation

/// R3.4b 内嵌词典：ECDICT（MIT）按词表裁的子集（音标/中文释义/词形，26k 词 2.9MB）。
/// 数据管线 `scripts/vocab/gen-ecdict-subset.py`；牛津系统词典仍是补充入口（词表外的词）。
enum VocabDictStore {

    struct Entry: Codable {
        var p: String?   // 音标
        var t: String?   // 中文释义（多行）
        var x: String?   // 词形变化 "d:brewed/i:brewing/s:brews"
    }

    /// 首次访问懒加载（2.9MB JSON，几十 ms，off-main 调用方自理；查询 O(1)）。
    private static let index: [String: Entry] = {
        guard let url = Bundle.module.url(forResource: "ecdict_subset", withExtension: "json", subdirectory: "ngsl")
                ?? Bundle.module.url(forResource: "ecdict_subset", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return map
    }()

    static func entry(for word: String) -> Entry? {
        index[word.lowercased()]
    }

    /// 词形反查（form → 原形，R5-4 归一用）：exchange 建表懒加载一次。
    /// ⚠️ 只收真变形 role（p/d/i/3/s/r/t）——role "0" 是"此词的原型"指针、"1" 是
    /// 变形方式标记，收进来会造成 abandon→abandoned 倒挂（R6 测试抓的）。
    /// 同 form 撞多个 base 时取字典序小的（确定性）。
    private static let reverseFormIndex: [String: String] = {
        let realFormRoles: Set<String> = ["p", "d", "i", "3", "s", "r", "t"]
        var map: [String: String] = [:]
        for (word, entry) in index {
            guard let x = entry.x else { continue }
            for part in x.split(separator: "/") {
                let pieces = part.split(separator: ":", maxSplits: 1)
                guard pieces.count == 2, realFormRoles.contains(String(pieces[0])) else { continue }
                let f = String(pieces[1]).trimmingCharacters(in: .whitespaces).lowercased()
                guard !f.isEmpty, f != word else { continue }
                if let cur = map[f], cur <= word { continue }
                map[f] = word
            }
        }
        return map
    }()

    /// "abolished" → "abolish"；查不到返回 nil。
    static func baseForm(of word: String) -> String? {
        reverseFormIndex[word.lowercased()]
    }

    /// exchange 字段拆词形列表（前缀 d/i/s/3/p… 是语法角色标记，展示只要词面，去重保序）。
    static func forms(from exchange: String?) -> [String] {
        guard let exchange, !exchange.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for part in exchange.split(separator: "/") {
            let pieces = part.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let form = String(pieces[1]).trimmingCharacters(in: .whitespaces)
            if !form.isEmpty, !seen.contains(form) {
                seen.insert(form)
                out.append(form)
            }
        }
        return out
    }
}
