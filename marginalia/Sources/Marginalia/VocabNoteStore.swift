import Foundation

/// 词条笔记：`vocab/<word>.md` + 图片附件 `vocab/img/<word>-*.<ext>`（独立目录，纯文件）。
enum VocabNoteStore {

    /// 组件库版存储根：Application Support/Marginalia/<profileId>/。
    /// （记忆花园完整版里笔记住在楼层文件库，AI 的 fs 工具可读写同一篇。）
    static var rootOverride: URL? = nil

    private static func root(_ profileId: String) -> URL {
        let base = rootOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marginalia", isDirectory: true)
        let dir = base.appendingPathComponent(profileId.isEmpty ? "default" : profileId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("vocab/img", isDirectory: true),
                                                 withIntermediateDirectories: true)
        return dir
    }

    private static func url(_ path: String, _ profileId: String) -> URL {
        root(profileId).appendingPathComponent(path)
    }


    /// 词面里文件路径的危险字符换成 "-"（词组空格保留）。
    private static func safeName(_ word: String) -> String {
        word.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    static func notePath(word: String) -> String {
        "vocab/\(safeName(word)).md"
    }

    /// 不存在 → nil（区分"没写过"与"空笔记"）。
    static func readNote(word: String, profileId: String) -> String? {
        let path = notePath(word: word)
        let u = url(path, profileId)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        return try? String(contentsOf: u, encoding: .utf8)
    }

    static func writeNote(word: String, content: String, profileId: String) throws {
        try content.data(using: .utf8)?.write(to: url(notePath(word: word), profileId), options: .atomic)
    }

    /// 缺则建骨架，已有内容不覆盖（幂等）。
    /// seed：旧 VocabProgress.note 的 lazy 迁移入口（R2-2 笔记合并）——只在首次建档时写入。
    static func ensureNote(word: String, profileId: String, seed: String? = nil) {
        guard readNote(word: word, profileId: profileId) == nil else { return }
        var content = "# \(word)\n\n"
        if let seed = seed?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
            content += seed + "\n"
        }
        try? writeNote(word: word, content: content, profileId: profileId)
    }

    // MARK: - 图片附件

    static func imagePaths(word: String, profileId: String) -> [String] {
        let prefix = "\(safeName(word))-"
        let dir = root(profileId).appendingPathComponent("vocab/img", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { "vocab/img/\($0)" }
    }

    static func addImage(word: String, data: Data, ext: String, profileId: String) throws {
        let suffix = UUID().uuidString.prefix(8)
        let path = "vocab/img/\(safeName(word))-\(suffix).\(ext)"
        try data.write(to: url(path, profileId), options: .atomic)
    }

    static func imageData(path: String, profileId: String) -> Data? {
        try? Data(contentsOf: url(path, profileId))
    }

    // MARK: - 双链

    /// `[[词]]` → `[词](vocabnote://open/<encoded>)`（MarkdownUI 链接化，openURL 拦截跳词卡）。
    /// 纯函数（R2-3a 抽出可测）。
    static func linkifiedMarkdown(_ md: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#) else { return md }
        var result = ""
        var last = md.startIndex
        for m in regex.matches(in: md, range: NSRange(md.startIndex..., in: md)) {
            guard let full = Range(m.range, in: md),
                  let inner = Range(m.range(at: 1), in: md) else { continue }
            result += md[last..<full.lowerBound]
            let target = String(md[inner])
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            result += "[\(target)](vocabnote://open/\(encoded))"
            last = full.upperBound
        }
        result += md[last...]
        return result
    }
}
