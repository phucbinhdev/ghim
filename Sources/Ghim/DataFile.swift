import Foundation

// Shared by the app and the `--mcp` server process: where the data lives,
// how it is read/written, and the pure rules that act on it.

enum GhimPaths {
    static let folder: URL = {
        if let custom = ProcessInfo.processInfo.environment["GHIM_DATA_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true) // used by tests / snapshots
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Ghim", isDirectory: true)
    }()
    static var dataFile: URL { folder.appendingPathComponent("data.json") }
    static var images: URL { folder.appendingPathComponent("images", isDirectory: true) }
    static var lockFile: URL { folder.appendingPathComponent(".lock") }
}

extension Notification.Name {
    /// Posted (distributed) by the MCP process after it wrote data.json. Object = data folder path.
    static let ghimDataChanged = Notification.Name("local.ghim.dataChanged")
    /// Posted by the MCP process before reading, so the app writes pending edits first.
    static let ghimFlush = Notification.Name("local.ghim.flush")
}

enum DataFile {
    /// Cross-process exclusive lock around a read-modify-write of data.json.
    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        let fd = open(GhimPaths.lockFile.path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        return try body()
    }

    static func decode(_ raw: Data) throws -> AppData {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(AppData.self, from: raw)
    }

    static func encode(_ d: AppData) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(d)
    }

    static func write(_ d: AppData) throws {
        try encode(d).write(to: GhimPaths.dataFile, options: .atomic)
    }

    static var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: GhimPaths.dataFile.path))?[.modificationDate] as? Date
    }
}

// MARK: - Rules shared by the UI and the MCP server

extension AppData {
    static func inToday(_ t: TaskItem) -> Bool {
        if t.isToday { return true }
        if let d = t.due, d < Day.endOfToday { return true }
        return false
    }

    var streak: Int {
        let cal = Calendar.current
        var day = Date()
        if (completions[Day.key(day)] ?? 0) == 0 {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var n = 0
        while (completions[Day.key(day)] ?? 0) > 0 {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    /// Marks a task done/undone and keeps the per-day completion count in sync.
    mutating func setDone(_ id: UUID, _ done: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].done != done else { return }
        let key = Day.key()
        if done {
            tasks[i].done = true
            tasks[i].completedAt = Date()
            completions[key, default: 0] += 1
        } else {
            if let c = tasks[i].completedAt, Day.key(c) == key {
                completions[key] = max(0, (completions[key] ?? 1) - 1)
            }
            tasks[i].done = false
            tasks[i].completedAt = nil
        }
    }

    /// New day: re-opens recurring tasks and clears yesterday's finished "today" flags.
    /// Returns false when nothing needed to change.
    @discardableResult
    mutating func rollover() -> Bool {
        let today = Day.key()
        guard lastDay != today else { return false }
        let now = Date()
        let start = Day.startOfToday
        for i in tasks.indices {
            var t = tasks[i]
            let applies = t.repeatRule.applies(on: now, anchor: t.createdAt, lastDone: t.completedAt)
            if t.done, let c = t.completedAt, c < start {
                if applies {
                    t.done = false
                    t.completedAt = nil
                    t.isToday = true
                } else if t.isToday {
                    t.isToday = false
                }
            } else if !t.done && applies {
                t.isToday = true
            }
            tasks[i] = t
        }
        lastDay = today
        return true
    }
}
