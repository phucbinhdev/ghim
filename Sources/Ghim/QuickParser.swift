import Foundation

/// Result of parsing a quick-capture line such as
/// "Gọi mẹ #family @mai @9h !! ~15m /weekly"
struct ParsedTask {
    var title = ""
    var categoryID: UUID?
    var priority: Priority = .none
    var due: Date?
    var hasTime = false
    var isToday = false
    var repeatRule: RepeatRule = .none
    var estimateMin: Int?

    var hasMeta: Bool {
        categoryID != nil || priority != .none || due != nil || isToday || repeatRule != .none || estimateMin != nil
    }
}

enum QuickParser {
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func parse(_ text: String, categories: [Category]) -> ParsedTask {
        var p = ParsedTask()
        var words: [String] = []
        var day: Date?
        var time: (Int, Int)?
        let cal = Calendar.current

        for raw in text.split(separator: " ", omittingEmptySubsequences: true) {
            let w = String(raw)
            let lw = fold(w)

            if w.hasPrefix("#"), w.count > 1 {
                let q = String(lw.dropFirst())
                if let c = categories.first(where: { fold($0.name) == q }) ?? categories.first(where: { fold($0.name).hasPrefix(q) }) {
                    p.categoryID = c.id
                    continue
                }
            }
            if (1...3).contains(w.count), w.allSatisfy({ $0 == "!" }) {
                p.priority = Priority(rawValue: w.count) ?? .none
                continue
            }
            if w == "*" { p.isToday = true; continue }
            if lw.hasPrefix("@"), lw.count > 1 {
                let v = String(lw.dropFirst())
                if let t = parseTime(v) { time = t; continue }
                if let d = parseDay(v) { day = d; continue }
            }
            if lw.hasPrefix("~"), let m = parseDuration(String(lw.dropFirst())) {
                p.estimateMin = m
                continue
            }
            if lw.hasPrefix("/") {
                switch String(lw.dropFirst()) {
                case "daily", "hangngay", "moingay", "everyday": p.repeatRule = .daily; continue
                case "weekdays", "ngaythuong", "t2t6": p.repeatRule = .weekdays; continue
                case "weekly", "hangtuan", "moituan": p.repeatRule = .weekly; continue
                default: break
                }
            }
            words.append(w)
        }

        if let time {
            let base = day ?? Day.startOfToday
            p.due = cal.date(bySettingHour: time.0, minute: time.1, second: 0, of: base)
            p.hasTime = true
        } else if let day {
            p.due = day
        }
        if let d = p.due, cal.isDateInToday(d) { p.isToday = true }
        p.title = words.joined(separator: " ")
        return p
    }

    static func parseDay(_ v: String) -> Date? {
        let cal = Calendar.current
        let today = Day.startOfToday
        switch v {
        case "today", "nay", "homnay", "hn", "td": return today
        case "tomorrow", "mai", "ngaymai", "tmr", "tm": return cal.date(byAdding: .day, value: 1, to: today)
        case "kia", "ngaykia": return cal.date(byAdding: .day, value: 2, to: today)
        case "tuansau", "nextweek", "nw": return Day.nextMonday()
        default: break
        }
        // weekdays: mon..sun / t2..t7 / cn
        let map: [String: Int] = ["sun": 1, "cn": 1, "mon": 2, "t2": 2, "tue": 3, "t3": 3, "wed": 4, "t4": 4,
                                  "thu": 5, "t5": 5, "fri": 6, "t6": 6, "sat": 7, "t7": 7]
        if let wd = map[v] {
            var d = cal.date(byAdding: .day, value: 1, to: today)!
            while cal.component(.weekday, from: d) != wd { d = cal.date(byAdding: .day, value: 1, to: d)! }
            return d
        }
        // +3 → in 3 days
        if v.hasPrefix("+"), let n = Int(v.dropFirst().filter(\.isNumber)), n < 1000 {
            return cal.date(byAdding: .day, value: n, to: today)
        }
        // dd/mm or dd/mm/yyyy
        let parts = v.split(separator: "/").compactMap { Int($0) }
        if parts.count >= 2, (1...31).contains(parts[0]), (1...12).contains(parts[1]) {
            var comps = cal.dateComponents([.year], from: today)
            comps.day = parts[0]
            comps.month = parts[1]
            if parts.count >= 3 { comps.year = parts[2] < 100 ? 2000 + parts[2] : parts[2] }
            if var d = cal.date(from: comps) {
                if parts.count < 3, d < today { d = cal.date(byAdding: .year, value: 1, to: d)! }
                return d
            }
        }
        return nil
    }

    /// 15:30, 15h, 15h30, 9am, 3pm
    static func parseTime(_ v: String) -> (Int, Int)? {
        var s = v
        var pm = false, am = false
        if s.hasSuffix("pm") { pm = true; s.removeLast(2) } else if s.hasSuffix("am") { am = true; s.removeLast(2) }
        var h: Int?, m = 0
        if s.contains(":") {
            let p = s.split(separator: ":")
            guard p.count == 2, let hh = Int(p[0]), let mm = Int(p[1]) else { return nil }
            h = hh; m = mm
        } else if s.contains("h") {
            let p = s.split(separator: "h", omittingEmptySubsequences: false)
            guard let hh = Int(p[0]) else { return nil }
            h = hh
            if p.count > 1, !p[1].isEmpty { guard let mm = Int(p[1]) else { return nil }; m = mm }
        } else if am || pm, let hh = Int(s) {
            h = hh
        }
        guard var hour = h, (0...59).contains(m) else { return nil }
        if pm && hour < 12 { hour += 12 }
        if am && hour == 12 { hour = 0 }
        guard (0...23).contains(hour) else { return nil }
        return (hour, m)
    }

    /// 25m, 1h, 1h30, 90
    static func parseDuration(_ v: String) -> Int? {
        if let n = Int(v) { return n }
        if v.hasSuffix("m"), let n = Int(v.dropLast()) { return n }
        if v.hasSuffix("p"), let n = Int(v.dropLast()) { return n }
        if v.contains("h") {
            let p = v.split(separator: "h", omittingEmptySubsequences: false)
            guard let h = Int(p[0]) else { return nil }
            var m = 0
            if p.count > 1, !p[1].isEmpty { guard let mm = Int(p[1].filter(\.isNumber)) else { return nil }; m = mm }
            return h * 60 + m
        }
        return nil
    }
}
