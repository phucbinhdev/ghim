import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Quick capture (⌃⌥N from anywhere)

@MainActor
final class QuickCapture {
    static let shared = QuickCapture()
    private(set) var panel: EdgePanel?

    /// ⌘V an image into quick capture → new note in the first notes tab.
    func pasteImages() -> Bool {
        let payloads = ImagePasteboard.payloads()
        guard !payloads.isEmpty, let cat = Store.shared.data.categories.first(where: { $0.kind == .notes }) else { return false }
        Store.shared.attachImages(payloads, to: nil, category: cat.id)
        Sound.play("Pop")
        NotificationCenter.default.post(name: .quickCaptureImageAdded, object: cat.name)
        return true
    }

    func show() {
        if panel == nil {
            let p = EdgePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 120),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .modalPanel
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.onCancel = { [weak self] in self?.close() }
            let host = NSHostingView(rootView: QuickCaptureView(onDone: { [weak self] in self?.close() })
                .environmentObject(Store.shared)
                .environmentObject(PanelController.shared))
            host.sizingOptions = []
            p.contentView = host
            panel = p
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        panel.setFrame(NSRect(x: vf.midX - 280, y: vf.minY + vf.height * 0.68, width: 560, height: 120), display: true)
        NotificationCenter.default.post(name: .quickCaptureOpened, object: nil)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }
}

extension Notification.Name {
    static let quickCaptureOpened = Notification.Name("ghim.quickCaptureOpened")
    static let quickCaptureImageAdded = Notification.Name("ghim.quickCaptureImageAdded")
}

struct QuickCaptureView: View {
    var onDone: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController
    @State private var text = ""
    @State private var added: String?
    @FocusState private var focused: Bool

    private var target: Category? {
        let p = QuickParser.parse(text, categories: store.data.categories)
        if let id = p.categoryID { return store.category(id) }
        if case .category(let id) = pc.selection, let c = store.category(id) { return c }
        return store.taskCategories.first
    }

    var body: some View {
        let parsed = QuickParser.parse(text, categories: store.data.categories)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: added == nil ? "pin.fill" : "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(added == nil ? Color(hex: target?.colorHex ?? "#F26B3A") : .green)
                    .rotationEffect(.degrees(added == nil ? 35 : 0))
                TextField("Ghi nhanh một việc hoặc ghi chú…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium))
                    .focused($focused)
                    .onSubmit(submit)
            }
            HStack(spacing: 6) {
                if let added {
                    Text("Đã thêm vào \(added)").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.green)
                } else {
                    if let t = target { CategoryPill(category: t) }
                    if parsed.hasMeta { ParsedPreview(parsed: ParsedTask(priority: parsed.priority, due: parsed.due, hasTime: parsed.hasTime, isToday: parsed.isToday, repeatRule: parsed.repeatRule, estimateMin: parsed.estimateMin)) }
                    Spacer()
                    Text("#tab  !!  @mai  @15h  ~30m  ·  ⌘V ảnh  ·  ↩ thêm  ·  esc")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 16)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 560, alignment: .leading)
        .background(VisualEffect(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .quickCaptureOpened)) { _ in
            text = ""
            added = nil
            DispatchQueue.main.async { focused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickCaptureImageAdded)) { n in
            added = "\(n.object as? String ?? "Notes") (ảnh)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone() }
        }
        .onAppear { focused = true }
    }

    private func submit() {
        let p = QuickParser.parse(text, categories: store.data.categories)
        guard !p.title.trimmingCharacters(in: .whitespaces).isEmpty, let t = target else { onDone(); return }
        if t.kind == .notes {
            store.addNote(in: t.id, text: p.title)
        } else {
            store.addTask(p, category: t.id)
        }
        Sound.play("Pop")
        added = t.name
        text = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { onDone() }
    }
}

// MARK: - Settings window

enum SettingsTab: Hashable { case general, tabs, focus, help }

@MainActor
final class SettingsWindow {
    static var window: NSWindow?
    static let selection = SettingsSelection()

    static func show(tab: SettingsTab = .general) {
        selection.tab = tab
        if window == nil {
            let host = NSHostingController(rootView: SettingsView()
                .environmentObject(Store.shared)
                .environmentObject(Prefs.shared)
                .environmentObject(selection))
            let w = NSWindow(contentViewController: host)
            w.title = "Ghim – Cài đặt"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 520, height: 470))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @EnvironmentObject var sel: SettingsSelection

    var body: some View {
        TabView(selection: $sel.tab) {
            GeneralSettings().tabItem { Label("Chung", systemImage: "gearshape") }.tag(SettingsTab.general)
            TabsSettings().tabItem { Label("Các tab", systemImage: "rectangle.stack") }.tag(SettingsTab.tabs)
            FocusSettings().tabItem { Label("Tập trung", systemImage: "scope") }.tag(SettingsTab.focus)
            HelpSettings().tabItem { Label("Phím tắt", systemImage: "keyboard") }.tag(SettingsTab.help)
        }
        .padding(16)
        .frame(width: 520, height: 470)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var store: Store
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Cạnh màn hình", selection: $prefs.edgeRight) {
                    Text("Trái").tag(false)
                    Text("Phải").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent("Độ mờ khi không dùng") {
                    HStack {
                        Slider(value: $prefs.idleOpacity, in: 0.12...1)
                        Text("\(Int(prefs.idleOpacity * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Vị trí theo chiều dọc") {
                    HStack {
                        Text("Dưới").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $prefs.verticalFraction, in: 0...1)
                        Text("Trên").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Dải tab") }

            Section {
                Toggle("Rê chuột vào là mở (không cần bấm)", isOn: $prefs.hoverToOpen)
                Toggle("Tự thu gọn khi bấm ra ngoài", isOn: $prefs.autoCollapse)
                Toggle("Chế độ phóng to (rộng, cao hết màn hình)", isOn: $prefs.largeMode)
                LabeledContent("Kích thước panel") {
                    HStack {
                        Stepper("Rộng \(Int(prefs.panelWidth))", value: $prefs.panelWidth, in: 280...1200, step: 10)
                        Stepper("Cao \(Int(prefs.panelHeight))", value: $prefs.panelHeight, in: 300...1600, step: 20)
                    }
                }
            } header: { Text("Panel") }

            Section {
                Toggle("Âm thanh khi hoàn thành", isOn: $prefs.sounds)
                Toggle("Hiện tiến độ hôm nay trên thanh menu", isOn: $prefs.menuBarCount)
                Toggle("Mở cùng macOS", isOn: Binding(get: { loginEnabled }, set: setLogin))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                LabeledContent("Dữ liệu") {
                    Button("Mở thư mục") { NSWorkspace.shared.open(store.folderURL) }
                }
            } header: { Text("Khác") }
        }
        .formStyle(.grouped)
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Không thể đổi: \(error.localizedDescription). Hãy chép Ghim.app vào /Applications rồi thử lại."
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

private struct TabsSettings: View {
    @EnvironmentObject var store: Store
    @State private var confirmDelete: Category?
    private let palette = ["#F26B3A", "#F6B92B", "#EE8CC6", "#5C7FD9", "#4F7D5C", "#8B5CF6", "#14B8A6", "#64748B", "#EF4444", "#A16207"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mỗi tab là một mảnh giấy dán bên cạnh màn hình. Tab “Danh sách việc” có checkbox, tab “Ghi chú” là các thẻ ghi chú tự do.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(store.data.categories) { c in
                    CategoryEditorRow(category: c,
                                      isFirst: c.id == store.data.categories.first?.id,
                                      isLast: c.id == store.data.categories.last?.id,
                                      onDelete: { confirmDelete = c })
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            HStack {
                Button {
                    let used = Set(store.data.categories.map(\.colorHex))
                    store.addCategory(name: "Tab mới", colorHex: palette.first { !used.contains($0) } ?? "#64748B", kind: .tasks)
                } label: { Label("Thêm tab việc", systemImage: "plus") }
                Button {
                    store.addCategory(name: "Ghi chú", colorHex: "#14B8A6", kind: .notes)
                } label: { Label("Thêm tab ghi chú", systemImage: "note.text.badge.plus") }
                Spacer()
            }
        }
        .alert(item: $confirmDelete) { c in
            let n = store.data.tasks.filter { $0.categoryID == c.id }.count + store.data.notes.filter { $0.categoryID == c.id }.count
            return Alert(title: Text("Xoá tab “\(c.name)”?"),
                         message: Text(n > 0 ? "\(n) mục bên trong cũng sẽ bị xoá. Không thể hoàn tác." : "Tab đang trống."),
                         primaryButton: .destructive(Text("Xoá")) { store.deleteCategory(c.id) },
                         secondaryButton: .cancel(Text("Huỷ")))
        }
    }
}

private struct CategoryEditorRow: View {
    let category: Category
    let isFirst: Bool
    let isLast: Bool
    let onDelete: () -> Void
    @EnvironmentObject var store: Store
    @State private var name = ""

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: category.colorHex) },
                set: { var c = category; c.colorHex = $0.hexString; store.updateCategory(c) }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 40)
            TextField("Tên", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
                .onChange(of: name) { _, _ in commit() }
            Picker("", selection: Binding(
                get: { category.kind },
                set: { var c = category; c.kind = $0; store.updateCategory(c) }
            )) {
                ForEach(CategoryKind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)
            Button { store.moveCategory(category.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(isFirst)
            Button { store.moveCategory(category.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(isLast)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .onAppear { name = category.name }
    }

    private func commit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != category.name else { return }
        var c = category
        c.name = n
        store.updateCategory(c)
    }
}

private struct FocusSettings: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Section {
                Stepper("Phiên tập trung: \(prefs.focusMinutes) phút", value: $prefs.focusMinutes, in: 5...120, step: 5)
                Stepper("Nghỉ giải lao: \(prefs.breakMinutes) phút", value: $prefs.breakMinutes, in: 1...30)
                Toggle("Tự bắt đầu giờ nghỉ sau mỗi phiên", isOn: $prefs.autoBreak)
            } header: { Text("Pomodoro") } footer: {
                Text("Nếu việc có ước lượng thời gian (~30m), nút ▶ sẽ dùng số phút đó.")
            }
            Section {
                LabeledContent("Hôm nay", value: "\(store.focusToday) phút")
                LabeledContent("7 ngày qua", value: "\(last7()) phút")
                LabeledContent("Chuỗi ngày hoàn thành", value: "\(store.streak) ngày 🔥")
            } header: { Text("Thống kê") }
        }
        .formStyle(.grouped)
    }

    private func last7() -> Int {
        (0..<7).reduce(0) { sum, i in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            return sum + (store.data.focusLog[Day.key(d)] ?? 0)
        }
    }
}

private struct HelpSettings: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                group("Phím tắt toàn hệ thống", [
                    ("⌃⌥Space", "Mở / thu gọn dải tab"),
                    ("⌃⌥N", "Ghi nhanh từ bất kỳ đâu"),
                    ("⌃⌥T", "Mở tab Hôm nay"),
                ])
                group("Khi panel đang mở", [
                    ("⌘0", "Tab Hôm nay"),
                    ("⌘1 … ⌘9", "Chuyển tab"),
                    ("⌘N", "Thêm việc / ghi chú mới"),
                    ("⌘F", "Tìm kiếm mọi tab"),
                    ("Esc / ⌘W", "Thu gọn"),
                    ("Nhấp đúp vào việc", "Sửa chi tiết"),
                    ("Kéo thả việc", "Sắp xếp lại thứ tự"),
                ])
                group("Cú pháp ghi nhanh", [
                    ("#family", "Đưa vào tab Family (gõ vài chữ đầu là đủ)"),
                    ("!  !!  !!!", "Ưu tiên thấp / vừa / cao"),
                    ("@nay @mai @kia", "Hạn hôm nay / mai / ngày kia"),
                    ("@t2 … @cn, @fri", "Thứ trong tuần tới"),
                    ("@20/11  @+3", "Ngày cụ thể / 3 ngày nữa"),
                    ("@15h  @9:30  @3pm", "Giờ – sẽ có thông báo nhắc"),
                    ("~30m  ~1h", "Ước lượng thời gian"),
                    ("/daily /weekdays /weekly", "Lặp lại hằng ngày / T2–T6 / hằng tuần"),
                    ("*", "Đưa vào Hôm nay"),
                ])
            }
            .padding(4)
        }
    }

    private func group(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(rows, id: \.0) { k, v in
                HStack(alignment: .firstTextBaseline) {
                    Text(k).font(.system(.body, design: .monospaced)).frame(width: 190, alignment: .leading)
                    Text(v).foregroundStyle(.secondary)
                }
            }
        }
    }
}
