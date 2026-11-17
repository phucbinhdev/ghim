import SwiftUI

// MARK: - Add field with live parsing

struct AddTaskField: View {
    var categoryID: UUID?
    var forceToday = false
    var placeholder = "Thêm việc…   #tab  !!  @mai  @15h  ~30m"

    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = QuickParser.parse(text, categories: store.data.categories)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(focused ? Color.accentColor : Color.secondary.opacity(0.7))
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(submit)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(focused ? 0.08 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.accentColor.opacity(focused ? 0.5 : 0), lineWidth: 1))

            if parsed.hasMeta && !text.isEmpty {
                ParsedPreview(parsed: parsed).padding(.leading, 4)
                    .transition(.opacity)
            }
        }
        .onChange(of: pc.focusRequest) { _, _ in focused = true }
        .onAppear {
            if pc.focusRequest > 0 { DispatchQueue.main.async { focused = true } }
        }
    }

    private func submit() {
        let p = QuickParser.parse(text, categories: store.data.categories)
        guard !p.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let target = p.categoryID ?? categoryID ?? store.defaultTaskCategoryID
        guard let target else { return }
        withAnimation(.snappy) {
            if store.category(target)?.kind == .notes {
                store.addNote(in: target, text: p.title)
            } else {
                store.addTask(p, category: target, forceToday: forceToday)
            }
        }
        text = ""
        focused = true
    }
}

struct ParsedPreview: View {
    let parsed: ParsedTask
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 4) {
            if let id = parsed.categoryID, let c = store.category(id) { CategoryPill(category: c) }
            if parsed.priority != .none { Chip(symbol: "flag.fill", text: parsed.priority.label, color: parsed.priority.color) }
            if let d = parsed.due {
                Chip(symbol: "calendar", text: Day.dueLabel(due: d, hasTime: parsed.hasTime), color: .blue)
            } else if parsed.isToday {
                Chip(symbol: "sun.max.fill", text: "Hôm nay", color: .orange)
            }
            if let m = parsed.estimateMin { Chip(symbol: "hourglass", text: "\(m)′", color: .purple) }
            if parsed.repeatRule != .none { Chip(symbol: "arrow.clockwise", text: parsed.repeatRule.short, color: .teal) }
        }
    }
}

// MARK: - List of a task category

struct TaskListView: View {
    let category: Category
    @EnvironmentObject var store: Store
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        let open = store.openTasks(in: category.id)
        let done = store.doneTasks(in: category.id)
        VStack(spacing: 0) {
            AddTaskField(categoryID: category.id)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            if open.isEmpty && done.isEmpty {
                EmptyState(symbol: "checklist", title: "Chưa có gì ở đây",
                           subtitle: "Gõ vào ô bên trên rồi Enter.\nVí dụ: Nộp báo cáo !! @t6 @17h")
                Spacer()
            } else {
                List {
                    ForEach(open) { t in
                        TaskRow(task: t).ghimRow()
                    }
                    .onMove { store.move(in: category.id, from: $0, to: $1) }

                    if open.isEmpty {
                        Text("Xong hết rồi! 🎉").font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 10).ghimRow()
                    }

                    if !done.isEmpty {
                        DoneHeader(count: done.count, expanded: $prefs.showCompleted) {
                            withAnimation { store.clearDone(in: category.id) }
                        }
                        .ghimRow()
                        if prefs.showCompleted {
                            ForEach(done) { t in TaskRow(task: t).ghimRow() }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 10)
            }
        }
    }
}

struct DoneHeader: View {
    let count: Int
    @Binding var expanded: Bool
    var onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Đã xong (\(count))").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if let onClear {
                Button("Dọn dẹp", action: onClear)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .help("Xoá các việc đã xong (việc lặp lại được giữ)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

// MARK: - Row

struct CheckCircle: View {
    let done: Bool
    let color: Color
    var body: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(done ? 1 : 0.85), lineWidth: 1.6)
            if done {
                Circle().fill(color)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Circle().inset(by: -4))
    }
}

struct TaskRow: View {
    let task: TaskItem
    var showCategory = false

    @EnvironmentObject var store: Store
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var pc: PanelController
    @State private var hover = false
    @State private var editing = false
    @State private var justChecked = false

    private var cat: Category? { store.category(task.categoryID) }
    private var circleColor: Color {
        task.priority != .none ? task.priority.color : Color(hex: cat?.colorHex ?? "#888888")
    }
    private var isFocusing: Bool { timer.active && !timer.isBreak && timer.taskID == task.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 9) {
                CheckCircle(done: task.done || justChecked, color: circleColor)
                    .padding(.top, 1)
                    .onTapGesture { check() }
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 13))
                        .strikethrough(task.done, color: .secondary)
                        .foregroundStyle(task.done ? Color.secondary : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    meta
                }
                Spacer(minLength: 0)

            }
            if editing {
                TaskEditor(task: store.binding(for: task.id), onClose: { withAnimation(.snappy) { editing = false } })
                    .padding(.leading, 25)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isFocusing ? Color(hex: "#FF5A5F").opacity(0.12) : Color.primary.opacity(hover || editing ? 0.06 : 0))
        )
        // Hover actions float over the top-right corner: the title keeps the full width
        // and never re-wraps when the mouse moves over the row.
        .overlay(alignment: .topTrailing) {
            if (hover || isFocusing) && !task.done && !editing {
                actions
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    .padding(.top, 3)
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
        .onTapGesture(count: 2) { withAnimation(.snappy) { editing.toggle() } }
        .contextMenu { TaskMenu(task: task, onEdit: { withAnimation(.snappy) { editing = true } }) }
    }

    private func check() {
        if task.done {
            withAnimation(.snappy) { store.toggle(task.id) }
            return
        }
        justChecked = true
        Sound.play("Pop")
        if isFocusing { timer.stop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.snappy) { store.toggle(task.id) }
            justChecked = false
        }
    }

    @ViewBuilder private var meta: some View {
        let hasMeta = showCategory || task.due != nil || task.repeatRule != .none || task.estimateMin != nil
            || task.focusedMin > 0 || !task.note.isEmpty || (task.isToday && !showCategory) || task.priority != .none
        if hasMeta {
            HStack(spacing: 4) {
                if showCategory, let cat { CategoryPill(category: cat) }
                if task.priority != .none {
                    Text(task.priority.marks).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(task.priority.color)
                }
                if task.due != nil {
                    Chip(symbol: task.hasTime ? "clock" : "calendar", text: Day.dueLabel(task),
                         color: task.isOverdue ? .red : (Calendar.current.isDateInToday(task.due!) ? .orange : .blue))
                } else if task.isToday && !showCategory && !task.done {
                    Chip(symbol: "sun.max.fill", text: "Hôm nay", color: .orange)
                }
                if task.repeatRule != .none { Chip(symbol: "arrow.clockwise", text: task.repeatRule.short, color: .teal) }
                if let m = task.estimateMin { Chip(symbol: "hourglass", text: "\(m)′", color: .purple) }
                if task.focusedMin > 0 { Chip(symbol: "scope", text: "\(task.focusedMin)′", color: Color(hex: "#FF5A5F")) }
                if !task.note.isEmpty { Image(systemName: "text.alignleft").font(.system(size: 9)).foregroundStyle(.tertiary) }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            do {
                IconButton(task.isToday ? "sun.max.fill" : "sun.max", size: 11, tint: task.isToday ? .orange : .secondary,
                           help: task.isToday ? "Bỏ khỏi Hôm nay" : "Thêm vào Hôm nay") {
                    withAnimation(.snappy) { store.modify(task.id) { $0.isToday.toggle() } }
                }
            }
            IconButton(isFocusing ? "stop.fill" : "play.fill", size: 11, tint: isFocusing ? Color(hex: "#FF5A5F") : .secondary,
                       help: isFocusing ? "Dừng tập trung" : "Tập trung \(Prefs.shared.focusMinutes) phút") {
                if isFocusing { timer.stop() } else { timer.start(task: task.id, minutes: task.estimateMin.map { min(max($0, 5), 90) }) }
            }
            Menu {
                TaskMenu(task: task, onEdit: { withAnimation(.snappy) { editing = true } })
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

struct TaskMenu: View {
    let task: TaskItem
    var onEdit: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var timer: FocusTimer

    var body: some View {
        Button(task.done ? "Đánh dấu chưa xong" : "Hoàn thành") { withAnimation { store.toggle(task.id) } }
        Button(task.isToday ? "Bỏ khỏi Hôm nay" : "Thêm vào Hôm nay") { store.modify(task.id) { $0.isToday.toggle() } }
        if !task.done {
            Button("Tập trung \(Prefs.shared.focusMinutes) phút") { timer.start(task: task.id) }
        }
        Button("Sửa chi tiết…", action: onEdit)
        Divider()
        Menu("Hạn") {
            Button("Hôm nay") { setDue(Day.startOfToday) }
            Button("Ngày mai") { setDue(Calendar.current.date(byAdding: .day, value: 1, to: Day.startOfToday)!) }
            Button("Thứ Hai tuần sau") { setDue(Day.nextMonday()) }
            Button("Bỏ hạn") { store.modify(task.id) { $0.due = nil; $0.hasTime = false } }
        }
        Menu("Ưu tiên") {
            ForEach(Priority.allCases.reversed()) { p in
                Button((p == task.priority ? "✓ " : "") + p.label + (p == .none ? "" : "  " + p.marks)) {
                    store.modify(task.id) { $0.priority = p }
                }
            }
        }
        Menu("Lặp lại") {
            ForEach(RepeatRule.allCases) { r in
                Button((r == task.repeatRule ? "✓ " : "") + r.label) { store.modify(task.id) { $0.repeatRule = r } }
            }
        }
        Menu("Chuyển sang") {
            ForEach(store.taskCategories) { c in
                Button((c.id == task.categoryID ? "✓ " : "") + c.name) { withAnimation { store.modify(task.id) { $0.categoryID = c.id } } }
            }
        }
        Divider()
        Button("Nhân bản") { store.duplicate(task.id) }
        Button("Sao chép nội dung") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(task.title, forType: .string)
        }
        Divider()
        Button("Xoá", role: .destructive) { withAnimation { store.delete(task.id) } }
    }

    private func setDue(_ d: Date) {
        store.modify(task.id) { $0.due = d; $0.hasTime = false }
    }
}

// MARK: - Inline editor

struct TaskEditor: View {
    @Binding var task: TaskItem
    var onClose: () -> Void
    @EnvironmentObject var store: Store

    private var hasDue: Binding<Bool> {
        Binding(get: { task.due != nil },
                set: { on in
                    if on { task.due = Calendar.current.date(byAdding: .day, value: 0, to: Day.startOfToday) }
                    else { task.due = nil; task.hasTime = false }
                })
    }
    private var dueDate: Binding<Date> {
        Binding(get: { task.due ?? Day.startOfToday }, set: { task.due = $0 })
    }
    private var estimate: Binding<Int> {
        Binding(get: { task.estimateMin ?? 0 }, set: { task.estimateMin = $0 == 0 ? nil : $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tiêu đề", text: $task.title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
            TextField("Ghi chú, link, chi tiết…", text: $task.note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .lineLimit(1...6)

            HStack(spacing: 8) {
                Toggle("Hạn", isOn: hasDue).toggleStyle(.checkbox)
                if task.due != nil {
                    DatePicker("", selection: dueDate, displayedComponents: task.hasTime ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .font(.system(size: 11))
                    Toggle("Giờ", isOn: $task.hasTime).toggleStyle(.checkbox)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11.5))

            HStack(spacing: 8) {
                Picker("", selection: $task.priority) {
                    Text("–").tag(Priority.none)
                    Text("!").tag(Priority.low)
                    Text("!!").tag(Priority.medium)
                    Text("!!!").tag(Priority.high)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                .help("Mức ưu tiên")
                Picker("", selection: estimate) {
                    Text("⏳ –").tag(0)
                    ForEach([5, 10, 15, 25, 30, 45, 60, 90, 120], id: \.self) { Text("⏳ \($0)′").tag($0) }
                }
                .labelsHidden()
                .frame(width: 80)
                .help("Ước lượng thời gian – nút ▶ sẽ dùng số phút này")
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                Picker("", selection: $task.repeatRule) {
                    ForEach(RepeatRule.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                Picker("", selection: $task.categoryID) {
                    ForEach(store.taskCategories) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 90)
                Spacer(minLength: 0)
            }
            .controlSize(.small)

            HStack {
                if task.focusedMin > 0 {
                    Text("Đã tập trung \(task.focusedMin) phút").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Xoá", role: .destructive) { withAnimation { store.delete(task.id) } }
                    .controlSize(.small)
                Button("Xong") { onClose() }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 2)
        .padding(.trailing, 4)
    }
}
