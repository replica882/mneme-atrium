import Foundation

/// 造句题的 AI 静默判分（不进主对话）。ProviderRouter.sendNonStreaming side-call，
/// AUDN 提取 / 做梦同款链路。任何失败返回 nil → UI 降级自评（App 自包含，AI 是增强）。
enum VocabSentenceGrader {

    static let systemPrompt = """
    You grade English vocabulary usage. The user is practicing a target word in a sentence \
    they wrote — judge whether it\'s used correctly and naturally.
    Criteria: right part of speech, sensible collocation, the sentence reads naturally. \
    Minor spelling/punctuation slips don\'t count against it.
    Output JSON only, no explanation:
    {"ok": true/false, "feedback": "one-sentence note; if wrong, say what\'s off and give a correct example"}
    """

    static func buildRequest(word: String, definition: String?, sentence: String)
        -> (systemPrompt: String, messages: [(role: String, content: String)]) {
        var user = "Target word: \(word)"
        if let def = definition, !def.isEmpty {
            user += " (\(def))"
        }
        user += "\nUser\'s sentence: \(sentence)"
        return (systemPrompt: systemPrompt, messages: [(role: "user", content: user)])
    }

    /// 严格 JSON → 兜底从文本抽 JSON 块。ok 字段缺失 = 解析失败。
    static func parse(_ response: String) -> (ok: Bool, feedback: String)? {
        if let r = parseJSON(response) { return r }
        if let range = response.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression),
           let r = parseJSON(String(response[range])) {
            return r
        }
        return nil
    }

    private static func parseJSON(_ json: String) -> (ok: Bool, feedback: String)? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = obj["ok"] as? Bool else { return nil }
        return (ok, obj["feedback"] as? String ?? "")
    }

    /// 组件库版判分：经 VocabBridge.gradeSentence（宿主接自己的 LLM）；
    /// 未接 bridge / 失败 → nil = 复习卡降自评（主库同款降级路径）。
    @MainActor
    static func grade(word: String, definition: String?, sentence: String,
                      via bridge: VocabBridge) async -> (ok: Bool, feedback: String)? {
        guard let grade = bridge.gradeSentence else { return nil }
        let request = buildRequest(word: word, definition: definition, sentence: sentence)
        guard let raw = await grade(request.systemPrompt, request.messages[0].content) else { return nil }
        // 剥 ```json 围栏（模型习惯性包裹）
        let cleaned = raw.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return parseJSON(cleaned)
    }
}
