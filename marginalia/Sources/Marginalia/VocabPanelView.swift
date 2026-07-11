import SwiftUI
import JournalKit
import SwiftData

/// page2 tool「单词」主容器。
///
/// 4 个 tab 切换：学习 / 筛选 / 统计 / 导出（决策 D3=A）。
/// 视觉学 BrowserView 同款卡片观感：22pt 圆角 + 上下 10pt 留白。
/// tab bar 学自家配色，不用系统 TabView（系统款在 page2 嵌套样式奇怪）。
struct VocabPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store = VocabSessionStore()
    @State private var reviewStore = VocabReviewStore()
    @State private var showSettings = false

    // 监听设置开关：toggle 改了立即 reapply，否则 filtered 还是上次缓存的 priority 顺序
    @AppStorage("vocabShuffleByDefault") private var shuffleByDefault: Bool = false

    var body: some View {
        Group {
            if let err = store.loadError {
                errorState(err)
            } else if !store.libraryLoaded {
                loadingState
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PixelLaceBackdrop())
        // 学 BrowserView 的卡片观感：22pt continuous 圆角 + 上下留白看圆角
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 10)
        .padding(.bottom, 10)
        .task {
            await store.bootstrap(context: modelContext)
            // bootstrap 完后消费 pending jump（widget tap 时本 view 还没渲染，
            // 通知丢了——用 UserDefaults 中转兜底）
            consumePendingJump()
        }
        .onChange(of: shuffleByDefault) { _, _ in
            Task { await store.applyFilters(context: modelContext) }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { VocabSettingsTab() }
        }
    }

    private func consumePendingJump() {
        guard let pending = UserDefaults.standard.string(forKey: "pendingVocabJumpWord"),
              !pending.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "pendingVocabJumpWord")
        Task { await store.jumpToWord(pending) }
    }

    // MARK: - 主内容（4 tab 切换）

    @ViewBuilder
    private var content: some View {
        // 真本子 z 序：书签贴在纸**后面**探出头（R7b——tab 浮纸前时纸页顶部
        // 圆角弧裸露成"缺角"，且页面自带蕾丝底会盖掉任何纸前补丁）
        ZStack(alignment: .top) {
            tabBar
            tabBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 44)
        }
    }

    /// A-4 本子侧标签（mockup v3）：英文衬线微标签，选中白纸凸起，未选沉入桌面色。
    private var tabBar: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(VocabTab.allCases) { t in
                let active = store.tab == t.rawValue
                Button {
                    store.tab = t.rawValue   // 页面切换不进动画事务（整树重建会闪）
                } label: {
                    Text(t.title)
                        .font(JournalTheme.serif(12.5, .semibold))
                        .tracking(1.2)
                        .foregroundColor(active ? (t == .review ? JournalTheme.rose : JournalTheme.mint) : JournalTheme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 30)   // 长身体，下半截藏进纸页后面
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: 11, topTrailingRadius: 11)
                                .fill(active ? JournalTheme.paper : JournalTheme.tabIdle)
                                .shadow(color: JournalTheme.shadowInk.opacity(active ? 0.08 : 0.04),
                                        radius: active ? 4 : 2, y: -1)
                        )
                        .offset(y: active ? 0 : 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: active)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(showSettings ? JournalTheme.mint : JournalTheme.faint)
                    .frame(width: 34)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 11, topTrailingRadius: 11)
                            .fill(showSettings ? JournalTheme.paper : JournalTheme.tabIdle)
                            .shadow(color: JournalTheme.shadowInk.opacity(showSettings ? 0.08 : 0.04),
                                    radius: showSettings ? 4 : 2, y: -1)
                    )
                    .offset(y: showSettings ? 0 : 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSettings)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var tabBody: some View {
        switch VocabTab(rawValue: store.tab) ?? .study {
        case .study:    VocabStudyView(store: store)
        case .review:   VocabReviewView(store: reviewStore, sessionStore: store)
        case .notebook: VocabNotebookView(store: store)
        case .stats:    VocabStatsView(store: store)
        }
    }

    // MARK: - 边界态

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("加载词库…")
                .font(.system(size: JournalTheme.F.body))
                .foregroundColor(JournalTheme.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(JournalTheme.clay)
            Text("词库加载失败")
                .font(.system(size: JournalTheme.F.body, weight: .semibold))
                .foregroundColor(JournalTheme.ink)
            Text(message)
                .font(.system(size: JournalTheme.F.caption))
                .foregroundColor(JournalTheme.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab enum

enum VocabTab: Int, CaseIterable, Identifiable {
    // B-1 tab 减负：筛选→刷词页按钮 / 导出→统计页（plan-vocab-ui-b）
    case study = 0
    case review
    case notebook
    case stats

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .study:    return "words"
        case .review:   return "review"
        case .notebook: return "notebook"
        case .stats:    return "stats"
        }
    }

    var icon: String {
        switch self {
        case .study:    return "rectangle.portrait.and.arrow.right"
        case .review:   return "repeat"
        case .notebook: return "bookmark"
        case .stats:    return "chart.bar.xaxis"
        }
    }
}
