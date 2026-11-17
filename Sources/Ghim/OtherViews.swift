import SwiftUI

// MARK: - Today (smart tab)

struct TodayView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var prefs: Prefs
    @State private var showDone = true

    var body: some View {
        let open = store.todayOpen
        let done = store.todayDone
        let overdue = open.filter(\.isOverdue)
        let rest = open.filter { !$0.isOverdue }
        let sugg = store.suggestions

        List {
            SummaryCard().ghimRow().padding(.top, 8)

            AddTaskField(categoryID: store.defaultTaskCategoryID, forceToday: true,
                         placeholder: "Việc cho hôm nay…   #tab  !!  @15h")
                .padding(.vertical, 4)
                .ghimRow()

            if !overdue.isEmpty {
                SectionLabel(text: "Quá hạn", color: .red).ghimRow()
                ForEach(overdue) { TaskRow(task: $0, showCategory: true).ghimRow() }
                SectionLabel(text: "Hôm nay", color: .orange).ghimRow()
            }
            ForEach(rest) { TaskRow(task: $0, showCategory: true).ghimRow() }

            if open.isEmpty {
                Text(done.isEmpty ? "Chưa chọn việc nào cho hôm nay.\nBấm ☀︎ trên một việc, hoặc chọn từ gợi ý." : "Xong hết việc hôm nay 🎉 Nghỉ ngơi xứng đáng!")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .ghimRow()
            }

            if open.count < 3 && !sugg.isEmpty {
                SectionLabel(text: "Gợi ý thêm vào hôm nay", color: .secondary).ghimRow()
                ForEach(sugg) { SuggestionRow(task: $0).ghimRow() }
            }

            if !done.isEmpty {
                DoneHeader(count: done.count, expanded: $showDone).ghimRow()
                if showDone {
                    ForEach(done) { TaskRow(task: $0, showCategory: true).ghimRow() }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 10)
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

struct SummaryCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let p = store.todayProgress
        let frac = p.total > 0 ? Double(p.done) / Double(p.total) : 0
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: frac, color: frac >= 1 ? .green : .orange, lineWidth: 6)
                VStack(spacing: -2) {
                    Text("\(p.done)").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("/\(p.total)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(message(p.done, p.total)).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                HStack(spacing: 10) {
                    stat("flame.fill", "\(store.streak) ngày", .orange, "Chuỗi ngày liên tiếp có hoàn thành việc")
                    stat("scope", "\(store.focusToday)′", Color(hex: "#FF5A5F"), "Phút tập trung hôm nay")
                    stat("checkmark.circle.fill", "\(store.completedToday)", .green, "Việc đã xong hôm nay (mọi tab)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func stat(_ symbol: String, _ text: String, _ color: Color, _ help: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(color)
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
        }
        .help(help)
    }

    private func message(_ done: Int, _ total: Int) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greet = hour < 11 ? "Chào buổi sáng ☀️" : (hour < 14 ? "Buổi trưa vui vẻ 🍜" : (hour < 18 ? "Chiều năng suất nhé 💪" : "Buổi tối thư thả 🌙"))
        if total == 0 { return greet + "\nChọn 1–3 việc quan trọng nhất." }
        if done == total { return "Hoàn thành tất cả! 🎉" }
        if done == 0 { return greet + "\nBắt đầu từ việc nhỏ nhất nhé." }
        if Double(done) / Double(total) < 0.5 { return "Đang vào nhịp rồi 🚀" }
        return "Sắp xong rồi, cố lên! 🔥"
    }
}

struct SuggestionRow: View {
    let task: TaskItem
    @EnvironmentObject var store: Store
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { store.modify(task.id) { $0.isToday = true } }
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 15)).foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Thêm vào Hôm nay")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 4) {
                    if let c = store.category(task.categoryID) { CategoryPill(category: c) }
                    if task.priority != .none {
                        Text(task.priority.marks).font(.system(size: 10, weight: .heavy)).foregroundStyle(task.priority.color)
                    }
                    if task.due != nil { Chip(symbol: "calendar", text: Day.dueLabel(task), color: .blue) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(hover ? 0.15 : 0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .onHover { hover = $0 }
    }
}

// MARK: - Notes

struct NotesView: View {
    let category: Category
    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController
    @State private var dropTarget = false

    var body: some View {
        let notes = store.notes(in: category.id)
        VStack(spacing: 0) {
            Button {
                addNote()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil").font(.system(size: 13))
                    Text("Ghi chú mới").font(.system(size: 13))
                    Spacer()
                    Text("⌘N  ·  ⌘V dán ảnh").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if notes.isEmpty {
                EmptyState(symbol: "photo.on.rectangle.angled", title: "Chưa có ghi chú",
                           subtitle: "Ghi ý tưởng, số điện thoại, đoạn text hay dùng…\nDán (⌘V) hoặc kéo thả ảnh vào đây.")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(notes) { n in
                            NoteCard(note: n, color: Color(hex: category.colorHex))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .overlay {
            if dropTarget {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(hex: category.colorHex), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color(hex: category.colorHex).opacity(0.08))
                    .overlay(Label("Thả ảnh để tạo ghi chú mới", systemImage: "photo.badge.plus").font(.system(size: 13, weight: .semibold)))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: ImageDrop.types, isTargeted: $dropTarget) { providers in
            ImageDrop.load(providers) { payloads in
                withAnimation(.snappy) { _ = store.attachImages(payloads, to: nil, category: category.id) }
            }
            return true
        }
        .onChange(of: pc.focusRequest) { _, _ in addNote() }
    }

    private func addNote() {
        let id = withAnimation(.snappy) { store.addNote(in: category.id) }
        pc.focusNoteID = id
    }
}

struct NoteCard: View {
    let note: Note
    let color: Color
    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController
    @State private var hover = false
    @State private var flash: String?
    @State private var dropTarget = false

    private var active: Bool { pc.activeNoteID == note.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(color) }
                Text(flash ?? note.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(flash == nil ? Color.secondary.opacity(0.8) : Color.green)
                if !note.images.isEmpty {
                    Label("\(note.images.count)", systemImage: "photo").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if hover {
                    IconButton("photo.badge.plus", size: 10, help: "Thêm ảnh từ máy…") { pickImages() }
                    IconButton("checklist", size: 10, help: "Biến dòng đầu thành việc") {
                        if store.noteToTask(note.id) { show("✓ Đã thêm vào danh sách việc") }
                    }
                    IconButton("doc.on.doc", size: 10, help: "Sao chép chữ") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.text, forType: .string)
                        show("✓ Đã sao chép")
                    }
                    IconButton(note.pinned ? "pin.slash" : "pin", size: 10, help: note.pinned ? "Bỏ ghim" : "Ghim lên đầu") {
                        withAnimation(.snappy) { store.toggleNotePin(note.id) }
                    }
                    IconButton("trash", size: 10, help: "Xoá") { withAnimation(.snappy) { store.deleteNote(note.id) } }
                }
            }
            .frame(height: 20)
            ZStack(alignment: .topLeading) {
                NoteTextView(text: store.noteBinding(note.id),
                             noteID: note.id,
                             focusMe: pc.focusNoteID == note.id,
                             onImages: { payloads in
                                 withAnimation(.snappy) { _ = store.attachImages(payloads, to: note.id, category: note.categoryID) }
                             })
                if note.text.isEmpty {
                    Text(note.images.isEmpty ? "Viết gì đó… hoặc ⌘V dán ảnh" : "Thêm chú thích…")
                        .font(.system(size: 13)).foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            NoteImagesView(note: note)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(dropTarget ? 0.25 : 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(color.opacity(active || dropTarget ? 0.7 : 0.18), lineWidth: dropTarget ? 2 : 1))
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
        .onDrop(of: ImageDrop.types, isTargeted: $dropTarget) { providers in
            ImageDrop.load(providers) { payloads in
                withAnimation(.snappy) { _ = store.attachImages(payloads, to: note.id, category: note.categoryID) }
            }
            return true
        }
    }

    private func show(_ s: String) {
        flash = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { flash = nil }
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        pc.pinned = true // keep the panel open while the file dialog is up
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { resp in
            pc.pinned = false
            guard resp == .OK else { return }
            let payloads = panel.urls.compactMap(ImagePayload.init(fileURL:))
            withAnimation(.snappy) { _ = store.attachImages(payloads, to: note.id, category: note.categoryID) }
        }
    }
}

/// NSTextView that grows with its content and turns pasted / dropped images into attachments.
final class ImageAwareTextView: NSTextView {
    var onImages: (([ImagePayload]) -> Void)?

    override func paste(_ sender: Any?) {
        let p = ImagePasteboard.payloads()
        if !p.isEmpty, let onImages { onImages(p) } else { super.paste(sender) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImagePasteboard.hasImage(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImagePasteboard.hasImage(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let p = ImagePasteboard.payloads(from: sender.draggingPasteboard)
        if !p.isEmpty, let onImages { onImages(p); return true }
        return super.performDragOperation(sender)
    }
}

struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    let noteID: UUID
    var focusMe: Bool
    var onImages: ([ImagePayload]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ImageAwareTextView {
        let tv = ImageAwareTextView()
        tv.isRichText = false
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 13)
        tv.textColor = .labelColor
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 5
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = true
        tv.string = text
        tv.delegate = context.coordinator
        tv.onImages = onImages
        return tv
    }

    func updateNSView(_ tv: ImageAwareTextView, context: Context) {
        context.coordinator.parent = self
        tv.onImages = onImages
        if tv.string != text && !context.coordinator.editing { tv.string = text }
        if focusMe {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                if PanelController.shared.focusNoteID == noteID { PanelController.shared.focusNoteID = nil }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: ImageAwareTextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 300
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        tc.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let h = max(lm.usedRect(for: tc).height, tv.font?.boundingRectForFont.height ?? 17)
        return CGSize(width: w, height: ceil(h))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        var editing = false
        init(_ p: NoteTextView) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            editing = true
            parent.text = tv.string
            editing = false
        }
        func textDidBeginEditing(_ n: Notification) {
            MainActor.assumeIsolated { PanelController.shared.activeNoteID = parent.noteID }
        }
        func textDidEndEditing(_ n: Notification) {
            MainActor.assumeIsolated {
                if PanelController.shared.activeNoteID == parent.noteID { PanelController.shared.activeNoteID = nil }
            }
        }
    }
}

// MARK: - Search

struct SearchResultsView: View {
    let query: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController

    var body: some View {
        let q = QuickParser.fold(query)
        let tasks = store.data.tasks.filter { QuickParser.fold($0.title + " " + $0.note).contains(q) }
            .sorted { (!$0.done && $1.done) }
        let notes = store.data.notes.filter { QuickParser.fold($0.text).contains(q) }
        List {
            if tasks.isEmpty && notes.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Không tìm thấy", subtitle: "Thử từ khoá khác nhé").ghimRow()
            }
            if !tasks.isEmpty {
                SectionLabel(text: "Việc (\(tasks.count))").ghimRow()
                ForEach(tasks) { TaskRow(task: $0, showCategory: true).ghimRow() }
            }
            if !notes.isEmpty {
                SectionLabel(text: "Ghi chú (\(notes.count))").ghimRow()
                ForEach(notes) { n in
                    Button {
                        pc.searching = false
                        pc.searchText = ""
                        pc.selection = .category(n.categoryID)
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            if let c = store.category(n.categoryID) { CategoryPill(category: c) }
                            Text(n.text).font(.system(size: 12)).lineLimit(3).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .ghimRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
