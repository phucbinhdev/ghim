import Foundation

// MARK: - Category (one coloured tab on the edge)

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case tasks, notes
    var id: String { rawValue }
    var label: String { self == .tasks ? "Danh sách việc" : "Ghi chú" }
}

struct Category: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String
    var kind: CategoryKind = .tasks
}

// MARK: - Task

enum Priority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case none = 0, low, medium, high
    var id: Int { rawValue }
    static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    var marks: String { String(repeating: "!", count: rawValue) }
    var label: String {
        switch self {
        case .none: return "Không"
        case .low: return "Thấp"
        case .medium: return "Vừa"
        case .high: return "Cao"
        }
    }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Không lặp"
        case .daily: return "Mỗi ngày"
        case .weekdays: return "Ngày thường (T2–T6)"
        case .weekly: return "Mỗi tuần"
        }
    }
    var short: String {
        switch self {
        case .none: return ""
        case .daily: return "hằng ngày"
        case .weekdays: return "T2–T6"
        case .weekly: return "hằng tuần"
        }
    }

    /// Whether a recurring task should come back (re-open) on `date`.
    func applies(on date: Date, anchor: Date, lastDone: Date?) -> Bool {
        let cal = Calendar.current
        switch self {
        case .none: return false
        case .daily: return true
        case .weekdays:
            let wd = cal.component(.weekday, from: date)
            return wd != 1 && wd != 7
        case .weekly:
            if cal.component(.weekday, from: date) == cal.component(.weekday, from: anchor) { return true }
            if let l = lastDone,
               let days = cal.dateComponents([.day], from: cal.startOfDay(for: l), to: cal.startOfDay(for: date)).day,
               days >= 7 { return true }
            return false
        }
    }
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var categoryID: UUID
    var done = false
    var createdAt = Date()
    var completedAt: Date?
    var due: Date?
    var hasTime = false
    var priority: Priority = .none
    var isToday = false
    var repeatRule: RepeatRule = .none
    var estimateMin: Int?
    var focusedMin = 0
    var note = ""
    var order: Double = 0

    init(title: String, categoryID: UUID) {
        self.title = title
        self.categoryID = categoryID
    }

    enum CodingKeys: String, CodingKey {
        case id, title, categoryID, done, createdAt, completedAt, due, hasTime, priority
        case isToday, repeatRule, estimateMin, focusedMin, note, order
    }

    // Tolerant decoding so future fields never wipe user data.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        categoryID = try c.decode(UUID.self, forKey: .categoryID)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        hasTime = try c.decodeIfPresent(Bool.self, forKey: .hasTime) ?? false
        priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? Priority.none
        isToday = try c.decodeIfPresent(Bool.self, forKey: .isToday) ?? false
        repeatRule = (try? c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)) ?? RepeatRule.none
        estimateMin = try c.decodeIfPresent(Int.self, forKey: .estimateMin)
        focusedMin = try c.decodeIfPresent(Int.self, forKey: .focusedMin) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
    }

    var isOverdue: Bool {
        guard !done, let d = due else { return false }
        return hasTime ? d < Date() : d < Day.startOfToday
    }
}

// MARK: - Note

struct Note: Identifiable, Codable, Hashable {
    var id = UUID()
    var categoryID: UUID
    var text = ""
    var pinned = false
    var createdAt = Date()
    var updatedAt = Date()
    /// file names inside Application Support/Ghim/images
    var images: [String] = []

    init(categoryID: UUID, text: String = "") {
        self.categoryID = categoryID
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case id, categoryID, text, pinned, createdAt, updatedAt, images }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        categoryID = try c.decode(UUID.self, forKey: .categoryID)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
    }

    var isEmpty: Bool { images.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - Whole document

struct AppData: Codable {
    var categories: [Category]
    var tasks: [TaskItem] = []
    var notes: [Note] = []
    var lastDay: String = ""
    /// completions per day key (yyyy-MM-dd) — powers streaks
    var completions: [String: Int] = [:]
    /// focus minutes per day key
    var focusLog: [String: Int] = [:]

    init(categories: [Category], tasks: [TaskItem] = [], notes: [Note] = []) {
        self.categories = categories
        self.tasks = tasks
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey { case categories, tasks, notes, lastDay, completions, focusLog }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        lastDay = try c.decodeIfPresent(String.self, forKey: .lastDay) ?? ""
        completions = try c.decodeIfPresent([String: Int].self, forKey: .completions) ?? [:]
        focusLog = try c.decodeIfPresent([String: Int].self, forKey: .focusLog) ?? [:]
    }

    static func seed() -> AppData {
        let todo = Category(name: "To-Do", colorHex: "#F26B3A")
        let ideas = Category(name: "Ideas", colorHex: "#F6B92B")
        let family = Category(name: "Family", colorHex: "#EE8CC6")
        let goals = Category(name: "Goals", colorHex: "#5C7FD9")
        let notes = Category(name: "Notes", colorHex: "#4F7D5C", kind: .notes)

        func t(_ title: String, _ cat: Category, today: Bool = false, prio: Priority = .none, order: Double) -> TaskItem {
            var x = TaskItem(title: title, categoryID: cat.id)
            x.isToday = today
            x.priority = prio
            x.order = order
            return x
        }
        var tasks = [
            t("Chào mừng đến Ghim 👋 — tick vòng tròn để hoàn thành", todo, today: true, order: 0),
            t("Gõ nhanh: Gọi mẹ #family @mai !!  → tự xếp tab, hạn, ưu tiên", todo, today: true, prio: .medium, order: 1),
            t("Rê chuột vào một việc rồi bấm ▶ để tập trung 25 phút", todo, today: true, order: 2),
            t("Kéo tay nắm ở đầu dải tab để đổi vị trí trên cạnh màn hình", todo, order: 3),
            t("⌃⌥Space mở/đóng dải tab · ⌃⌥N ghi nhanh từ bất cứ đâu", todo, order: 4),
            t("Đọc 12 cuốn sách trong năm", goals, order: 0),
            t("Cuối tuần đi ăn cùng gia đình", family, order: 0),
            t("App ghi chú ghim cạnh màn hình 😄", ideas, order: 0),
        ]
        var review = TaskItem(title: "Xem lại kế hoạch tuần", categoryID: todo.id)
        review.repeatRule = .weekly
        review.order = 5
        tasks.append(review)

        let note = Note(categoryID: notes.id,
                        text: "Ghi chú dán nhanh ở đây ✍️\nMẹo: rê chuột vào thẻ và bấm ☑︎ để biến dòng đầu tiên thành một việc.")
        var d = AppData(categories: [todo, ideas, family, goals, notes], tasks: tasks, notes: [note])
        d.lastDay = Day.key()
        return d
    }
}

// MARK: - Day helpers

enum Day {
    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ d: Date = Date()) -> String { keyFormatter.string(from: d) }
    static var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    static var endOfToday: Date { Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)! }

    static let weekdayShort = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EEEE, d 'tháng' M"
        return f
    }()

    static func dueLabel(_ t: TaskItem) -> String {
        guard let d = t.due else { return "" }
        return dueLabel(due: d, hasTime: t.hasTime)
    }

    static func dueLabel(due d: Date, hasTime: Bool) -> String {
        let cal = Calendar.current
        var s: String
        if cal.isDateInToday(d) { s = "Hôm nay" }
        else if cal.isDateInTomorrow(d) { s = "Mai" }
        else if cal.isDateInYesterday(d) { s = "Hôm qua" }
        else {
            let wd = weekdayShort[cal.component(.weekday, from: d) - 1]
            s = "\(wd) \(cal.component(.day, from: d))/\(cal.component(.month, from: d))"
        }
        if hasTime { s += " " + timeFormatter.string(from: d) }
        return s
    }

    static func nextMonday() -> Date {
        let cal = Calendar.current
        var d = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        while cal.component(.weekday, from: d) != 2 { d = cal.date(byAdding: .day, value: 1, to: d)! }
        return d
    }
}
