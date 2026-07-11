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
        ("word", "词面（如 apple）"),
        ("definition", "释义"),
        ("band", "频段（如 NGSL 1-500）"),
        ("categories", "词表，顿号分隔（如 General NGSL、Spoken NGSL）"),
        ("forms", "词形变化，逗号分隔。空时整行省"),
        ("status", "当前学习状态（已掌握 / 反应慢 / 不认识）。未标过整行省"),
        ("assistantName", "当前楼层 AI 的名字"),
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
