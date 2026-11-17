import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var data: AppData { didSet { if !applyingExternal { scheduleSave() } } }
    private var applyingExternal = false

    let folderURL: URL
    let fileURL: URL
    let imagesURL: URL
    private var saveWork: DispatchWorkItem?

    init() {
        folderURL = GhimPaths.folder
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        fileURL = folderURL.appendingPathComponent("data.json")
        imagesURL = folderURL.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)

        if let raw = try? Data(contentsOf: fileURL) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let decoded = try? dec.decode(AppData.self, from: raw), !decoded.categories.isEmpty {
                data = decoded
            } else {
                // Never silently destroy user data: keep a backup of the unreadable file.
                let backup = folderURL.appendingPathComponent("data-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fileURL, to: backup)
                data = .seed()
            }
        } else {
            data = .seed()
        }
        rollover()
    }

    // MARK: Persistence

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        do {
            let snapshot = data
            try DataFile.withLock { try DataFile.write(snapshot) }
        } catch {
            NSLog("Ghim: save failed \(error)")
        }
        Notifier.reschedule(tasks: data.tasks)
    }

    // MARK: New day

    /// Called on launch, every minute and on wake. Re-opens recurring tasks
    /// and clears yesterday's finished "today" flags.
    func rollover() {
        var d = data
        if d.rollover() { data = d }
    }

    // MARK: External changes (MCP / AI)

    /// The `--mcp` process edits data.json directly; reload when it says so,
    /// and flush pending edits when it is about to read.
    func observeExternalChanges() {
        let dnc = DistributedNotificationCenter.default()
        let me = folderURL.path
        dnc.addObserver(forName: .ghimFlush, object: me, queue: .main) { _ in
            MainActor.assumeIsolated {
                let s = Store.shared
                if s.saveWork != nil { s.saveNow() }
            }
        }
        dnc.addObserver(forName: .ghimDataChanged, object: me, queue: .main) { _ in
            MainActor.assumeIsolated { Store.shared.reloadFromDisk() }
        }
    }

    func reloadFromDisk() {
        guard let raw = try? Data(contentsOf: fileURL),
              let fresh = try? DataFile.decode(raw), !fresh.categories.isEmpty else { return }
        saveWork?.cancel()
        saveWork = nil
        applyingExternal = true
        data = fresh
        applyingExternal = false
        Notifier.reschedule(tasks: data.tasks)
    }

    // MARK: Lookups

    func category(_ id: UUID) -> Category? { data.categories.first { $0.id == id } }

    var taskCategories: [Category] { data.categories.filter { $0.kind == .tasks } }

    var defaultTaskCategoryID: UUID? { taskCategories.first?.id }

    func openTasks(in cat: UUID) -> [TaskItem] {
        data.tasks.filter { $0.categoryID == cat && !$0.done }.sorted { $0.order < $1.order }
    }

    func doneTasks(in cat: UUID) -> [TaskItem] {
        data.tasks.filter { $0.categoryID == cat && $0.done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func openCount(_ cat: UUID) -> Int { data.tasks.reduce(0) { $0 + ($1.categoryID == cat && !$1.done ? 1 : 0) } }
    func overdueCount(_ cat: UUID) -> Int { data.tasks.reduce(0) { $0 + ($1.categoryID == cat && $1.isOverdue ? 1 : 0) } }

    func notes(in cat: UUID) -> [Note] {
        data.notes.filter { $0.categoryID == cat }.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.createdAt > $1.createdAt
        }
    }

    // MARK: Today

    func inToday(_ t: TaskItem) -> Bool { AppData.inToday(t) }

    var todayOpen: [TaskItem] {
        data.tasks.filter { !$0.done && inToday($0) }.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            if a.priority != b.priority { return a.priority > b.priority }
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.order < b.order
            }
        }
    }

    var todayDone: [TaskItem] {
        let start = Day.startOfToday
        return data.tasks.filter { $0.done && ($0.completedAt ?? .distantPast) >= start && inToday($0) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var todayProgress: (done: Int, total: Int) {
        let d = todayDone.count
        return (d, d + todayOpen.count)
    }

    var suggestions: [TaskItem] {
        data.tasks.filter { !$0.done && !inToday($0) }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority > b.priority }
                switch (a.due, b.due) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.createdAt < b.createdAt
                }
            }
            .prefix(3).map { $0 }
    }

    var completedToday: Int { data.completions[Day.key()] ?? 0 }
    var focusToday: Int { data.focusLog[Day.key()] ?? 0 }

    var streak: Int { data.streak }

    // MARK: Task mutations

    private func idx(_ id: UUID) -> Int? { data.tasks.firstIndex { $0.id == id } }

    @discardableResult
    func addTask(_ p: ParsedTask, category: UUID, forceToday: Bool = false) -> UUID? {
        let title = p.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        var t = TaskItem(title: title, categoryID: category)
        t.priority = p.priority
        t.due = p.due
        t.hasTime = p.hasTime
        t.isToday = p.isToday || forceToday
        t.repeatRule = p.repeatRule
        t.estimateMin = p.estimateMin
        let minOrder = data.tasks.filter { $0.categoryID == category }.map(\.order).min() ?? 0
        t.order = minOrder - 1
        data.tasks.append(t)
        return t.id
    }

    func toggle(_ id: UUID) {
        guard let i = idx(id) else { return }
        var d = data
        d.setDone(id, !d.tasks[i].done)
        data = d
    }

    func update(_ t: TaskItem) {
        guard let i = idx(t.id) else { return }
        data.tasks[i] = t
    }

    func modify(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let i = idx(id) else { return }
        var t = data.tasks[i]
        change(&t)
        data.tasks[i] = t
    }

    func delete(_ id: UUID) { data.tasks.removeAll { $0.id == id } }

    func duplicate(_ id: UUID) {
        guard let i = idx(id) else { return }
        var t = data.tasks[i]
        t.id = UUID()
        t.done = false
        t.completedAt = nil
        t.focusedMin = 0
        t.createdAt = Date()
        t.order += 0.5
        data.tasks.append(t)
    }

    func binding(for id: UUID) -> Binding<TaskItem> {
        Binding(
            get: { [weak self] in
                self?.data.tasks.first { $0.id == id } ?? TaskItem(title: "", categoryID: UUID())
            },
            set: { [weak self] nv in
                guard let self, let i = self.idx(id) else { return }
                self.data.tasks[i] = nv
            }
        )
    }

    func move(in cat: UUID, from: IndexSet, to: Int) {
        var list = openTasks(in: cat)
        list.move(fromOffsets: from, toOffset: to)
        var d = data
        for (n, t) in list.enumerated() {
            if let i = d.tasks.firstIndex(where: { $0.id == t.id }) { d.tasks[i].order = Double(n) }
        }
        data = d
    }

    func clearDone(in cat: UUID) { data.tasks.removeAll { $0.categoryID == cat && $0.done && $0.repeatRule == .none } }

    func addFocus(task: UUID?, minutes: Int) {
        guard minutes > 0 else { return }
        var d = data
        d.focusLog[Day.key(), default: 0] += minutes
        if let task, let i = d.tasks.firstIndex(where: { $0.id == task }) { d.tasks[i].focusedMin += minutes }
        data = d
    }

    // MARK: Notes

    @discardableResult
    func addNote(in cat: UUID, text: String = "") -> UUID {
        let n = Note(categoryID: cat, text: text)
        data.notes.append(n)
        return n.id
    }

    func noteBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.data.notes.first { $0.id == id }?.text ?? "" },
            set: { [weak self] nv in
                guard let self, let i = self.data.notes.firstIndex(where: { $0.id == id }) else { return }
                self.data.notes[i].text = nv
                self.data.notes[i].updatedAt = Date()
            }
        )
    }

    func toggleNotePin(_ id: UUID) {
        guard let i = data.notes.firstIndex(where: { $0.id == id }) else { return }
        data.notes[i].pinned.toggle()
    }

    func deleteNote(_ id: UUID) {
        if let n = data.notes.first(where: { $0.id == id }) { n.images.forEach(deleteImageFile) }
        data.notes.removeAll { $0.id == id }
    }

    func cleanEmptyNotes() {
        if data.notes.contains(where: \.isEmpty) {
            data.notes.removeAll(where: \.isEmpty)
        }
    }

    // MARK: Note images

    func imageURL(_ name: String) -> URL { imagesURL.appendingPathComponent(name) }

    /// Saves image payloads and attaches them to a note (creating one in `category` when `noteID` is nil).
    /// Returns the note id.
    @discardableResult
    func attachImages(_ payloads: [ImagePayload], to noteID: UUID?, category: UUID) -> UUID? {
        let names = payloads.compactMap(saveImage)
        guard !names.isEmpty else { return nil }
        if let noteID, let i = data.notes.firstIndex(where: { $0.id == noteID }) {
            data.notes[i].images += names
            data.notes[i].updatedAt = Date()
            return noteID
        }
        var n = Note(categoryID: category)
        n.images = names
        data.notes.append(n)
        return n.id
    }

    func removeImage(_ name: String, from noteID: UUID) {
        guard let i = data.notes.firstIndex(where: { $0.id == noteID }) else { return }
        data.notes[i].images.removeAll { $0 == name }
        deleteImageFile(name)
    }

    private func saveImage(_ p: ImagePayload) -> String? {
        let name = "\(UUID().uuidString.prefix(12)).\(p.ext)"
        do {
            try p.data.write(to: imageURL(name), options: .atomic)
            return name
        } catch {
            NSLog("Ghim: image save failed \(error)")
            return nil
        }
    }

    private func deleteImageFile(_ name: String) {
        ImageCache.shared.remove(name)
        try? FileManager.default.removeItem(at: imageURL(name))
    }

    /// Turns the first line of a note into a task in the default list.
    func noteToTask(_ id: UUID) -> Bool {
        guard let n = data.notes.first(where: { $0.id == id }),
              let line = n.text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }),
              let cat = defaultTaskCategoryID else { return false }
        var p = QuickParser.parse(line, categories: data.categories)
        if p.title.isEmpty { p.title = line }
        addTask(p, category: p.categoryID.flatMap { category($0)?.kind == .tasks ? $0 : nil } ?? cat)
        return true
    }

    // MARK: Categories

    func addCategory(name: String, colorHex: String, kind: CategoryKind) {
        data.categories.append(Category(name: name, colorHex: colorHex, kind: kind))
    }

    func updateCategory(_ c: Category) {
        guard let i = data.categories.firstIndex(where: { $0.id == c.id }) else { return }
        data.categories[i] = c
    }

    func deleteCategory(_ id: UUID) {
        var d = data
        d.categories.removeAll { $0.id == id }
        d.tasks.removeAll { $0.categoryID == id }
        d.notes.removeAll { $0.categoryID == id }
        data = d
    }

    func moveCategory(_ id: UUID, by delta: Int) {
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < data.categories.count else { return }
        data.categories.swapAt(i, j)
    }

    // MARK: Export

    func exportMarkdown() -> String {
        var out = "# Ghim — \(Day.longFormatter.string(from: Date()))\n"
        for c in data.categories {
            out += "\n## \(c.name)\n"
            if c.kind == .tasks {
                for t in openTasks(in: c.id) + doneTasks(in: c.id) {
                    var line = "- [\(t.done ? "x" : " ")] \(t.title)"
                    if t.priority != .none { line += " \(t.priority.marks)" }
                    if t.due != nil { line += " (hạn: \(Day.dueLabel(t)))" }
                    out += line + "\n"
                    if !t.note.isEmpty { out += "  > " + t.note.replacingOccurrences(of: "\n", with: "\n  > ") + "\n" }
                }
            } else {
                for n in notes(in: c.id) {
                    out += n.text + "\n"
                    for img in n.images { out += "![](\(imageURL(img).path.replacingOccurrences(of: " ", with: "%20")))\n" }
                    out += "\n---\n"
                }
            }
        }
        return out
    }
}
