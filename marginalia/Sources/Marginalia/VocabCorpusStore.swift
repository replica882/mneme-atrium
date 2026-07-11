import Foundation

/// 考古语料索引（CR-3 P3）。语料 = `Resources/vocab-corpus/%04d-{word}.md`，
/// xcodegen 平铺进 bundle root（与 ngsl 同款行为），按文件名 pattern 过滤建索引。
/// 增量语料由 cc-bridge 续写触发器夜跑写 repo，随下次装包到达设备。
public enum VocabCorpusStore {
    /// 考古产物到达（宿主回投 saveLive 后 post，词详情即刻刷新）。
    public static let corpusArrivedNotification = Notification.Name("marginaliaCorpusArrived")


    /// word（小写）→ 语料 URL。首次访问构建一次（几百条，枚举 + 文件名解析，毫秒级）。
    /// ⚠️ urls(forResourcesWithExtension:subdirectory:) 对不存在的子目录返回**空数组不是 nil**，
    /// `??` 回落永不触发——上线起 index 一直是空的（"abolish 看不见"07-10 事故），显式判空回落。
    private static let index: [String: URL] = {
        var urls = Bundle.module.urls(forResourcesWithExtension: "md", subdirectory: "vocab-corpus") ?? []
        if urls.isEmpty {
            urls = Bundle.module.urls(forResourcesWithExtension: "md", subdirectory: nil) ?? []
        }
        var map: [String: URL] = [:]
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            // 语料命名 %04d-word（word 可含连字符）；bundle 里其他 md 不匹配自然排除
            let parts = name.split(separator: "-", maxSplits: 1)
            guard parts.count == 2, parts[0].count == 4, Int(parts[0]) != nil else { continue }
            map[String(parts[1]).lowercased()] = url
        }
        print("[PROBE] vocab corpus index: \(map.count) entries")
        return map
    }()

    static func markdown(for word: String) -> String? {
        // R3-3 live 覆盖层优先：考古按钮产物即刻可见，装包后 bundle 追上
        if let live = try? String(contentsOf: liveURL(for: word), encoding: .utf8), !live.isEmpty {
            return live
        }
        guard let url = index[word.lowercased()] else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    static func hasCorpus(for word: String) -> Bool {
        index[word.lowercased()] != nil
            || FileManager.default.fileExists(atPath: liveURL(for: word).path)
    }

    // MARK: - R3-3 live 覆盖层（考古按钮回投落地）

    private static var liveDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vocab-corpus-live", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func liveURL(for word: String) -> URL {
        let safe = word.lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return liveDir.appendingPathComponent("\(safe).md")
    }

    public static func saveLive(word: String, markdown: String) {
        try? markdown.data(using: .utf8)?.write(to: liveURL(for: word), options: .atomic)
    }
}
