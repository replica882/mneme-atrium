import Foundation

/// 造句题的 AI 静默判分（不进主对话）。ProviderRouter.sendNonStreaming side-call，
/// AUDN 提取 / 做梦同款链路。任何失败返回 nil → UI 降级自评（App 自包含，AI 是增强）。
enum VocabSentenceGrader {

    static let systemPrompt = """
    你是英语用词判分器。用户在练习用目标单词造句，判断句子是否正确、自然地使用了目标词。
    判分标准：词性用对、语义搭配合理、句子本身通顺。轻微拼写或标点瑕疵不扣。
    只输出 JSON，不要解释：
    {"ok": true/false, "feedback": "一句话中文点评；错了指出错在哪并给一个正确示例"}
    """

    static func buildRequest(word: String, definition: String?, sentence: String)
        -> (systemPrompt: String, messages: [(role: String, content: String)]) {
        var user = "目标词：\(word)"
        if let def = definition, !def.isEmpty {
            user += "（\(def)）"
        }
        user += "\n用户造的句子：\(sentence)"
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
