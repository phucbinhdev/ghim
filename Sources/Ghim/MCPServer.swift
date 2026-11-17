import Foundation

/// A Model Context Protocol server over stdio, started with `Ghim --mcp`.
/// It reads and writes the same data.json as the app (under a file lock) and
/// pings the running app so the panel refreshes instantly.
enum MCPServer {
    static let version = "1.0"
    static let supportedProtocols = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    static func run() -> Never {
        try? FileManager.default.createDirectory(at: GhimPaths.images, withIntermediateDirectories: true)
        while let line = readLine(strippingNewline: true) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let raw = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: raw) else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            if let batch = obj as? [[String: Any]] {
                let replies = batch.compactMap(handle)
                if !replies.isEmpty { send(replies) }
            } else if let msg = obj as? [String: Any], let reply = handle(msg) {
                send(reply)
            }
        }
        exit(0)
    }

    private static func send(_ obj: Any) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static func handle(_ msg: [String: Any]) -> [String: Any]? {
        let method = msg["method"] as? String ?? ""
        guard let id = msg["id"] else { return nil } // notification: no reply
        func ok(_ result: Any) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        func fail(_ code: Int, _ m: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": m]] }

        switch method {
        case "initialize":
            let asked = (msg["params"] as? [String: Any])?["protocolVersion"] as? String ?? ""
            return ok([
                "protocolVersion": supportedProtocols.contains(asked) ? asked : supportedProtocols[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "ghim", "title": "Ghim — ghi chú & việc cạnh màn hình", "version": version],
                "instructions": instructions,
            ])
        case "ping":
            return ok([String: Any]())
        case "tools/list":
            return ok(["tools": MCPTools.definitions])
        case "tools/call":
            let p = msg["params"] as? [String: Any] ?? [:]
            let name = p["name"] as? String ?? ""
            let args = p["arguments"] as? [String: Any] ?? [:]
            do {
                let out = try MCPTools.call(name, args)
                return ok(["content": [["type": "text", "text": out]], "isError": false])
            } catch let e as ToolError {
                return ok(["content": [["type": "text", "text": e.message]], "isError": true])
            } catch {
                return ok(["content": [["type": "text", "text": "Lỗi: \(error.localizedDescription)"]], "isError": true])
            }
        default:
            return fail(-32601, "Method not found: \(method)")
        }
    }

    static let instructions = """
    Ghim is the user's sticky-tab app on the macOS screen edge holding their tasks and notes, \
    grouped into coloured lists (tabs). Start with get_overview to see today's plan and the list names. \
    IDs are short 8-char prefixes; pass them back as-is. add_task accepts Ghim quick syntax in `text`: \
    #list, ! / !! / !!! priority, * = today, @mai/@t2/@25/12/@15h due, ~30m estimate, /daily /weekdays /weekly. \
    Changes appear in the app immediately. Write titles in the user's language.
    """
}

struct ToolError: Error { let message: String; init(_ m: String) { message = m } }

// MARK: - Tools

enum MCPTools {
    // MARK: Schema

    private static func tool(_ name: String, _ title: String, _ desc: String, _ props: [String: Any] = [:],
                             required: [String] = [], readOnly: Bool = false, destructive: Bool = false) -> [String: Any] {
        [
            "name": name,
            "title": title,
            "description": desc,
            "inputSchema": ["type": "object", "properties": props, "required": required, "additionalProperties": false],
            "annotations": ["readOnlyHint": readOnly, "destructiveHint": destructive, "idempotentHint": readOnly, "openWorldHint": false],
        ]
    }
    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func bool(_ d: String) -> [String: Any] { ["type": "boolean", "description": d] }

    private static let listArg = str("List (tab) name or id, e.g. \"To-Do\". Prefix and accent-insensitive.")
    private static let dueArg = str("Due date: YYYY-MM-DD, YYYY-MM-DD HH:mm, or mai/nay/t2..cn/+3/25/12, optionally with a time like 15h. Empty string clears it.")
    private static let prioArg: [String: Any] = ["type": "string", "enum": ["none", "low", "medium", "high"], "description": "Priority"]
    private static let repeatArg: [String: Any] = ["type": "string", "enum": ["none", "daily", "weekdays", "weekly"], "description": "Repeat rule"]

    static let definitions: [[String: Any]] = [
        tool("get_overview", "Today overview",
             "Today's plan (open and finished tasks), overdue tasks, every list with counts, streak and focus minutes. Call this first.",
             readOnly: true),
        tool("list_tasks", "List tasks",
             "Tasks filtered by list, status, today or text.",
             ["list": listArg,
              "status": ["type": "string", "enum": ["open", "done", "all"], "description": "Default open"],
              "today_only": bool("Only tasks planned for today or due by today"),
              "query": str("Case/accent-insensitive text filter on title and note")],
             readOnly: true),
        tool("add_task", "Add task",
             "Adds a task to the top of a list. `text` may use Ghim quick syntax (#list !! * @mai @15h ~30m /daily); explicit fields override it.",
             ["text": str("Task title, optionally with quick syntax"), "list": listArg,
              "today": bool("Put it in today's plan"), "due": dueArg, "priority": prioArg,
              "repeat": repeatArg, "estimate_min": ["type": "integer", "description": "Estimated minutes"],
              "note": str("Extra details shown under the task")],
             required: ["text"]),
        tool("update_task", "Update task",
             "Changes a task: complete/reopen it, rename, move, reschedule, re-prioritise. Only the given fields change.",
             ["id": str("Task id"), "done": bool("true = complete, false = reopen"), "title": str("New title"),
              "list": listArg, "today": bool("In today's plan or not"), "due": dueArg, "priority": prioArg,
              "repeat": repeatArg, "estimate_min": ["type": "integer", "description": "Estimated minutes, 0 clears"],
              "note": str("Replace the task's note")],
             required: ["id"]),
        tool("delete_task", "Delete task", "Permanently deletes a task.",
             ["id": str("Task id")], required: ["id"], destructive: true),
        tool("list_notes", "List notes",
             "Notes (free text cards, may have images) in notes-type lists. Pinned first, then newest.",
             ["list": listArg, "query": str("Text filter")], readOnly: true),
        tool("add_note", "Add note", "Creates a note card.",
             ["text": str("Note text"), "list": listArg, "pinned": bool("Pin to the top")], required: ["text"]),
        tool("update_note", "Update note", "Replaces or appends note text, or pins/unpins it.",
             ["id": str("Note id"), "text": str("Replace the whole text"), "append": str("Append as a new line"),
              "pinned": bool("Pin state")], required: ["id"]),
        tool("delete_note", "Delete note", "Permanently deletes a note and its images.",
             ["id": str("Note id")], required: ["id"], destructive: true),
        tool("search", "Search", "Searches all tasks (open and done) and notes.",
             ["query": str("Text to find")], required: ["query"], readOnly: true),
    ]

    // MARK: Dispatch

    static func call(_ name: String, _ a: [String: Any]) throws -> String {
        switch name {
        case "get_overview": return try read { overview($0) }
        case "list_tasks": return try read { try listTasks($0, a) }
        case "list_notes": return try read { try listNotes($0, a) }
        case "search": return try read { try search($0, a) }
        case "add_task": return try write { try addTask(&$0, a) }
        case "update_task": return try write { try updateTask(&$0, a) }
        case "delete_task": return try write { try deleteTask(&$0, a) }
        case "add_note": return try write { try addNote(&$0, a) }
        case "update_note": return try write { try updateNote(&$0, a) }
        case "delete_note": return try write { try deleteNote(&$0, a) }
        default: throw ToolError("Unknown tool: \(name)")
        }
    }

    // MARK: Data access

    private static var appFolderObject: String { GhimPaths.folder.path }

    /// Ask a running Ghim to write any unsaved edits before we read.
    private static func flushApp() {
        DistributedNotificationCenter.default().postNotificationName(.ghimFlush, object: appFolderObject,
                                                                     userInfo: nil, deliverImmediately: true)
        usleep(120_000)
    }

    private static func load() throws -> AppData {
        guard let raw = try? Data(contentsOf: GhimPaths.dataFile) else {
            // First run without the app: create the starter data so ids stay stable.
            let seed = AppData.seed()
            try? FileManager.default.createDirectory(at: GhimPaths.folder, withIntermediateDirectories: true)
            try DataFile.write(seed)
            return seed
        }
        guard let d = try? DataFile.decode(raw), !d.categories.isEmpty else {
            throw ToolError("data.json không đọc được — mở app Ghim để nó tự sao lưu và khôi phục.")
        }
        return d
    }

    private static func read(_ body: (AppData) throws -> Any) throws -> String {
        flushApp()
        var d = try DataFile.withLock { try load() }
        d.rollover()
        return json(try body(d))
    }

    private static func write(_ body: (inout AppData) throws -> Any) throws -> String {
        flushApp()
        let out = try DataFile.withLock { () -> Any in
            var d = try load()
            d.rollover()
            let r = try body(&d)
            try DataFile.write(d)
            return r
        }
        DistributedNotificationCenter.default().postNotificationName(.ghimDataChanged, object: appFolderObject,
                                                                     userInfo: nil, deliverImmediately: true)
        return json(out)
    }

    private static func json(_ v: Any) -> String {
        if let s = v as? String { return s }
        guard let data = try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else { return "\(v)" }
        return s
    }

    // MARK: Formatting

    static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let dayTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()
    private static let prioNames: [Priority: String] = [.none: "none", .low: "low", .medium: "medium", .high: "high"]

    private static func taskDict(_ t: TaskItem, _ d: AppData) -> [String: Any] {
        var o: [String: Any] = ["id": short(t.id), "title": t.title]
        o["list"] = d.categories.first { $0.id == t.categoryID }?.name ?? "?"
        if t.done {
            o["done"] = true
            if let c = t.completedAt { o["completed_at"] = dayTimeFmt.string(from: c) }
        }
        if AppData.inToday(t) { o["today"] = true }
        if let due = t.due {
            o["due"] = t.hasTime ? dayTimeFmt.string(from: due) : dayFmt.string(from: due)
            if t.isOverdue { o["overdue"] = true }
        }
        if t.priority != .none { o["priority"] = prioNames[t.priority] }
        if t.repeatRule != .none { o["repeat"] = t.repeatRule.rawValue }
        if let e = t.estimateMin { o["estimate_min"] = e }
        if t.focusedMin > 0 { o["focused_min"] = t.focusedMin }
        if !t.note.isEmpty { o["note"] = t.note }
        return o
    }

    private static func noteDict(_ n: Note, _ d: AppData) -> [String: Any] {
        var o: [String: Any] = ["id": short(n.id), "text": n.text,
                                "list": d.categories.first { $0.id == n.categoryID }?.name ?? "?",
                                "updated_at": dayTimeFmt.string(from: n.updatedAt)]
        if n.pinned { o["pinned"] = true }
        if !n.images.isEmpty { o["images"] = n.images.map { GhimPaths.images.appendingPathComponent($0).path } }
        return o
    }

    private static func sortedTasks(_ tasks: [TaskItem], _ d: AppData) -> [TaskItem] {
        let rank = Dictionary(uniqueKeysWithValues: d.categories.enumerated().map { ($1.id, $0) })
        return tasks.sorted {
            let (ra, rb) = (rank[$0.categoryID] ?? 99, rank[$1.categoryID] ?? 99)
            if ra != rb { return ra < rb }
            if $0.done != $1.done { return !$0.done }
            return $0.order < $1.order
        }
    }

    // MARK: Lookups

    private static func fold(_ s: String) -> String { QuickParser.fold(s) }

    private static func matches(_ text: String, _ q: String) -> Bool {
        let fq = fold(q)
        return fq.isEmpty || fold(text).contains(fq)
    }

    private static func category(_ q: String, _ d: AppData, kind: CategoryKind?) throws -> Category {
        let pool = d.categories.filter { kind == nil || $0.kind == kind }
        let fq = fold(q)
        if let c = pool.first(where: { short($0.id) == q.lowercased() })
            ?? pool.first(where: { fold($0.name) == fq })
            ?? pool.first(where: { fold($0.name).hasPrefix(fq) }) {
            return c
        }
        let names = pool.map(\.name).joined(separator: ", ")
        throw ToolError("Không có danh sách \"\(q)\"\(kind == .notes ? " (loại ghi chú)" : kind == .tasks ? " (loại việc)" : ""). Có: \(names)")
    }

    private static func taskIndex(_ a: [String: Any], _ d: AppData) throws -> Int {
        let q = (a["id"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 4 else { throw ToolError("Cần id của task (ít nhất 4 ký tự).") }
        let hits = d.tasks.indices.filter { d.tasks[$0].id.uuidString.lowercased().hasPrefix(q) }
        guard hits.count == 1 else { throw ToolError(hits.isEmpty ? "Không tìm thấy task \(q)." : "id \(q) trùng nhiều task, dùng id dài hơn.") }
        return hits[0]
    }

    private static func noteIndex(_ a: [String: Any], _ d: AppData) throws -> Int {
        let q = (a["id"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 4 else { throw ToolError("Cần id của note (ít nhất 4 ký tự).") }
        let hits = d.notes.indices.filter { d.notes[$0].id.uuidString.lowercased().hasPrefix(q) }
        guard hits.count == 1 else { throw ToolError(hits.isEmpty ? "Không tìm thấy note \(q)." : "id \(q) trùng nhiều note, dùng id dài hơn.") }
        return hits[0]
    }

    private static func parsePriority(_ v: Any?) throws -> Priority? {
        guard let v else { return nil }
        if let n = v as? Int, let p = Priority(rawValue: n) { return p }
        let s = "\(v)".lowercased()
        if let p = prioNames.first(where: { $0.value == s })?.key { return p }
        if (1...3).contains(s.count), s.allSatisfy({ $0 == "!" }) { return Priority(rawValue: s.count) }
        throw ToolError("priority phải là none/low/medium/high.")
    }

    private static func parseRepeat(_ v: Any?) throws -> RepeatRule? {
        guard let s = v as? String else { return nil }
        guard let r = RepeatRule(rawValue: s.lowercased()) else { throw ToolError("repeat phải là none/daily/weekdays/weekly.") }
        return r
    }

    /// Returns (date, hasTime), or nil date for "" (clear).
    private static func parseDue(_ s: String) throws -> (Date?, Bool) {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return (nil, false) }
        for f in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = f
            if let d = fmt.date(from: v) { return (d, true) }
        }
        if let d = dayFmt.date(from: v) { return (d, false) }
        // Ghim quick syntax, e.g. "mai 15h", "t2", "25/12"
        let p = QuickParser.parse(v.split(separator: " ").map { "@" + $0 }.joined(separator: " "), categories: [])
        if let d = p.due, p.title.isEmpty { return (d, p.hasTime) }
        throw ToolError("Không hiểu ngày \"\(s)\". Dùng YYYY-MM-DD hoặc YYYY-MM-DD HH:mm.")
    }

    // MARK: Read tools

    private static func overview(_ d: AppData) -> Any {
        let start = Day.startOfToday
        let open = d.tasks.filter { !$0.done && AppData.inToday($0) }
        let done = d.tasks.filter { $0.done && ($0.completedAt ?? .distantPast) >= start && AppData.inToday($0) }
        let overdue = d.tasks.filter(\.isOverdue)
        let lists: [[String: Any]] = d.categories.map { c in
            var o: [String: Any] = ["name": c.name, "id": short(c.id), "kind": c.kind.rawValue]
            if c.kind == .tasks {
                o["open"] = d.tasks.filter { $0.categoryID == c.id && !$0.done }.count
                let od = d.tasks.filter { $0.categoryID == c.id && $0.isOverdue }.count
                if od > 0 { o["overdue"] = od }
            } else {
                o["notes"] = d.notes.filter { $0.categoryID == c.id }.count
            }
            return o
        }
        return [
            "now": dayTimeFmt.string(from: Date()),
            "today": [
                "progress": "\(done.count)/\(done.count + open.count)",
                "open": sortedTasks(open, d).map { taskDict($0, d) },
                "done": done.map { taskDict($0, d) },
            ],
            "overdue": sortedTasks(overdue, d).map { taskDict($0, d) },
            "lists": lists,
            "streak_days": d.streak,
            "focus_min_today": d.focusLog[Day.key()] ?? 0,
            "completed_today": d.completions[Day.key()] ?? 0,
        ] as [String: Any]
    }

    private static func listTasks(_ d: AppData, _ a: [String: Any]) throws -> Any {
        var ts = d.tasks
        if let l = a["list"] as? String, !l.isEmpty {
            let c = try category(l, d, kind: .tasks)
            ts = ts.filter { $0.categoryID == c.id }
        }
        switch a["status"] as? String ?? "open" {
        case "done": ts = ts.filter(\.done)
        case "all": break
        default: ts = ts.filter { !$0.done }
        }
        if a["today_only"] as? Bool == true { ts = ts.filter { AppData.inToday($0) } }
        if let q = a["query"] as? String { ts = ts.filter { matches($0.title + " " + $0.note, q) } }
        let list = sortedTasks(ts, d)
        var out: [String: Any] = ["count": list.count, "tasks": list.prefix(200).map { taskDict($0, d) }]
        if list.count > 200 { out["truncated"] = true }
        return out
    }

    private static func listNotes(_ d: AppData, _ a: [String: Any]) throws -> Any {
        var ns = d.notes
        if let l = a["list"] as? String, !l.isEmpty {
            let c = try category(l, d, kind: .notes)
            ns = ns.filter { $0.categoryID == c.id }
        }
        if let q = a["query"] as? String { ns = ns.filter { matches($0.text, q) } }
        ns.sort { $0.pinned != $1.pinned ? $0.pinned : $0.createdAt > $1.createdAt }
        return ["count": ns.count, "notes": ns.prefix(100).map { noteDict($0, d) }]
    }

    private static func search(_ d: AppData, _ a: [String: Any]) throws -> Any {
        let q = a["query"] as? String ?? ""
        guard !fold(q).isEmpty else { throw ToolError("query trống.") }
        let ts = sortedTasks(d.tasks.filter { matches($0.title + " " + $0.note, q) }, d)
        let ns = d.notes.filter { matches($0.text, q) }
        return ["tasks": ts.prefix(50).map { taskDict($0, d) }, "notes": ns.prefix(50).map { noteDict($0, d) }]
    }

    // MARK: Write tools

    private static func addTask(_ d: inout AppData, _ a: [String: Any]) throws -> Any {
        let text = (a["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var p = QuickParser.parse(text, categories: d.categories.filter { $0.kind == .tasks })
        if p.title.isEmpty { p.title = text }
        guard !p.title.isEmpty else { throw ToolError("text trống.") }

        let cat: Category
        if let l = a["list"] as? String, !l.isEmpty { cat = try category(l, d, kind: .tasks) }
        else if let id = p.categoryID, let c = d.categories.first(where: { $0.id == id }) { cat = c }
        else if let c = d.categories.first(where: { $0.kind == .tasks }) { cat = c }
        else { throw ToolError("Chưa có danh sách việc nào.") }

        var t = TaskItem(title: p.title, categoryID: cat.id)
        t.priority = p.priority
        t.due = p.due
        t.hasTime = p.hasTime
        t.isToday = p.isToday
        t.repeatRule = p.repeatRule
        t.estimateMin = p.estimateMin
        try apply(a, to: &t, d)
        t.order = (d.tasks.filter { $0.categoryID == t.categoryID }.map(\.order).min() ?? 0) - 1
        d.tasks.append(t)
        return ["added": taskDict(t, d)]
    }

    /// Shared optional fields for add/update.
    private static func apply(_ a: [String: Any], to t: inout TaskItem, _ d: AppData) throws {
        if let s = a["title"] as? String {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { throw ToolError("title trống.") }
            t.title = v
        }
        if let l = a["list"] as? String, !l.isEmpty { t.categoryID = try category(l, d, kind: .tasks).id }
        if let v = a["today"] as? Bool { t.isToday = v }
        if let s = a["due"] as? String {
            let (date, hasTime) = try parseDue(s)
            t.due = date
            t.hasTime = hasTime
            if let date, Calendar.current.isDateInToday(date) { t.isToday = true }
        }
        if let p = try parsePriority(a["priority"]) { t.priority = p }
        if let r = try parseRepeat(a["repeat"]) { t.repeatRule = r }
        if let e = a["estimate_min"] as? Int { t.estimateMin = e > 0 ? e : nil }
        if let n = a["note"] as? String { t.note = n }
    }

    private static func updateTask(_ d: inout AppData, _ a: [String: Any]) throws -> Any {
        let i = try taskIndex(a, d)
        var t = d.tasks[i]
        let oldCat = t.categoryID
        try apply(a, to: &t, d)
        if t.categoryID != oldCat {
            t.order = (d.tasks.filter { $0.categoryID == t.categoryID }.map(\.order).min() ?? 0) - 1
        }
        d.tasks[i] = t
        if let done = a["done"] as? Bool { d.setDone(t.id, done) }
        return ["updated": taskDict(d.tasks[i], d)]
    }

    private static func deleteTask(_ d: inout AppData, _ a: [String: Any]) throws -> Any {
        let i = try taskIndex(a, d)
        let t = d.tasks.remove(at: i)
        return ["deleted": ["id": short(t.id), "title": t.title]]
    }

    private static func addNote(_ d: inout AppData, _ a: [String: Any]) throws -> Any {
        let text = (a["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ToolError("text trống.") }
        let cat: Category
        if let l = a["list"] as? String, !l.isEmpty { cat = try category(l, d, kind: .notes) }
        else if let c = d.categories.first(where: { $0.kind == .notes }) { cat = c }
        else { throw ToolError("Chưa có danh sách ghi chú nào — tạo một tab loại Ghi chú trong Cài đặt.") }
        var n = Note(categoryID: cat.id, text: text)
        n.pinned = a["pinned"] as? Bool ?? false
        d.notes.append(n)
        return ["added": noteDict(n, d)]
    }

    private static func updateNote(_ d: inout AppData, _ a: [String: Any]) throws -> Any {
        let i = try noteIndex(a, d)
        var n = d.notes[i]
        if let s = a["text"] as? String { n.text = s }
        if let s = a["append"] as? String, !s.isEmpty {
            n.text = n.text.isEmpty ? s : n.text + (n.text.hasSuffix("\n") ? "" : "\n") + s
        }
        if let p = a["pinned"] as? Bool { n.pinned = p }
        n.updatedAt = Date()
        d.notes[i] = n
        return ["updated": noteDict(n, d)]
    }

    private static func deleteNote(_ d: inout AppData, _ a: [String: Any]) throws -> Any {
        let i = try noteIndex(a, d)
        let n = d.notes.remove(at: i)
        for img in n.images { try? FileManager.default.removeItem(at: GhimPaths.images.appendingPathComponent(img)) }
        return ["deleted": ["id": short(n.id), "text": String(n.text.prefix(80))]]
    }
}
