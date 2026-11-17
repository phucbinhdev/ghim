import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel: it can take keyboard focus for typing
/// without stealing activation from the app you are working in.
final class EdgePanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Hosting view that reports hover even when the app is not active
/// and lets the first click act immediately.
final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onHover?(true) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum TabMetrics {
    static let stripWidth: CGFloat = 30
    static let restWidth: CGFloat = 25
    static let spacing: CGFloat = 3
    static let gripHeight: CGFloat = 20
    static let todayHeight: CGFloat = 62
    static let focusHeight: CGFloat = 50
    static let font = NSFont.systemFont(ofSize: 12, weight: .semibold)

    static func textWidth(_ s: String) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }
    static func height(_ c: Category) -> CGFloat {
        max(58, textWidth(c.name) + (c.kind == .tasks ? 40 : 22))
    }
    static func stripHeight(_ cats: [Category], focus: Bool) -> CGFloat {
        var h = gripHeight + spacing + todayHeight
        if focus { h += spacing + focusHeight }
        for c in cats { h += spacing + height(c) }
        return h
    }
}

@MainActor
final class PanelController: NSObject, ObservableObject {
    static let shared = PanelController()

    enum Tab: Hashable { case today, category(UUID) }

    @Published var expanded = false
    @Published var showContent = false
    @Published var selection: Tab = .today
    @Published var pinned = false
    @Published var hovering = false
    @Published var stripOffset: CGFloat = 0
    /// effective width of the content panel (custom size or large mode)
    @Published var contentWidth: CGFloat = 350
    @Published var resizing = false
    @Published var searching = false
    @Published var searchText = ""
    /// bump to ask the visible "add" field to take focus
    @Published var focusRequest = 0
    @Published private(set) var isHidden = false
    /// note whose text view should grab focus (new notes)
    @Published var focusNoteID: UUID?
    /// note currently being edited
    @Published var activeNoteID: UUID?

    private(set) var panel: EdgePanel!
    private var bag = Set<AnyCancellable>()
    private var mouseMonitor: Any?
    private var hoverWork: DispatchWorkItem?
    private var openedByHover = false
    private var dragStart: (mouseY: CGFloat, fraction: Double)?
    private var resizeStart: (mouse: NSPoint, w: CGFloat, h: CGFloat)?

    static let minSize = NSSize(width: 280, height: 300)

    private var store: Store { .shared }
    private var prefs: Prefs { .shared }

    // MARK: Setup

    func setup() {
        let p = EdgePanel(contentRect: NSRect(x: 0, y: 0, width: 30, height: 300),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovable = false
        p.becomesKeyOnlyIfNeeded = false
        p.isReleasedWhenClosed = false
        p.onCancel = { [weak self] in
            guard let self else { return }
            if self.searching { self.searching = false; self.searchText = "" } else { self.collapse() }
        }

        let root = RootView()
            .environmentObject(store)
            .environmentObject(self)
            .environmentObject(prefs)
            .environmentObject(FocusTimer.shared)
        let host = HoverHostingView(rootView: root)
        host.sizingOptions = []
        host.onHover = { [weak self] inside in self?.setHover(inside) }
        p.contentView = host
        panel = p

        layout()
        p.alphaValue = CGFloat(prefs.idleOpacity)
        p.orderFrontRegardless()

        // Re-layout when anything that affects geometry changes.
        prefs.objectWillChange
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.layout(); self?.updateAlpha() }
            .store(in: &bag)
        store.$data
            .map { $0.categories.map { "\($0.id)\($0.name)\($0.kind.rawValue)" }.joined() }
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.validateSelection(); self?.layout() } }
            .store(in: &bag)
        FocusTimer.shared.$active
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.layout() } }
            .store(in: &bag)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }

        // ⌘V of an image when no note text view has focus.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, e.charactersIgnoringModifiers?.lowercased() == "v" else { return e }
            if e.window?.firstResponder is ImageAwareTextView { return e }
            if e.window === self.panel, self.pasteImagesFromClipboard() { return nil }
            if let qc = QuickCapture.shared.panel, e.window === qc, QuickCapture.shared.pasteImages() { return nil }
            return e
        }

        // Clicking anywhere in another app collapses the panel (unless pinned).
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.outsideClick() }
        }
    }

    private func validateSelection() {
        if case .category(let id) = selection, store.category(id) == nil { selection = .today }
    }

    // MARK: Geometry

    var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    func layout() {
        guard let panel else { return }
        let vf = screen.visibleFrame
        let sh = TabMetrics.stripHeight(store.data.categories, focus: FocusTimer.shared.active)
        let sw = TabMetrics.stripWidth

        let center = vf.minY + vf.height * CGFloat(prefs.verticalFraction)
        var stripTop = center + sh / 2
        stripTop = min(stripTop, vf.maxY)
        stripTop = max(stripTop, vf.minY + min(sh, vf.height))

        let size = panelSize(in: vf)
        if abs(size.width - contentWidth) > 0.5 { contentWidth = size.width }

        var w = sw, h = sh, top = stripTop
        if expanded {
            w = sw + size.width
            h = min(max(size.height, sh), vf.height)
            if prefs.largeMode { top = vf.maxY }
            if top - h < vf.minY { top = vf.minY + h }
            top = min(top, vf.maxY)
        }
        let offset = max(0, top - stripTop)
        if abs(offset - stripOffset) > 0.5 { stripOffset = offset }
        let x = prefs.edgeRight ? vf.maxX - w : vf.minX
        let frame = NSRect(x: x, y: top - h, width: w, height: h).integral
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    /// Content panel size for the current mode, clamped to the screen.
    func panelSize(in vf: NSRect) -> NSSize {
        let maxW = max(Self.minSize.width, vf.width * 0.75 - TabMetrics.stripWidth)
        var w = CGFloat(prefs.panelWidth), h = CGFloat(prefs.panelHeight)
        if prefs.largeMode {
            w = max(w, min(680, vf.width * 0.45))
            h = vf.height
        }
        return NSSize(width: min(max(w, Self.minSize.width), maxW),
                      height: min(max(h, Self.minSize.height), vf.height))
    }

    // MARK: Resizing by dragging the panel edges

    enum ResizeEdge { case side, bottom, corner }

    func resizeChanged(_ edge: ResizeEdge) {
        let m = NSEvent.mouseLocation
        let vf = screen.visibleFrame
        if resizeStart == nil {
            let cur = panelSize(in: vf)
            // leaving large mode: continue from what is on screen
            if prefs.largeMode {
                prefs.panelWidth = Double(cur.width)
                prefs.panelHeight = Double(cur.height)
                prefs.largeMode = false
            }
            resizeStart = (m, cur.width, cur.height)
            resizing = true
        }
        guard let s = resizeStart else { return }
        if edge != .bottom {
            let dx = prefs.edgeRight ? s.mouse.x - m.x : m.x - s.mouse.x
            prefs.panelWidth = Double(max(Self.minSize.width, s.w + dx))
        }
        if edge != .side {
            prefs.panelHeight = Double(max(Self.minSize.height, s.h + (s.mouse.y - m.y)))
        }
        layout()
    }

    func resizeEnded() {
        // store the clamped values so the next drag starts from what is visible
        let cur = panelSize(in: screen.visibleFrame)
        prefs.panelWidth = Double(cur.width)
        prefs.panelHeight = Double(cur.height)
        resizeStart = nil
        resizing = false
    }

    func toggleLarge() {
        withAnimation(.snappy) { prefs.largeMode.toggle() }
        layout()
    }

    // MARK: Expand / collapse

    func expand(_ tab: Tab? = nil, focusInput: Bool = false) {
        if isHidden { show() }
        if let tab { selection = tab }
        if !expanded {
            expanded = true
            layout()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { showContent = true }
        }
        panel.makeKey()
        updateAlpha()
        if focusInput { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.focusRequest += 1 } }
    }

    func collapse() {
        guard expanded else { return }
        openedByHover = false
        searching = false
        searchText = ""
        withAnimation(.easeIn(duration: 0.15)) { showContent = false }
        store.cleanEmptyNotes()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, !self.showContent else { return }
            self.expanded = false
            self.layout()
            // hand keyboard focus back to whatever app the user was in
            if self.panel.isKeyWindow {
                self.panel.orderOut(nil)
                self.panel.orderFrontRegardless()
            }
            self.updateAlpha()
        }
    }

    func toggle() { expanded ? collapse() : expand(focusInput: true) }

    func select(_ tab: Tab) {
        openedByHover = false
        if expanded && selection == tab { collapse() } else { expand(tab) }
    }

    func show() {
        isHidden = false
        panel.orderFrontRegardless()
        layout()
    }

    func hide() {
        collapse()
        isHidden = true
        panel.orderOut(nil)
    }

    private func outsideClick() {
        guard expanded, !pinned, prefs.autoCollapse else { return }
        // Ignore clicks that land on our own panel (global monitor shouldn't see them, but be safe).
        if panel.frame.contains(NSEvent.mouseLocation) { return }
        // The button may still be held: the user could be dragging an image from Finder/Safari towards us.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in self?.collapseAfterMouseUp() }
    }

    private func collapseAfterMouseUp() {
        guard expanded, !pinned else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.collapseAfterMouseUp() }
            return
        }
        // released over the panel → it was a drop onto us, stay open
        if panel.frame.contains(NSEvent.mouseLocation) { return }
        collapse()
    }

    // MARK: Pasting images

    /// ⌘V with an image on the clipboard while no note is being edited:
    /// attach it to the active note or create a new note in the current (or first) notes tab.
    func pasteImagesFromClipboard(_ pb: NSPasteboard = .general) -> Bool {
        guard expanded else { return false }
        let payloads = ImagePasteboard.payloads(from: pb)
        guard !payloads.isEmpty else { return false }
        var target: UUID?
        var note: UUID?
        if case .category(let id) = selection, store.category(id)?.kind == .notes {
            target = id
            note = activeNoteID
        } else {
            target = store.data.categories.first { $0.kind == .notes }?.id
        }
        guard let target else { return false }
        withAnimation(.snappy) {
            _ = store.attachImages(payloads, to: note, category: target)
            selection = .category(target)
        }
        Sound.play("Pop")
        return true
    }

    // MARK: Hover & opacity

    private func setHover(_ inside: Bool) {
        hovering = inside
        updateAlpha()
        hoverWork?.cancel()
        if inside {
            if prefs.hoverToOpen && !expanded {
                let w = DispatchWorkItem { [weak self] in
                    guard let self, self.hovering, !self.expanded else { return }
                    self.openedByHover = true
                    self.expand()
                }
                hoverWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
            }
        } else if openedByHover && expanded && !pinned {
            let w = DispatchWorkItem { [weak self] in
                guard let self, !self.hovering, self.openedByHover else { return }
                self.collapse()
            }
            hoverWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: w)
        }
    }

    /// Any click inside the panel means the user is working in it: stop hover auto-close.
    func userInteracted() { openedByHover = false }

    func updateAlpha() {
        guard let panel else { return }
        let target: CGFloat = (expanded || hovering || dragStart != nil) ? 1 : CGFloat(prefs.idleOpacity)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = target
        }
    }

    // MARK: Dragging the strip along the edge

    func dragChanged() {
        let y = NSEvent.mouseLocation.y
        if dragStart == nil {
            dragStart = (y, prefs.verticalFraction)
            updateAlpha()
        }
        guard let s = dragStart else { return }
        let vf = screen.visibleFrame
        let f = s.fraction + Double((y - s.mouseY) / vf.height)
        prefs.verticalFraction = min(1, max(0, f))
        layout()
    }

    func dragEnded() {
        dragStart = nil
        updateAlpha()
    }

    // MARK: Search

    func toggleSearch() {
        searching.toggle()
        if !searching { searchText = "" }
    }
}
