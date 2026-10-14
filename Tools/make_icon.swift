import AppKit

// Рисует иконку приложения в PNG 1024×1024. Использование: make_icon <out.png>
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.16, green: 0.45, blue: 0.98, alpha: 1), NSColor(red: 0.42, green: 0.25, blue: 0.93, alpha: 1)])!
    .draw(in: bg, angle: -60)
let center = NSPoint(x: 512, y: 512)
let face = NSBezierPath(ovalIn: NSRect(x: center.x - 270, y: center.y - 270, width: 540, height: 540))
NSColor.white.setFill(); face.fill()
let hands = NSBezierPath()
hands.lineWidth = 46; hands.lineCapStyle = .round
hands.move(to: center); hands.line(to: NSPoint(x: center.x, y: center.y + 190))
hands.move(to: center); hands.line(to: NSPoint(x: center.x + 140, y: center.y - 70))
NSColor(red: 0.2, green: 0.3, blue: 0.85, alpha: 1).setStroke(); hands.stroke()
let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68))
NSColor(red: 0.2, green: 0.3, blue: 0.85, alpha: 1).setFill(); dot.fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
