import SwiftUI
import JournalKit
import MarkdownUI
#if os(iOS)
import PhotosUI
#endif

/// 词条笔记共享组件：文件库 `vocab/<word>.md` 渲染 + [[双链]] 跳词 + 照片附件。
/// 挂两处：复习卡（答题后）+ 词详情 sheet。文件库面板/AI fs 工具读写同一篇。
struct VocabNoteSection: View {
    let word: String
    /// 旧 VocabProgress.note 的迁移 seed（R2-2 笔记合并）：md 不存在时首次展示自动建档带入。
    var legacySeed: String? = nil
    /// 便签纸色（默认暖白；白纸页上传近白避免撞色）。
    var tone: Color = Color(hex: 0xFFFEF6)


    @State private var noteText: String? = nil
    @State private var images: [(path: String, data: Data)] = []
    @State private var showEditor = false
    @State private var editorDraft = ""
    /// [[双链]] 点出来的词，弹它的词详情。
    @State private var linkedWord: String? = nil
    #if os(iOS)
    @State private var pickerItem: PhotosPickerItem? = nil
    #else
    @State private var showImporter = false
    #endif

    private var profileId: String? { "default" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let note = noteText, !strippedEmpty(note) {
                noteMarkdown(VocabNoteStore.linkifiedMarkdown(note))
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "vocabnote" else { return .systemAction }
                        let target = String(url.path.dropFirst())
                        if !target.isEmpty { linkedWord = target }
                        return .handled
                    })
            } else {
                Text("No notes yet. Write something, add a photo, link related words with [[word]]…")
                    .font(JournalTheme.serifItalic(12.5))
                    .foregroundColor(JournalTheme.faint)
            }

            if !images.isEmpty {
                imageStrip
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stickyNote(rotation: -0.4, tone: tone)
        .task(id: word) { reload() }
        .sheet(isPresented: $showEditor) { editorSheet }
        .sheet(isPresented: Binding(
            get: { linkedWord != nil },
            set: { if !$0 { linkedWord = nil } }
        )) {
            if let w = linkedWord {
                VocabWordDetailSheet(word: w)
            }
        }
        #if os(macOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get(),
                  url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            addImage(data: data, ext: url.pathExtension.lowercased())
        }
        #endif
        #if os(iOS)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    addImage(data: data, ext: sniffExt(data))
                }
                pickerItem = nil
            }
        }
        #endif
    }

    /// md 渲染统一走 page1（聊天）那套，scale 1.0（粟粟定的）；[[双链]] 两边都走 openURL 环境。
    /// 划线锚 = 合成 id "vocabnote:<词>"。
    @ViewBuilder
    private func noteMarkdown(_ md: String) -> some View {
        Markdown(md).markdownTheme(.marginalia)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Text("notes")
                .font(JournalTheme.serifItalic(12))
                .tracking(1.2)
                .foregroundColor(JournalTheme.pencil)

            Spacer()

            #if os(iOS)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 13))
                    .foregroundColor(JournalTheme.faint)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #else
            Button { showImporter = true } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 13))
                    .foregroundColor(JournalTheme.faint)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #endif

            Button {
                openEditor()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundColor(JournalTheme.faint)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 照片条

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images, id: \.path) { img in
                    thumbnail(img.data)
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ data: Data) -> some View {
        #if os(macOS)
        if let ns = NSImage(data: data) {
            Image(nsImage: ns)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        #else
        if let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        #endif
    }

    // MARK: - 编辑

    private var editorSheet: some View {
        NavigationStack {
            TextEditor(text: $editorDraft)
                .font(.system(size: JournalTheme.F.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(JournalTheme.cream)
                .navigationTitle(word)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEditor = false }
                            .foregroundColor(JournalTheme.pencil)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let pid = profileId {
                                try? VocabNoteStore.writeNote(word: word, content: editorDraft, profileId: pid)
                            }
                            showEditor = false
                            reload()
                        }
                        .foregroundColor(JournalTheme.mint)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #endif
    }

    private func openEditor() {
        guard let pid = profileId else { return }
        VocabNoteStore.ensureNote(word: word, profileId: pid, seed: legacySeed)
        editorDraft = VocabNoteStore.readNote(word: word, profileId: pid) ?? "# \(word)\n\n"
        showEditor = true
    }

    // MARK: - 数据

    private func reload() {
        guard let pid = profileId else { return }
        noteText = VocabNoteStore.readNote(word: word, profileId: pid)
        // 旧笔记 lazy 迁移：md 还没建且有老 note → 建档带入（幂等，seed 只生效一次）
        if noteText == nil, let seed = legacySeed, !seed.isEmpty {
            VocabNoteStore.ensureNote(word: word, profileId: pid, seed: seed)
            noteText = VocabNoteStore.readNote(word: word, profileId: pid)
        }
        images = VocabNoteStore.imagePaths(word: word, profileId: pid).compactMap { path in
            VocabNoteStore.imageData(path: path, profileId: pid).map { (path, $0) }
        }
    }

    private func addImage(data: Data, ext: String) {
        guard let pid = profileId, !data.isEmpty else { return }
        try? VocabNoteStore.addImage(word: word, data: data, ext: ext, profileId: pid)
        reload()
    }

    #if os(iOS)
    /// PhotosPicker 只给裸 Data，按 magic bytes 猜扩展名（writeData 白名单要求有 ext）。
    private func sniffExt(_ data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpg"
    }
    #endif

    /// 只有骨架标题算"没写过"。
    private func strippedEmpty(_ note: String) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines) == "# \(word)"
            || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}
