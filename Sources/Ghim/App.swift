import AppKit
import Combine
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var bag = Set<AnyCancellable>()
    private var minuteTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = Store.shared
        Store.shared.observeExternalChanges()

        installEditMenu()
        PanelController.shared.setup()
        setupStatusItem()
        setupHotKeys()
        Notifier.setup()
        Notifier.reschedule(tasks: Store.shared.data.tasks)

        let t = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { Store.shared.rollover() }
        }
        RunLoop.main.add(t, forMode: .common)
        minuteTimer = t
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Store.shared.rollover() }
        }

        // Dev aid: `Ghim --snapshot <dir>` renders the panel states to PNGs and quits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            runSnapshots(to: URL(fileURLWithPath: args[i + 1]))
            return
        }

        if !Prefs.shared.didOnboard {
            Prefs.shared.didOnboard = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                PanelController.shared.pinned = true
                PanelController.shared.expand(.today)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.saveNow()
    }

    /// Accessory apps have no visible menu bar, but the main menu still provides
    /// the standard ⌘X/⌘C/⌘V/⌘A/⌘Z key equivalents to text fields.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Thoát Ghim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            let img = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Ghim")
            img?.isTemplate = true
            b.image = img
            b.imagePosition = .imageLeading
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Store.shared.$data
            .combineLatest(Prefs.shared.$menuBarCount)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _, show in self?.updateStatusTitle(show) }
            .store(in: &bag)
    }

    private func updateStatusTitle(_ show: Bool) {
        let p = Store.shared.todayProgress
        statusItem.button?.title = (show && p.total > 0) ? " \(p.done)/\(p.total)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pc = PanelController.shared
        let p = Store.shared.todayProgress
        let header = NSMenuItem(title: "Hôm nay: \(p.done)/\(p.total) việc · 🔥 \(Store.shared.streak) ngày", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item(pc.expanded ? "Thu gọn panel" : "Mở panel", #selector(togglePanel), "⌃⌥Space"))
        menu.addItem(item("Ghi nhanh…", #selector(quickCapture), "⌃⌥N"))
        menu.addItem(item(pc.isHidden ? "Hiện dải tab" : "Ẩn dải tab", #selector(toggleHidden)))
        menu.addItem(item(Prefs.shared.edgeRight ? "Chuyển sang cạnh trái" : "Chuyển sang cạnh phải", #selector(switchEdge)))
        menu.addItem(.separator())
        menu.addItem(item("Sao chép tất cả dạng Markdown", #selector(exportMD)))
        menu.addItem(item("Cài đặt…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Thoát Ghim", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector, _ hint: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: hint.map { "\(title)    \($0)" } ?? title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func togglePanel() { PanelController.shared.toggle() }
    @objc private func quickCapture() { QuickCapture.shared.show() }
    @objc private func toggleHidden() {
        let pc = PanelController.shared
        pc.isHidden ? pc.show() : pc.hide()
    }
    @objc private func switchEdge() { Prefs.shared.edgeRight.toggle() }
    @objc private func exportMD() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Store.shared.exportMarkdown(), forType: .string)
    }
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Snapshots (testing)

    private func runSnapshots(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pc = PanelController.shared
        var steps: [(String, () -> Void)] = [("collapsed", { pc.collapse() }), ("today", { pc.expand(.today) })]
        for c in Store.shared.data.categories {
            steps.append((c.name, { pc.expand(.category(c.id)) }))
        }
        if let notes = Store.shared.data.categories.first(where: { $0.kind == .notes }) {
            steps.append(("paste-image", {
                pc.expand(.category(notes.id))
                // simulate ⌘V of a screenshot, using a private pasteboard so the user's clipboard is untouched
                let pb = NSPasteboard(name: NSPasteboard.Name("ghim.snapshot"))
                pb.clearContents()
                let img = NSImage(size: NSSize(width: 640, height: 360), flipped: false) { r in
                    NSGradient(colors: [.systemPink, .systemOrange])!.draw(in: r, angle: 30)
                    ("Ảnh dán ⌘V" as NSString).draw(at: NSPoint(x: 40, y: 150),
                        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 56), .foregroundColor: NSColor.white])
                    return true
                }
                pb.writeObjects([img])
                _ = pc.pasteImagesFromClipboard(pb)
            }))
        }
        steps.append(("large", { pc.expand(.today); pc.toggleLarge() }))
        steps.append(("normal-again", { pc.toggleLarge() }))
        steps.append(("focus", { FocusTimer.shared.start(task: Store.shared.todayOpen.first?.id); pc.expand(.today) }))
        steps.append(("quick", { QuickCapture.shared.show() }))
        func run(_ i: Int) {
            guard i < steps.count else { FocusTimer.shared.stop(); NSApp.terminate(nil); return }
            steps[i].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                let win: NSWindow? = steps[i].0 == "quick" ? NSApp.windows.last { $0 !== pc.panel && $0.isVisible } : pc.panel
                if let v = win?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(i)-\(steps[i].0).png"))
                }
                run(i + 1)
            }
        }
        run(0)
    }

    // MARK: Hotkeys

    private func setupHotKeys() {
        let mods = controlKey | optionKey
        HotKeys.shared.register(keyCode: kVK_Space, modifiers: mods) {
            MainActor.assumeIsolated { PanelController.shared.toggle() }
        }
        HotKeys.shared.register(keyCode: kVK_ANSI_N, modifiers: mods) {
            MainActor.assumeIsolated { QuickCapture.shared.show() }
        }
        HotKeys.shared.register(keyCode: kVK_ANSI_T, modifiers: mods) {
            MainActor.assumeIsolated { PanelController.shared.expand(.today, focusInput: true) }
        }
    }
}
