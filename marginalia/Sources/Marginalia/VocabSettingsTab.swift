import SwiftUI
import JournalKit

/// 单词功能的设置面板。
///
/// 双入口（D8=C）：
/// - vocab panel 顶部齿轮按钮 → sheet
/// - 全局设置 → 单词 tab → NavigationStack push
///
/// 目前只有一项：「问 {{char}}」按钮的 prompt 模板。
struct VocabSettingsTab: View {
    @Environment(\.vocabBridge) private var bridge
    @AppStorage("vocabAskPromptTemplate") private var template: String = VocabPromptDefaults.template
    @AppStorage("vocabShuffleByDefault") private var shuffleByDefault: Bool = false
    @AppStorage("vocabReviewDailyQuota") private var reviewDailyQuota: Int = 10

    /// build 戳（可执行文件 mtime）——"到底装没装上"一眼可见，不再猜进程新旧。
    private var buildStamp: String {
        guard let url = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return "?" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return "build \(f.string(from: date))"
    }
    @AppStorage("vocabReviewDailyCap") private var reviewDailyCap: Int = 50
    @AppStorage("vocabReviewAutoFromReading") private var reviewAutoFromReading: Bool = true
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            orderSection
            reviewSection
            if bridge.askAI != nil {
                placeholderSection
                templateSection
                previewSection
                resetSection
            }

            Section {
            } footer: {
                Text(buildStamp)
                    .font(.system(size: 11))
                    .foregroundColor(JournalTheme.faint.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(hex: 0xFAFAF8).ignoresSafeArea())
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 出词顺序

    private var orderSection: some View {
        Section {
            Toggle("Shuffle by default", isOn: $shuffleByDefault)
                .toggleStyle(SwitchToggleStyle(tint: JournalTheme.mint))
                .listRowBackground(JournalTheme.cream)
        } header: {
            Text("Word order")
                .foregroundColor(JournalTheme.faint)
        } footer: {
            Text("Off: words come in recommended order (high-frequency first).\nOn: shuffled every time you refilter or revisit settings.")
                .font(.system(size: JournalTheme.F.caption))
                .foregroundColor(JournalTheme.faint)
        }
    }

    // MARK: - 复习

    private var reviewSection: some View {
        Section {
            Stepper(value: $reviewDailyQuota, in: 0...50) {
                HStack {
                    Text("Daily new cards")
                    Spacer()
                    Text("\(reviewDailyQuota)")
                        .foregroundColor(JournalTheme.pencil)
                        .monospacedDigit()
                }
            }
            .listRowBackground(JournalTheme.cream)

            Stepper(value: $reviewDailyCap, in: 0...300, step: 10) {
                HStack {
                    Text("Daily review cap")
                    Spacer()
                    Text(reviewDailyCap == 0 ? "no limit" : "\(reviewDailyCap)")
                        .foregroundColor(JournalTheme.pencil)
                        .monospacedDigit()
                }
            }
            .listRowBackground(JournalTheme.cream)

            Toggle("Auto-add highlighted words to review", isOn: $reviewAutoFromReading)
                .toggleStyle(SwitchToggleStyle(tint: JournalTheme.mint))
                .listRowBackground(JournalTheme.cream)
        } header: {
            Text("Review")
                .foregroundColor(JournalTheme.faint)
        } footer: {
            Text("Daily new cards: how many new cards get pulled in each day from the selected wordbook, in order. 0 = don't auto-supply.\nDaily review cap: max cards reviewed today (new + due combined); once hit, you'll see the done screen. Overflow due cards just wait until tomorrow. 0 = no cap.\nAuto-add: words you collect while reading or chatting go straight into the review deck.\n\nExercises climb with familiarity: new cards start as read-and-reveal, then spelling (fill the blank from the definition or source sentence) once you've gotten it right twice, then sentence-writing once the interval passes 7 days. A miss drops it back to read-and-reveal. Long-press a card to remove it from the deck.")
                .font(.system(size: JournalTheme.F.caption))
                .foregroundColor(JournalTheme.faint)
        }
    }

    // MARK: - 占位符说明

    private var placeholderSection: some View {
        Section {
            ForEach(VocabPromptDefaults.placeholderDocs, id: \.key) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Text("{\(entry.key)}")
                        .font(.system(size: JournalTheme.F.body, design: .monospaced))
                        .foregroundColor(JournalTheme.mint)
                        .frame(width: 110, alignment: .leading)
                    Text(entry.desc)
                        .font(.system(size: JournalTheme.F.secondary))
                        .foregroundColor(JournalTheme.pencil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(JournalTheme.cream)
            }
        } header: {
            Text("Available placeholders")
                .foregroundColor(JournalTheme.faint)
        } footer: {
            Text("`{forms}` or `{status}` hide their whole line automatically when empty — no dangling colons.")
                .font(.system(size: JournalTheme.F.caption))
                .foregroundColor(JournalTheme.faint)
        }
    }

    // MARK: - 模板编辑

    private var templateSection: some View {
        Section {
            TextEditor(text: $template)
                .font(.system(size: JournalTheme.F.body, design: .monospaced))
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .listRowBackground(JournalTheme.cream)
        } header: {
            Text("Template")
                .foregroundColor(JournalTheme.faint)
        } footer: {
            Text("Rendered into the prompt sent to your AI when you tap “ask {{char}}”.")
                .font(.system(size: JournalTheme.F.caption))
                .foregroundColor(JournalTheme.faint)
        }
    }

    // MARK: - 预览（拿假数据渲染一下让用户看效果）

    private var previewSection: some View {
        Section {
            Text(previewText)
                .font(.system(size: JournalTheme.F.secondary))
                .foregroundColor(JournalTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(JournalTheme.cream)
        } header: {
            Text("Preview (with word forms + marked as slow)")
                .foregroundColor(JournalTheme.faint)
        }
    }

    private var previewText: String {
        VocabPromptDefaults.render(template: template, vars: [
            "word": "ephemeral",
            "definition": "brief; fleeting",
            "band": "Specialized / overlap",
            "categories": "Academic NAWL",
            "forms": "ephemerals, ephemerally",
            "status": "slow",
            "assistantName": "the assistant",
        ])
    }

    // MARK: - 恢复默认

    private var resetSection: some View {
        Section {
            Button {
                showResetConfirm = true
            } label: {
                Text("Reset to default")
                    .foregroundColor(JournalTheme.clay)
            }
            .listRowBackground(JournalTheme.cream)
        }
        .confirmationDialog("Reset the template to default?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                template = VocabPromptDefaults.template
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite your current edits.")
        }
    }
}
