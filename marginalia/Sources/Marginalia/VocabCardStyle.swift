import SwiftUI
import JournalKit

/// B-2 单词系统统一卡片规格（plan-vocab-ui-b）：白 0.5 填充 + accent 0.5 描边 + continuous 圆角。
/// 两级：大卡 18（学习/复习题卡）、内容块 12（词典/出处/笔记块）。
/// 只统一背景语言，不动各自 padding/布局（气质留给拟物手账立项）。
struct VocabCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(JournalTheme.wash.opacity(0.5), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func vocabCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(VocabCardModifier(cornerRadius: cornerRadius))
    }
}
