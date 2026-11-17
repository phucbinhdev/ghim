import SwiftUI

struct ContentPanel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var timer: FocusTimer
    @FocusState private var searchFocused: Bool

    private var currentCategory: Category? {
        if case .category(let id) = pc.selection { return store.category(id) }
        return nil
    }

    private var accent: Color {
        if let c = currentCategory { return Color(hex: c.colorHex) }
        return .orange
    }

    private var title: String { currentCategory?.name ?? "Hôm nay" }

    private var subtitle: String {
        if let c = currentCategory {
            if c.kind == .notes { return "\(store.notes(in: c.id).count) ghi chú" }
            let open = store.openCount(c.id), od = store.overdueCount(c.id)
            return od > 0 ? "\(open) việc · \(od) quá hạn" : (open == 0 ? "Không còn việc nào 🎉" : "\(open) việc chưa xong")
        }
        return Day.longFormatter.string(from: Date()).capitalizedFirst
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if pc.searching { searchField }
            if timer.active {
                FocusBar().padding(.horizontal, 10).padding(.bottom, 8)
            }
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            Group {
                if pc.searching && !pc.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResultsView(query: pc.searchText)
                } else if let c = currentCategory {
                    if c.kind == .tasks { TaskListView(category: c).id(c.id) } else { NotesView(category: c).id(c.id) }
                } else {
                    TodayView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            ZStack {
                VisualEffect(material: .popover)
                LinearGradient(colors: [accent.opacity(0.16), accent.opacity(0.04)], startPoint: .top, endPoint: .bottom)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .overlay(alignment: prefs.edgeRight ? .trailing : .leading) {
            // colour seam that visually connects the panel to the selected tab
            Rectangle().fill(accent).frame(width: 3).padding(.vertical, 14)
        }
        .padding(prefs.edgeRight ? .trailing : .leading, 2)
        .overlay { ResizeHandles() }
        .background(shortcuts)
    }

    private var header: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent.gradient)
                .frame(width: 6, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            IconButton("magnifyingglass", tint: pc.searching ? accent : .secondary, help: "Tìm kiếm (⌘F)") {
                pc.toggleSearch()
                if pc.searching { DispatchQueue.main.async { searchFocused = true } }
            }
            IconButton(prefs.largeMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       tint: prefs.largeMode ? accent : .secondary,
                       help: prefs.largeMode ? "Thu nhỏ về kích thước thường" : "Phóng to (rộng + cao hết màn hình)") {
                pc.toggleLarge()
            }
            IconButton(pc.pinned ? "pin.fill" : "pin", tint: pc.pinned ? accent : .secondary,
                       help: pc.pinned ? "Đang giữ mở – bấm để cho phép tự thu gọn" : "Giữ panel luôn mở") {
                pc.pinned.toggle()
            }
            Menu {
                Button("Ghi nhanh… (⌃⌥N)") { QuickCapture.shared.show() }
                Button("Sao chép tất cả dạng Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.exportMarkdown(), forType: .string)
                }
                if let c = currentCategory, c.kind == .tasks {
                    Button("Xoá việc đã xong trong \(c.name)") { withAnimation { store.clearDone(in: c.id) } }
                }
                Divider()
                Button(prefs.edgeRight ? "Chuyển sang cạnh trái" : "Chuyển sang cạnh phải") { prefs.edgeRight.toggle() }
                Button("Cài đặt…") { SettingsWindow.show() }
                Divider()
                Button("Thoát Ghim") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 3)
            IconButton(prefs.edgeRight ? "chevron.right" : "chevron.left", help: "Thu gọn (Esc)") { pc.collapse() }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("Tìm trong mọi tab…", text: $pc.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !pc.searchText.isEmpty {
                IconButton("xmark.circle.fill", size: 11) { pc.searchText = "" }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .onAppear { searchFocused = true }
    }

    /// Invisible buttons that provide keyboard shortcuts while the panel is key.
    private var shortcuts: some View {
        ZStack {
            Button("") { pc.selection = .today } .keyboardShortcut("0", modifiers: .command)
            ForEach(Array(store.data.categories.prefix(9).enumerated()), id: \.element.id) { i, c in
                Button("") { pc.selection = .category(c.id) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Button("") { pc.focusRequest += 1 }.keyboardShortcut("n", modifiers: .command)
            Button("") { pc.searching = true; DispatchQueue.main.async { searchFocused = true } }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { pc.collapse() }.keyboardShortcut("w", modifiers: .command)
            Button("") { SettingsWindow.show() }.keyboardShortcut(",", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Focus bar

struct FocusBar: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var store: Store

    var body: some View {
        let color: Color = timer.isBreak ? .green : Color(hex: "#FF5A5F")
        let task = timer.taskID.flatMap { id in store.data.tasks.first { $0.id == id } }
        HStack(spacing: 10) {
            ZStack {
                ProgressRing(progress: timer.progress, color: color, lineWidth: 3.5)
                Image(systemName: timer.isBreak ? "cup.and.saucer.fill" : "scope")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(timer.isBreak ? "Giải lao – đứng dậy vươn vai nhé" : (task?.title ?? "Tập trung"))
                    .font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(timer.remainingString)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timer.running ? Color.primary : Color.secondary)
            }
            Spacer(minLength: 0)
            IconButton(timer.running ? "pause.fill" : "play.fill", size: 12, help: timer.running ? "Tạm dừng" : "Tiếp tục") { timer.togglePause() }
            IconButton("goforward.5", size: 12, help: "+5 phút") { timer.addMinutes(5) }
            if let task, !timer.isBreak {
                IconButton("checkmark", size: 12, tint: .green, help: "Xong việc này") {
                    store.toggle(task.id)
                    Sound.play("Hero")
                    timer.stop()
                }
            }
            IconButton(timer.isBreak ? "forward.end.fill" : "stop.fill", size: 12, help: timer.isBreak ? "Bỏ qua giờ nghỉ" : "Dừng") { timer.stop() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(color.opacity(0.3), lineWidth: 0.5))
    }
}


// MARK: - Resize handles

/// Invisible grab areas on the outer side, the bottom edge and the outer-bottom corner.
/// Double-click any of them to toggle large mode.
struct ResizeHandles: View {
    @EnvironmentObject var pc: PanelController
    @EnvironmentObject var prefs: Prefs
    @State private var cornerHover = false

    var body: some View {
        let outer: Alignment = prefs.edgeRight ? .leading : .trailing
        let corner: Alignment = prefs.edgeRight ? .bottomLeading : .bottomTrailing
        ZStack {
            // side edge → width
            handle(.side, cursor: .resizeLeftRight)
                .frame(width: 7)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: outer)
            // bottom edge → height
            handle(.bottom, cursor: .resizeUpDown)
                .frame(height: 7)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // corner → both, with a small visible grip
            ZStack {
                handle(.corner, cursor: .crosshair)
                CornerGrip(mirrored: prefs.edgeRight)
                    .stroke(Color.primary.opacity(cornerHover || pc.resizing ? 0.55 : 0.22),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 10, height: 10)
                    .padding(5)
                    .allowsHitTesting(false)
            }
            .frame(width: 20, height: 20)
            .onHover { cornerHover = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
        }
    }

    private func handle(_ edge: PanelController.ResizeEdge, cursor: NSCursor) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { cursor.push() } else if !pc.resizing { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in pc.resizeChanged(edge) }
                    .onEnded { _ in pc.resizeEnded(); NSCursor.pop() }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { pc.toggleLarge() })
            .help("Kéo để đổi kích thước · nhấp đúp để phóng to/thu nhỏ")
    }
}

/// Three diagonal lines, like a classic window resize grip.
struct CornerGrip: Shape {
    var mirrored: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let o = CGFloat(i) * r.width / 3
            if mirrored {
                p.move(to: CGPoint(x: r.minX, y: r.minY + o))
                p.addLine(to: CGPoint(x: r.maxX - o, y: r.maxY))
            } else {
                p.move(to: CGPoint(x: r.maxX, y: r.minY + o))
                p.addLine(to: CGPoint(x: r.minX + o, y: r.maxY))
            }
        }
        return p
    }
}
