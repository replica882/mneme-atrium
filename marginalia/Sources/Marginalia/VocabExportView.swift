import SwiftUI
import JournalKit
import SwiftData
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 导出 tab。
///
/// 复刻原 NGSL：导出**缺口词**（status ∈ {slow, unknown}）成两种格式：
/// - CSV: `vocab_gap_export.csv`（逗号分隔 + RFC 4180 转义）
/// - Anki TSV: `anki_gap_import.tsv`（Tab 分隔，给 Anki 导入用）
///
/// iOS 走 UIActivityViewController（Share Sheet）。
/// macOS 走 NSSavePanel（用户选保存位置）。
struct VocabExportView: View {
    @Bindable var store: VocabSessionStore
    @Environment(\.modelContext) private var modelContext

    @State private var gapCount: Int = 0

    #if os(iOS)
    @State private var shareItem: VocabShareItem? = nil
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoCard
                exportButton(
                    title: "导出缺口 CSV",
                    detail: "Excel / 文本编辑器可读，逗号分隔",
                    icon: "tablecells",
                    isAnki: false
                )
                exportButton(
                    title: "导出 Anki TSV",
                    detail: "Anki Desktop / AnkiMobile 直接导入，Tab 分隔",
                    icon: "rectangle.stack.badge.plus",
                    isAnki: true
                )
                Spacer()
            }
            .padding(16)
        }
        .task(id: store.idx) {
            await refreshCount()
        }
        .task {
            await refreshCount()
        }
        #if os(iOS)
        .sheet(item: $shareItem) { item in
            VocabShareSheet(items: [item.url])
        }
        #endif
    }

    private func refreshCount() async {
        let snap = store.readProgressSnapshot(context: modelContext)
        gapCount = snap.values.filter { $0.status == .slow || $0.status == .unknown }.count
    }

    // MARK: - 信息卡

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(JournalTheme.mint)
                Text("\(gapCount) 个缺口词将导出")
                    .font(.system(size: JournalTheme.F.body, weight: .semibold))
                    .foregroundColor(JournalTheme.ink)
            }
            Text("字段：word / definition / categories / forms / status / seconds / note")
                .font(.system(size: JournalTheme.F.caption))
                .foregroundColor(JournalTheme.faint)
            Text("仅包含「反应慢 / 不认识」的词，「认识」的不进导出。")
                .font(.system(size: JournalTheme.F.caption))
                .foregroundColor(JournalTheme.faint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(JournalTheme.wash.opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: - 导出按钮

    private func exportButton(title: String, detail: String, icon: String, isAnki: Bool) -> some View {
        Button {
            Task { await doExport(isAnki: isAnki) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(JournalTheme.mint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: JournalTheme.F.body, weight: .semibold))
                        .foregroundColor(JournalTheme.ink)
                    Text(detail)
                        .font(.system(size: JournalTheme.F.caption))
                        .foregroundColor(JournalTheme.faint)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(JournalTheme.faint)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(JournalTheme.wash.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(gapCount == 0)
        .opacity(gapCount == 0 ? 0.5 : 1)
    }

    // MARK: - 导出实现

    private func doExport(isAnki: Bool) async {
        let snapshot = store.readProgressSnapshot(context: modelContext)
        let rows = await VocabLibrary.shared.gapRows(progress: snapshot)
        let body = isAnki ? TSVBuilder.build(rows: rows) : CSVBuilder.build(rows: rows)
        let filename = isAnki ? "anki_gap_import.tsv" : "vocab_gap_export.csv"

        await MainActor.run {
            saveOrShare(body: body, filename: filename)
        }
    }

    @MainActor
    private func saveOrShare(body: String, filename: String) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try body.data(using: .utf8)?.write(to: tmp)
        } catch {
            print("[Vocab] export write failed: \(error)")
            return
        }

        #if os(iOS)
        shareItem = VocabShareItem(url: tmp)
        #else
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dst = panel.url {
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: tmp, to: dst)
        }
        #endif
    }
}

// MARK: - iOS Share Sheet wrapper

#if os(iOS)
/// `Vocab` 前缀避免跟 ConfigPage/FeedbackSheet 已有的同名 struct 冲突。
private struct VocabShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct VocabShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - CSV / TSV builders

/// 最小 RFC 4180 CSV 转义：含 `"` / `,` / 换行 的字段加引号 + 双 `"` 转义。
enum CSVBuilder {
    static func build(rows: [[String]]) -> String {
        rows.map { row in
            row.map(escapeField).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }

    private static func escapeField(_ s: String) -> String {
        if s.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" || $0 == "\r" }) {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}

/// Anki TSV：Tab 分隔，字段内 tab/换行替换成空格（Anki 不支持转义）。
enum TSVBuilder {
    static func build(rows: [[String]]) -> String {
        rows.map { row in
            row.map { $0.replacingOccurrences(of: "\t", with: " ")
                       .replacingOccurrences(of: "\n", with: " ")
                       .replacingOccurrences(of: "\r", with: " ") }
                .joined(separator: "\t")
        }.joined(separator: "\n") + "\n"
    }
}
