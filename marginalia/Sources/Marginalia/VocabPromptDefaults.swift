import Foundation

/// 「问 {{char}}」按钮的 prompt 模板默认值 + 占位符渲染。
///
/// 用户可以在「设置 → 单词」/ vocab panel 齿轮按钮里改这个模板
/// （存进 `@AppStorage("vocabAskPromptTemplate")`），改坏了可恢复默认。
enum VocabPromptDefaults {
    /// 默认模板，含全部 7 个占位符 ({forms}/{status} 空时整行删)。
    static let template: String = """
    「{word}」
    - 释义：{definition}
    - 频段：{band}
    - 出现于：{categories}
    - 词形：{forms}
    - 我刚标的状态：{status}

    {assistantName}，帮我把这个词讲透。可以举例句、对比近义词、或者帮我联想记忆。
    """

    /// 占位符说明 —— 设置面板展示给用户看。
    static let placeholderDocs: [(key: String, desc: String)] = [
        ("word", "the word itself (e.g. apple)"),
        ("definition", "definition"),
        ("band", "frequency band (e.g. NGSL 1-500)"),
        ("categories", "word lists, comma-separated (e.g. General NGSL, Spoken NGSL)"),
        ("forms", "word forms, comma-separated. Whole line omitted if empty"),
        ("status", "current status (known / slow / unknown). Whole line omitted if unmarked"),
        ("assistantName", "the assistant’s name"),
    ]

    /// 渲染：把 `{key}` 替换成对应 value。
    /// 行内含 `{forms}` 或 `{status}` 且对应值为空时，**整行删**（避免出现 "- 词形：" 这种空冒号）。
    static func render(template: String, vars: [String: String]) -> String {
        let conditionalKeys: Set<String> = ["forms", "status"]

        let lines = template.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine -> String? in
            var rendered = String(rawLine)
            var killed = false

            for (k, v) in vars {
                let token = "{\(k)}"
                guard rendered.contains(token) else { continue }
                if v.isEmpty && conditionalKeys.contains(k) {
                    killed = true
                    break
                }
                rendered = rendered.replacingOccurrences(of: token, with: v)
            }

            return killed ? nil : rendered
        }

        return lines.joined(separator: "\n")
    }
}
