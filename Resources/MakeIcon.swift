import AppKit

let directory = CommandLine.arguments[1]
guard let source = NSImage(contentsOfFile: CommandLine.arguments[3]) else {
    fatalError("No se encontró el icono fuente")
}
var chunks = Data()
func integer(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: url)
        let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"], 256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
        chunks.append(Data(types[size]![scale - 1].utf8))
        chunks.append(integer(png.count + 8)); chunks.append(png)
    }
}
var icon = Data("icns".utf8)
icon.append(integer(chunks.count + 8)); icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
