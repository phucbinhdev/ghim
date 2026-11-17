import AppKit
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// background squircle
let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(calibratedWhite: 0.20, alpha: 1), NSColor(calibratedWhite: 0.09, alpha: 1)])!.draw(in: bg, angle: -90)
// paper sheet
let paper = NSBezierPath(roundedRect: NSRect(x: 200, y: 200, width: 470, height: 624), xRadius: 40, yRadius: 40)
NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); paper.fill()
// lines + checks
for i in 0..<4 {
    let y = CGFloat(660 - i * 120)
    let box = NSBezierPath(ovalIn: NSRect(x: 250, y: y, width: 54, height: 54))
    box.lineWidth = 10
    NSColor(calibratedWhite: 0.35, alpha: 1).setStroke(); box.stroke()
    if i < 2 {
        NSColor(red: 0.20, green: 0.70, blue: 0.40, alpha: 1).setFill(); box.fill()
    }
    let line = NSBezierPath(roundedRect: NSRect(x: 330, y: y + 18, width: CGFloat(260 - i * 30), height: 18), xRadius: 9, yRadius: 9)
    NSColor(calibratedWhite: 0.78, alpha: 1).setFill(); line.fill()
}
// coloured edge tabs
let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.95,0.42,0.23),(0.96,0.73,0.17),(0.93,0.55,0.78),(0.36,0.50,0.85),(0.31,0.49,0.36)]
for (i, c) in colors.enumerated() {
    let h: CGFloat = 112
    let y = 790 - CGFloat(i) * (h + 14) - h
    let r = NSRect(x: 690, y: y, width: 140, height: h)
    let p = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26)
    NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1).setFill(); p.fill()
}
_ = ctx
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
