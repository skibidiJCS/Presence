import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: generate_icon.swift output.png")
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create drawing context")
}

let outerRect = CGRect(x: 42, y: 42, width: 940, height: 940)
let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(
    colors: [
        NSColor(red: 0.10, green: 0.23, blue: 0.52, alpha: 1),
        NSColor(red: 0.19, green: 0.66, blue: 0.72, alpha: 1)
    ]
)!
gradient.draw(in: outerPath, angle: -45)

context.setShadow(
    offset: CGSize(width: 0, height: -12),
    blur: 32,
    color: NSColor.black.withAlphaComponent(0.22).cgColor
)

let eyePath = NSBezierPath()
eyePath.move(to: NSPoint(x: 182, y: 512))
eyePath.curve(
    to: NSPoint(x: 842, y: 512),
    controlPoint1: NSPoint(x: 345, y: 748),
    controlPoint2: NSPoint(x: 679, y: 748)
)
eyePath.curve(
    to: NSPoint(x: 182, y: 512),
    controlPoint1: NSPoint(x: 679, y: 276),
    controlPoint2: NSPoint(x: 345, y: 276)
)
eyePath.close()
NSColor.white.withAlphaComponent(0.96).setFill()
eyePath.fill()

context.setShadow(offset: .zero, blur: 0)
let irisRect = NSRect(x: 352, y: 352, width: 320, height: 320)
let iris = NSBezierPath(ovalIn: irisRect)
NSColor(red: 0.11, green: 0.31, blue: 0.54, alpha: 1).setFill()
iris.fill()

let pupilRect = NSRect(x: 432, y: 432, width: 160, height: 160)
NSColor(red: 0.03, green: 0.08, blue: 0.16, alpha: 1).setFill()
NSBezierPath(ovalIn: pupilRect).fill()

let highlightRect = NSRect(x: 470, y: 548, width: 68, height: 68)
NSColor.white.withAlphaComponent(0.88).setFill()
NSBezierPath(ovalIn: highlightRect).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

