import AppKit

let folder = CommandLine.arguments[1]
let source = NSImage(size: NSSize(width: 1024, height: 1024))
source.lockFocus()
NSColor(calibratedRed: 0.10, green: 0.43, blue: 0.34, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 36, y: 36, width: 952, height: 952), xRadius: 216, yRadius: 216).fill()
NSColor.white.setFill()
for (x, y) in [(224, 544), (544, 544), (224, 224)] {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 256, height: 256), xRadius: 32, yRadius: 32).fill()
}
NSColor(calibratedRed: 0.10, green: 0.43, blue: 0.34, alpha: 1).setFill()
for (x, y) in [(272, 592), (592, 592), (272, 272)] {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 160, height: 160), xRadius: 12, yRadius: 12).fill()
}
NSColor.white.setFill()
for (x, y) in [(312, 632), (632, 632), (312, 312), (544, 384), (704, 384), (624, 304), (544, 224), (704, 224)] {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 80, height: 80), xRadius: 8, yRadius: 8).fill()
}
source.unlockFocus()
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = size * factor
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = factor == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: folder).appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// ICNS stores PNG representations in length-prefixed chunks.
func bigEndianData(_ number: Int) -> Data {
    var value = UInt32(number).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var chunks = Data()
for (type, filename) in [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
] {
    let png = try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(filename))
    chunks.append(Data(type.utf8))
    chunks.append(bigEndianData(png.count + 8))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndianData(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: folder).appendingPathComponent("AppIcon.icns"))
