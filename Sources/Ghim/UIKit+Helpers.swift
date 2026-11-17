import AppKit
import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

func luminance(_ hex: String) -> Double {
    let c = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .gray
    return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
}

/// Readable text colour on top of a tab colour.
func inkColor(on hex: String) -> Color {
    luminance(hex) > 0.42 ? Color.black.opacity(0.82) : Color.white
}

extension Priority {
    var color: Color {
        switch self {
        case .none: return .secondary
        case .low: return Color(hex: "#3B82F6")
        case .medium: return Color(hex: "#F59E0B")
        case .high: return Color(hex: "#EF4444")
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Tab shape rounded only on the side facing away from the screen edge.
struct TabShape: Shape {
    var right: Bool
    var radius: CGFloat = 8
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: right ? radius : 0,
                               bottomLeadingRadius: right ? radius : 0,
                               bottomTrailingRadius: right ? 0 : radius,
                               topTrailingRadius: right ? 0 : radius,
                               style: .continuous).path(in: rect)
    }
}

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 3
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.35), value: progress)
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var tint: Color = .secondary
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    init(_ symbol: String, size: CGFloat = 13, tint: Color = .secondary, help: String = "", action: @escaping () -> Void) {
        self.symbol = symbol
        self.size = size
        self.tint = tint
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hover ? Color.primary : tint)
                .frame(width: size + 11, height: size + 11)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.09 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct Chip: View {
    let symbol: String
    let text: String
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct CategoryPill: View {
    let category: Category
    var body: some View {
        Text(category.name)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(inkColor(on: category.colorHex))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color(hex: category.colorHex)))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// Plain-list row modifiers used everywhere.
extension View {
    func ghimRow() -> some View {
        self.listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
