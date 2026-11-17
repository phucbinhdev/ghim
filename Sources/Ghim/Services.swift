import AppKit
import Carbon
import UserNotifications

// MARK: - Focus (pomodoro) timer

@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    @Published private(set) var taskID: UUID?
    @Published private(set) var isBreak = false
    @Published private(set) var active = false
    @Published private(set) var running = false
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval = 0

    private var timer: Timer?
    private var lastTick = Date()
    private var focusedSeconds: TimeInterval = 0

    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    var remainingString: String {
        let s = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var minutesLeft: Int { max(0, Int((remaining / 60).rounded(.up))) }

    func start(task: UUID?, minutes: Int? = nil) {
        commitFocus()
        taskID = task
        isBreak = false
        total = TimeInterval((minutes ?? Prefs.shared.focusMinutes) * 60)
        remaining = total
        begin()
    }

    func startBreak() {
        commitFocus()
        isBreak = true
        total = TimeInterval(Prefs.shared.breakMinutes * 60)
        remaining = total
        begin()
    }

    private func begin() {
        active = true
        running = true
        lastTick = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func togglePause() {
        running.toggle()
        lastTick = Date()
    }

    func addMinutes(_ m: Int) {
        remaining += TimeInterval(m * 60)
        total += TimeInterval(m * 60)
    }

    func stop() {
        commitFocus()
        timer?.invalidate()
        timer = nil
        active = false
        running = false
        isBreak = false
        taskID = nil
        remaining = 0
        total = 0
    }

    /// Book the focused minutes so far into stats.
    private func commitFocus() {
        if !isBreak {
            let minutes = Int(focusedSeconds / 60)
            if minutes > 0 { Store.shared.addFocus(task: taskID, minutes: minutes) }
        }
        focusedSeconds = 0
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard running else { return }
        remaining -= dt
        if !isBreak { focusedSeconds += dt }
        if remaining <= 0 { finish() }
    }

    private func finish() {
        if isBreak {
            Notifier.send(title: "Hết giờ nghỉ ☕️", body: "Sẵn sàng cho phiên tiếp theo chưa?")
            Sound.play("Glass")
            stop()
        } else {
            focusedSeconds = total // credit the full session
            let title = taskID.flatMap { id in Store.shared.data.tasks.first { $0.id == id }?.title } ?? "Phiên tập trung"
            Notifier.send(title: "Xong \(Int(total / 60)) phút tập trung 🎯", body: title)
            Sound.play("Glass")
            if Prefs.shared.autoBreak && Prefs.shared.breakMinutes > 0 {
                startBreak()
            } else {
                stop()
            }
        }
    }
}

// MARK: - Sounds

enum Sound {
    @MainActor static func play(_ name: String) {
        guard Prefs.shared.sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

// MARK: - Notifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { PanelController.shared.expand(.today) }
        }
        completionHandler()
    }
}

enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    static func setup() {
        guard available else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = NotificationDelegate.shared
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func send(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Schedules a reminder for every open task with a time in the next 7 days.
    static func reschedule(tasks: [TaskItem]) {
        guard available else { return }
        let c = UNUserNotificationCenter.current()
        let now = Date()
        let horizon = now.addingTimeInterval(7 * 86400)
        let upcoming = tasks.filter { !$0.done && $0.hasTime && ($0.due ?? .distantPast) > now && ($0.due ?? .distantFuture) < horizon }
            .sorted { $0.due! < $1.due! }
            .prefix(50)
        c.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix("task-") }
            c.removePendingNotificationRequests(withIdentifiers: old)
            for t in upcoming {
                let content = UNMutableNotificationContent()
                content.title = "⏰ " + t.title
                content.body = "Đến hạn lúc " + Day.timeFormatter.string(from: t.due!)
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: t.due!)
                let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                c.add(UNNotificationRequest(identifier: "task-\(t.id.uuidString)", content: content, trigger: trig))
            }
        }
    }
}

// MARK: - Global hotkeys (Carbon, no Accessibility permission needed)

final class HotKeys {
    static let shared = HotKeys()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false

    @discardableResult
    func register(keyCode: Int, modifiers: Int, _ handler: @escaping () -> Void) -> Bool {
        install()
        let hkID = EventHotKeyID(signature: OSType(0x4748_494D), id: nextID) // 'GHIM'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        handlers[nextID] = handler
        refs.append(ref)
        nextID += 1
        return true
    }

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKeys.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
