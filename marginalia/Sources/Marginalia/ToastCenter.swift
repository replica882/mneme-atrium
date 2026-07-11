import SwiftUI
import JournalKit
import Observation

/// 全局 toast 中心（R3.3）：各 view 自挂 overlay 导致提示位置漂移（聊天里甚至挂在
/// 消息气泡上跟着消息跑）——统一走这里，位置永远是屏幕顶部居中。
/// sheet 内的提示例外（sheet 盖住 root overlay，保留在 sheet 顶部）。
@Observable
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    private(set) var message: String? = nil
    private var seq = 0

    func show(_ msg: String) {
        seq += 1
        let cur = seq
        message = msg
        Task {
            try? await Task.sleep(for: .seconds(2))
            if seq == cur { message = nil }
        }
    }
}

/// 挂在 ContentView 根部的展示层（胶囊样式与原各处 toast 一致）。
public struct GlobalToastOverlay: View {
    public init() {}

    public var body: some View {
        Group {
            if let msg = ToastCenter.shared.message {
                Text(msg)
                    .font(.system(size: JournalTheme.F.body, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(JournalTheme.mint)
                            .shadow(color: JournalTheme.shadowInk.opacity(0.15), radius: 8, y: 2)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ToastCenter.shared.message)
    }
}
