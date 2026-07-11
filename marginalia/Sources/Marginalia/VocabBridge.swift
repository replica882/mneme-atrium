import SwiftUI

/// 宿主 app 的可选能力注入——Marginalia 自身闭环完整（刷词/复习/生词本/统计/tag/词典/发音），
/// 这些桥不接就隐藏对应入口。完整体验（AI 考古实时回投、问 AI、跳回聊天原文）在记忆花园里。
public struct VocabBridge: Sendable {
    /// 「问 AI」：收到 (词, 渲染后的 prompt)，返回是否已发送。nil = 按钮隐藏。
    public var askAI: (@MainActor (String, String) -> Bool)?
    /// 聊天来源跳转：(消息 id, 思考链闪词)。nil = 出处不可点。
    public var openChatSource: (@MainActor (String, String?) -> Void)?
    /// 书籍来源跳转：(书名, 章节, 锚点偏移)。nil = 出处不可点。
    public var openBookSource: (@MainActor (String, Int, Int?) -> Void)?
    /// 一键考古（把词交给宿主的生成管线），返回是否受理。nil = 按钮隐藏，仅显示预生成语料。
    public var requestArcheology: (@MainActor (String) -> Bool)?
    /// 造句 AI 判分：(systemPrompt, userPrompt) → 模型原文；nil = 复习降自评。
    public var gradeSentence: (@MainActor (String, String) async -> String?)?

    public init() {}
}

private struct VocabBridgeKey: EnvironmentKey {
    static let defaultValue = VocabBridge()
}

public extension EnvironmentValues {
    var vocabBridge: VocabBridge {
        get { self[VocabBridgeKey.self] }
        set { self[VocabBridgeKey.self] = newValue }
    }
}
