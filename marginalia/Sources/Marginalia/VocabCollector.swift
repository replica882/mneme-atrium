import Foundation
import NaturalLanguage
import SwiftData

/// CR-3 P2：阅读器选词 → 生词本（书词打通的写入口）。
/// 已有该词记录 → 补出处不动学习状态；新词 → unknown 起步。
enum VocabCollector {

    /// 返回 normalize 后的词面（nil = 选段不适合收词）。
    /// sourceBookRef 第三段存章节内字符 offset（vocab 自有格式，与 Note.id 语义无关）。
    @discardableResult
    static func collect(
        rawText: String,
        bookSafeName: String,
        chapter: Int,
        anchorStart: Int,
        context: ModelContext
    ) -> String? {
        let word = canonicalize(rawText)
        guard !word.isEmpty, word.count <= 64 else { return nil }
        let ref = "\(bookSafeName)#chapter\(chapter)#\(anchorStart)"
        let anchor = String(rawText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))

        let desc = FetchDescriptor<VocabProgress>(predicate: #Predicate { $0.word == word })
        if let existing = (try? context.fetch(desc))?.first {
            existing.sourceBookRef = ref
            existing.anchorText = anchor
        } else {
            let p = VocabProgress(word: word, status: .unknown, seconds: 0)
            p.sourceBookRef = ref
            p.anchorText = anchor
            context.insert(p)
        }
        try? context.save()

        // 划词收词同步进复习牌堆（设置开关，默认开；复习 tab 下次 bootstrap 捞到）
        if autoReviewEnabled {
            VocabCardStore.addIfAbsent(word: word, source: "reading", dir: reviewDeckDir)
        }
        return word
    }

    /// 「划词收词进复习」开关（书里划的 + 聊天里划的共用一个语义）。
    static var autoReviewEnabled: Bool {
        (UserDefaults.standard.object(forKey: "vocabReviewAutoFromReading") as? Bool) ?? true
    }

    /// 复习牌堆目录——测试注入 tmp，别污染真库（2026-07-08 测试跑进真 cards.json 的教训）。
    static var reviewDeckDir: URL = VocabCardStore.defaultDir

    /// 词面归一：去首尾空白/标点 + 小写。短语（含空格）原样保留成词组条目。
    static func normalize(_ raw: String) -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,;:!?\"'()[]{}<>“”‘’—–…"))
        return raw.trimmingCharacters(in: trimSet).lowercased()
    }

    /// R5-4/R6 词形归一：划 "switched" 收成 "switch"。normalize 后走
    /// ECDICT 词形反查 → NLTagger lemma 兜底；词组不动。
    /// ⚠️ R6 规则反转：R5 的"自身有词条不归"守卫被 ECDICT 反噬（它对一切变形都有
    /// 词条，switched/abolished 全被挡，归一形同虚设）——改为反查优先 + 歧义白名单。
    static func canonicalize(_ raw: String) -> String {
        canonicalizeCore(normalize(raw), baseForm: VocabDictStore.baseForm(of:))
    }

    /// "既是高频独立词又是不规则变形"的闭集——这些词保留原样不归一。
    static let lemmaAmbiguousWhitelist: Set<String> = [
        "left", "found", "saw", "rose", "lay", "ground", "felt", "bore",
        "bound", "wound", "spoke", "bent", "lit", "shed", "stole", "beat", "fell",
    ]

    /// 归一规则（纯函数可测）。
    static func canonicalizeCore(_ word: String,
                                 baseForm: (String) -> String?) -> String {
        guard !word.isEmpty, !word.contains(" ") else { return word }   // 词组不动
        guard !lemmaAmbiguousWhitelist.contains(word) else { return word }
        if let base = baseForm(word) { return base }
        // 系统 lemmatizer 兜底（离线；孤词要显式钉语言否则识别不出）
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        if let lemma = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased(),
           !lemma.isEmpty, lemma != word {
            return lemma
        }
        return word
    }

    /// 手动收词的出处哨兵（学习卡 ✨ / 生词本搜索收词）。
    /// 生词本判定统一走 `sourceBookRef != nil`；"manual" 解析不出书 ref，出处 chip 自然不显示。
    static let manualSource = "manual"

    /// 聊天收词出处 ref（"chat#<nodeId>"，与书籍 "safeName#chapterN#offset" 同字段分流；
    /// parseSourceBookRef 对它 parts[1] 非 chapter 前缀解析失败，互不误伤）。
    /// 词详情 sheet 里收词（合成锚 vocab:/vocabnote:）→ "vocab#<来源词>"，跳回来源词详情。
    /// thinking sheet（合成锚 thinking:<真nodeId>）→ "thinking#<真id>"（保留标记：
    /// 跳回要自动弹思考链+闪词）。
    /// ⚠️ 新增合成锚（xxx:<...>）必须来这里接分流，否则收词出处会变"原消息已删除"死链。
    static func chatRef(nodeId: String) -> String {
        if nodeId.hasPrefix("vocab:") { return "vocab#\(nodeId.dropFirst("vocab:".count))" }
        if nodeId.hasPrefix("vocabnote:") { return "vocab#\(nodeId.dropFirst("vocabnote:".count))" }
        if nodeId.hasPrefix("thinking:") { return "thinking#\(nodeId.dropFirst("thinking:".count))" }
        return "chat#\(nodeId)"
    }

    /// 解析思考链 ref → 真消息 id（"thinking#<id>"；兼容 R6b 前误存的 "chat#thinking:<id>"）。
    static func parseThinkingRef(_ ref: String) -> String? {
        if ref.hasPrefix("thinking#") {
            let id = String(ref.dropFirst("thinking#".count))
            return id.isEmpty ? nil : id
        }
        if ref.hasPrefix("chat#thinking:") {
            let id = String(ref.dropFirst("chat#thinking:".count))
            return id.isEmpty ? nil : id
        }
        return nil
    }

    /// 解析词详情来源 ref → 来源词；兼容早期误存的 "chat#vocab:<词>"。
    static func parseVocabRef(_ ref: String) -> String? {
        if ref.hasPrefix("vocab#") {
            let w = String(ref.dropFirst("vocab#".count))
            return w.isEmpty ? nil : w
        }
        if ref.hasPrefix("chat#vocab:") {
            let w = String(ref.dropFirst("chat#vocab:".count))
            return w.isEmpty ? nil : w
        }
        if ref.hasPrefix("chat#vocabnote:") {
            let w = String(ref.dropFirst("chat#vocabnote:".count))
            return w.isEmpty ? nil : w
        }
        return nil
    }

    /// 解析聊天 ref → nodeId；非 chat ref / 合成锚 / thinking ref（parseThinkingRef 接管）返回 nil。
    static func parseChatRef(_ ref: String) -> String? {
        guard ref.hasPrefix("chat#") else { return nil }
        let id = String(ref.dropFirst("chat#".count))
        guard !id.isEmpty, !id.hasPrefix("vocab:"), !id.hasPrefix("vocabnote:"),
              !id.hasPrefix("thinking:") else { return nil }
        return id
    }

    /// 思考链弹窗打开请求（来源跳转落地后 ContentView 转发，气泡的 ThinkingDisclosure 认领）。
    static let openThinkingNotification = Notification.Name("vocabOpenThinkingRequested")

    /// 手动收词（无书出处）。已有词只在没出处时补 manual 标记——书出处信息量更大，不覆盖。
    /// anchor：选中处所在句子快照（聊天划词传，拼写题挖空材料）；已有 anchorText 不覆盖。
    /// chatNodeId：聊天收词传所在消息 node → 出处可点跳回原对话；manual 可升级成 chat ref。
    @discardableResult
    static func collectManually(rawText: String, anchor: String? = nil,
                                chatNodeId: String? = nil, context: ModelContext) -> String? {
        let word = canonicalize(rawText)
        guard !word.isEmpty, word.count <= 64 else { return nil }
        let trimmedAnchor = anchor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newRef = chatNodeId.map(chatRef(nodeId:)) ?? manualSource
        let desc = FetchDescriptor<VocabProgress>(predicate: #Predicate { $0.word == word })
        if let existing = (try? context.fetch(desc))?.first {
            if existing.sourceBookRef == nil || existing.sourceBookRef == manualSource {
                existing.sourceBookRef = newRef
            }
            if existing.anchorText?.isEmpty != false, let a = trimmedAnchor, !a.isEmpty {
                existing.anchorText = String(a.prefix(300))
            }
        } else {
            let p = VocabProgress(word: word, status: .unknown, seconds: 0)
            p.sourceBookRef = newRef
            if let a = trimmedAnchor, !a.isEmpty {
                p.anchorText = String(a.prefix(300))
            }
            context.insert(p)
        }
        try? context.save()
        return word
    }

    /// 来源跳转通知（词详情/刷词卡出处点击 → ContentView 导航到聊天原处）。
    static let sourceJumpNotification = Notification.Name("vocabSourceJumpRequested")

    /// 合成划线锚（vocab:<词>/vocabnote:<词>）→ 词；聊天真锚返回 nil（R5-1 收藏页分流用）。
    static func parseVocabAnchor(_ nodeId: String) -> String? {
        if nodeId.hasPrefix("vocab:") {
            let w = String(nodeId.dropFirst("vocab:".count))
            return w.isEmpty ? nil : w
        }
        if nodeId.hasPrefix("vocabnote:") {
            let w = String(nodeId.dropFirst("vocabnote:".count))
            return w.isEmpty ? nil : w
        }
        return nil
    }

    /// 选中位置所在句子（。．.!?！？；;\n 切分，含结尾标点，不截断——存储侧统一 300 字上限）。
    static func sentence(containing range: Range<String.Index>, in text: String) -> String {
        let boundaries: Set<Character> = ["。", "．", ".", "!", "?", "！", "？", "；", ";", "\n"]
        var start = range.lowerBound
        while start > text.startIndex {
            let prev = text.index(before: start)
            if boundaries.contains(text[prev]) { break }
            start = prev
        }
        var end = range.upperBound
        while end < text.endIndex {
            let ch = text[end]
            end = text.index(after: end)
            if boundaries.contains(ch) { break }
        }
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 已收词面集合（书内虚线用）。VocabProgress 量级 = 用户标过的词，全 fetch 不爆。
    static func collectedWords(context: ModelContext) -> [String] {
        let all = (try? context.fetch(FetchDescriptor<VocabProgress>())) ?? []
        return all.map(\.word).filter { !$0.isEmpty }
    }

    // MARK: - aiNote 回填（P3：问{{char}} → turn 收口 → 回答写进词条）

    private static let pendingAskKey = "pendingVocabAsk"

    /// askInChat 发送成功后记录待回填（单值，新问覆盖旧问）。
    static func recordPendingAsk(word: String, conversationId: String) {
        UserDefaults.standard.set(
            ["word": word, "conversationId": conversationId],
            forKey: pendingAskKey
        )
    }

}
