import SwiftUI
import SwiftData
import Marginalia

/// Marginalia · 页边集——开箱即用壳。
/// clone → 开 App/MarginaliaApp.xcodeproj → 选自己的开发者签名 → Run。
/// 五桥（问 AI / 来源跳转 / 考古 / AI 判分）在 standalone 里不接线，对应入口自动隐藏；
/// 想接自己的 LLM 见 README「VocabBridge」。
@main
struct MarginaliaApp: App {
    var body: some Scene {
        WindowGroup {
            MarginaliaPanel()
                .frame(minWidth: 420, minHeight: 640)
        }
        .modelContainer(for: VocabProgress.self)
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
