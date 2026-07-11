import SwiftUI
import SwiftData
import JournalKit

/// Marginalia 页边集——单词手账（记忆花园的开源小甜品）。
///
/// 最小接入：
/// ```swift
/// MarginaliaPanel()
///     .modelContainer(for: VocabProgress.self)   // 学习进度（SwiftData）
/// ```
/// 可选桥（问 AI / 来源跳转 / 考古 / AI 判分——不接则对应入口隐藏，模块自身闭环完整）：
/// ```swift
/// MarginaliaPanel(bridge: myBridge)
/// ```
public struct MarginaliaPanel: View {
    private let bridge: VocabBridge

    public init(bridge: VocabBridge = VocabBridge()) {
        self.bridge = bridge
    }

    public var body: some View {
        ZStack {
            PixelLaceBackdrop().ignoresSafeArea()   // 铺满上下安全区（standalone 顶层是安全的，
                                                    // 主库 HC 溢出坑只在嵌套 UIKit 容器里）
            VocabPanelView()
            GlobalToastOverlay()
        }
        .environment(\.vocabBridge, bridge)
    }
}
