import Foundation
import SwiftUI

@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var edgeRight: Bool { didSet { d.set(edgeRight, forKey: "edgeRight") } }
    /// Opacity of the tab strip when idle (mouse away, collapsed)
    @Published var idleOpacity: Double { didSet { d.set(idleOpacity, forKey: "idleOpacity") } }
    /// Vertical centre of the strip, 0 = bottom … 1 = top of the screen
    @Published var verticalFraction: Double { didSet { d.set(verticalFraction, forKey: "verticalFraction") } }
    @Published var hoverToOpen: Bool { didSet { d.set(hoverToOpen, forKey: "hoverToOpen") } }
    @Published var autoCollapse: Bool { didSet { d.set(autoCollapse, forKey: "autoCollapse") } }
    @Published var panelWidth: Double { didSet { d.set(panelWidth, forKey: "panelWidth") } }
    @Published var panelHeight: Double { didSet { d.set(panelHeight, forKey: "panelHeight") } }
    @Published var focusMinutes: Int { didSet { d.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var breakMinutes: Int { didSet { d.set(breakMinutes, forKey: "breakMinutes") } }
    @Published var autoBreak: Bool { didSet { d.set(autoBreak, forKey: "autoBreak") } }
    @Published var showCompleted: Bool { didSet { d.set(showCompleted, forKey: "showCompleted") } }
    @Published var sounds: Bool { didSet { d.set(sounds, forKey: "sounds") } }
    @Published var menuBarCount: Bool { didSet { d.set(menuBarCount, forKey: "menuBarCount") } }
    @Published var didOnboard: Bool { didSet { d.set(didOnboard, forKey: "didOnboard") } }
    /// "Phóng to": wide panel using the full screen height
    @Published var largeMode: Bool { didSet { d.set(largeMode, forKey: "largeMode") } }

    init() {
        d.register(defaults: [
            "edgeRight": true,
            "idleOpacity": 0.45,
            "verticalFraction": 0.72,
            "hoverToOpen": false,
            "autoCollapse": true,
            "panelWidth": 350.0,
            "panelHeight": 540.0,
            "focusMinutes": 25,
            "breakMinutes": 5,
            "autoBreak": true,
            "showCompleted": true,
            "sounds": true,
            "menuBarCount": true,
            "didOnboard": false,
            "largeMode": false,
        ])
        edgeRight = d.bool(forKey: "edgeRight")
        idleOpacity = d.double(forKey: "idleOpacity")
        verticalFraction = d.double(forKey: "verticalFraction")
        hoverToOpen = d.bool(forKey: "hoverToOpen")
        autoCollapse = d.bool(forKey: "autoCollapse")
        panelWidth = d.double(forKey: "panelWidth")
        panelHeight = d.double(forKey: "panelHeight")
        focusMinutes = d.integer(forKey: "focusMinutes")
        breakMinutes = d.integer(forKey: "breakMinutes")
        autoBreak = d.bool(forKey: "autoBreak")
        showCompleted = d.bool(forKey: "showCompleted")
        sounds = d.bool(forKey: "sounds")
        menuBarCount = d.bool(forKey: "menuBarCount")
        didOnboard = d.bool(forKey: "didOnboard")
        largeMode = d.bool(forKey: "largeMode")
    }
}
