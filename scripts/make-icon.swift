import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)
    let box = NSRect(x: 78, y: 78, width: 868, height: 868)
    let path = NSBezierPath(roundedRect: box, xRadius: 192, yRadius: 192)
    NSColor(calibratedRed: 0.075, green: 0.088, blue: 0.09, alpha: 1).setFill(); path.fill()
    NSColor(calibratedWhite: 1, alpha: 0.11).setStroke(); path.lineWidth = 3; path.stroke()
    let accent = NSColor(calibratedRed: 0.831, green: 0.957, blue: 0.608, alpha: 1)
    accent.setStroke()
    for (x, y, dx, dy) in [(285.0, 285.0, 1.0, 1.0), (739, 285, -1, 1), (285, 739, 1, -1), (739, 739, -1, -1)] {
        let p = NSBezierPath(); p.lineWidth = 38; p.lineCapStyle = .round; p.lineJoinStyle = .round
        p.move(to: NSPoint(x: x, y: y + dy * 112)); p.line(to: NSPoint(x: x, y: y + dy * 22))
        p.curve(to: NSPoint(x: x + dx * 22, y: y), controlPoint1: NSPoint(x: x, y: y + dy * 7), controlPoint2: NSPoint(x: x + dx * 7, y: y))
        p.line(to: NSPoint(x: x + dx * 112, y: y)); p.stroke()
    }
    accent.setFill()
    let triangle = NSBezierPath(); triangle.move(to: NSPoint(x: 451, y: 387)); triangle.line(to: NSPoint(x: 641, y: 512)); triangle.line(to: NSPoint(x: 451, y: 637)); triangle.close(); triangle.fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name)) }
}
