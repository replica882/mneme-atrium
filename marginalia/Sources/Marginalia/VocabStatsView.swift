import SwiftUI
import JournalKit
import SwiftData

/// 统计 tab。
///
/// - 顶部 4 个统计卡：总数 / 认识 / 反应慢 / 不认识
/// - 中间大进度环
/// - 缺口聚合表：按 categories ∪ band 聚合，按 (slow + unknown) 降序
/// - 底部「清空进度」按钮（带二次确认）
struct VocabStatsView: View {
    /// B-1：导出从 tab 收进统计页（sheet）。
    @State private var showExport = false

    @Bindable var store: VocabSessionStore
    @Environment(\.modelContext) private var modelContext

    @State private var groups: [GapGroup] = []
    @State private var counts: StatsCounts = StatsCounts()
    @State private var showWipeConfirm = false

    var body: some View {
        // A-5 拟物手账：统计页 = 活页纸页
        // 蕾丝底由 VocabPanelView 容器统一铺（页面内再铺会在 UIKit HC 里
        // ignoresSafeArea 物理溢出盖住书签行——R7c 缺角真凶）
        ZStack {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(JournalTheme.paper)
                    PaperNoise()
                    RoseMarginLines(x: 34)
                    PunchHoles()

                    ScrollView {
                        VStack(spacing: 18) {
                            statsRow
                            progressRing
                            gapTable
                            exportButton
                            wipeButton
                            Color.clear.frame(height: 8)
                        }
                        .padding(.top, 22)
                        .padding(.leading, 52)
                        .padding(.trailing, 20)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: JournalTheme.shadowInk.opacity(0.13), radius: 8, y: 3)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showExport) {
            NavigationStack { VocabExportView(store: store) }
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 520)
                #endif
        }
        .task(id: store.idx) {
            // 切词或回 stats tab 都会触发；idx 变化 = mark 了，进度数据可能变
            await recompute()
        }
        .task(id: store.tab) {
            await recompute()
        }
    }

    // MARK: - 数据重算

    private func recompute() async {
        let snapshot = store.readProgressSnapshot(context: modelContext)
        let statusMap = snapshot.mapValues(\.status)
        let g = await VocabLibrary.shared.gapStats(filtered: store.filtered, progress: statusMap)
        groups = g

        // 4 档计数
        var c = StatsCounts()
        c.total = store.filtered.count
        for w in store.filtered {
            switch statusMap[w.word] {
            case .known:   c.known += 1
            case .slow:    c.slow += 1
            case .unknown: c.unknown += 1
            case .none:    break
            }
        }
        counts = c
    }

    // MARK: - 顶部 4 档统计

    private var statsRow: some View {
        HStack(spacing: 22) {
            statInk(value: counts.total, label: "all", color: JournalTheme.ink)
            statInk(value: counts.known, label: "know", color: JournalTheme.mint)
            statInk(value: counts.slow, label: "slow", color: JournalTheme.amber)
            statInk(value: counts.unknown, label: "unknown", color: JournalTheme.clay)
        }
        .frame(maxWidth: .infinity)
    }

    private func statInk(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(JournalTheme.serif(21, .bold))
                .foregroundColor(color)
                .monospacedDigit()
            Text(label)
                .font(JournalTheme.serifItalic(10.5))
                .tracking(0.8)
                .foregroundColor(JournalTheme.faint)
        }
    }

    // MARK: - 进度环

    private var progressRing: some View {
        let seen = counts.known + counts.slow + counts.unknown
        let total = max(counts.total, 1)
        let ratio = Double(seen) / Double(total)

        return ZStack {
            Circle()
                .stroke(JournalTheme.mint.opacity(0.18), lineWidth: 9)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(JournalTheme.mint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: ratio)
            VStack(spacing: 1) {
                Text(String(format: "%.0f%%", ratio * 100))
                    .font(JournalTheme.serif(26, .bold))
                    .foregroundColor(JournalTheme.ink)
                Text("\(seen) of \(total)")
                    .font(JournalTheme.serifItalic(11))
                    .foregroundColor(JournalTheme.faint)
            }
        }
        .frame(width: 126, height: 126)
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            StarSticker(color: JournalTheme.amber, size: 20, rotation: 12)
                .offset(x: 6, y: 2)
        }
    }

    // MARK: - 缺口聚合表

    private var gapTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("gaps")
                .font(JournalTheme.serifItalic(12))
                .tracking(1.2)
                .foregroundColor(JournalTheme.pencil)
                .padding(.bottom, 2)

            // 表头（英文微标签，划一条铅笔线）
            HStack(spacing: 8) {
                Text("group").frame(maxWidth: .infinity, alignment: .leading)
                col("all", w: 40)
                col("seen", w: 40)
                col("slow", w: 40)
                col("✗", w: 36)
            }
            .font(JournalTheme.serifItalic(11))
            .foregroundColor(JournalTheme.faint)
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(JournalTheme.faint.opacity(0.35))
                    .frame(height: 0.8)
            }

            VStack(spacing: 0) {
                ForEach(groups) { g in
                    gapRow(g)
                }
                if groups.isEmpty {
                    Text("nothing under this filter")
                        .font(JournalTheme.serifItalic(12))
                        .foregroundColor(JournalTheme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private func col(_ text: String, w: CGFloat) -> some View {
        Text(text).frame(width: w, alignment: .trailing).monospacedDigit()
    }

    private func gapRow(_ g: GapGroup) -> some View {
        HStack(spacing: 8) {
            Text(g.name)
                .font(JournalTheme.serif(12.5))
                .foregroundColor(JournalTheme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            statCol(g.total, w: 40, color: JournalTheme.faint)
            statCol(g.seen, w: 40, color: JournalTheme.pencil)
            statCol(g.slow, w: 40, color: g.slow > 0 ? JournalTheme.amber : JournalTheme.faint.opacity(0.6))
            statCol(g.unknown, w: 36, color: g.unknown > 0 ? JournalTheme.clay : JournalTheme.faint.opacity(0.6))
        }
        .font(JournalTheme.mono(11.5))
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JournalTheme.mint.opacity(0.22))
                .frame(height: 1)
        }
    }

    private func statCol(_ value: Int, w: CGFloat, color: Color) -> some View {
        Text("\(value)")
            .foregroundColor(color)
            .monospacedDigit()
            .frame(width: w, alignment: .trailing)
    }

    // MARK: - 清空进度

    /// B-1：导出从 tab 收编成统计页动作。
    private var exportButton: some View {
        Button {
            showExport = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                Text("导出学习数据")
                    .font(JournalTheme.serifItalic(13))
            }
            .foregroundColor(JournalTheme.pencil)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var wipeButton: some View {
        Button {
            showWipeConfirm = true
        } label: {
            Text("清空所有进度")
                .font(JournalTheme.serifItalic(12.5))
                .foregroundColor(JournalTheme.clay)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .confirmationDialog("清空所有学习进度？", isPresented: $showWipeConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                Task {
                    await store.wipeAllProgress(context: modelContext)
                    await recompute()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有「认识 / 反应慢 / 不认识」标记会被清除，note 也一起没。")
        }
    }
}

// MARK: - 内部小数据

private struct StatsCounts {
    var total: Int = 0
    var known: Int = 0
    var slow: Int = 0
    var unknown: Int = 0
}
