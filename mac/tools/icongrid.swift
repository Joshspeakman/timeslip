// icongrid <rendered icon.png> <out 1024 png>: release/android/icon.html renders its tile at 16..496 of 512; this puts it on
// macOS's icon grid (824 of 1024, centred, a soft shadow), so it sits like the other ports' icons. Used by mac/install.sh.
import AppKit
// fit the rendered tile (16..496 of 512) onto macOS's icon grid: 824 of 1024, centred, transparent margin
let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 1024, height: 1024)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
let s = src.size, t = s.width * 16 / 512
let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.35); sh.shadowBlurRadius = 18; sh.shadowOffset = NSSize(width: 0, height: -8); sh.set()
src.draw(in: NSRect(x: 100, y: 100, width: 824, height: 824), from: NSRect(x: t, y: t, width: s.width - 2 * t, height: s.height - 2 * t), operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
