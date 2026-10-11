import AppKit

enum BrandIcon {
    static let ghost: NSImage = {
        let image = NSImage(size: NSSize(width: 12, height: 14), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.scaleBy(x: rect.width / 100, y: rect.height / 120)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 50, y: 3))
            path.addCurve(to: CGPoint(x: 77, y: 48), control1: CGPoint(x: 50, y: 3), control2: CGPoint(x: 77, y: 12))
            path.addLine(to: CGPoint(x: 77, y: 111))
            path.addLine(to: CGPoint(x: 62, y: 101)); path.addLine(to: CGPoint(x: 50, y: 113))
            path.addLine(to: CGPoint(x: 38, y: 101)); path.addLine(to: CGPoint(x: 23, y: 111))
            path.addLine(to: CGPoint(x: 23, y: 48))
            path.addCurve(to: CGPoint(x: 50, y: 3), control1: CGPoint(x: 23, y: 12), control2: CGPoint(x: 50, y: 3))
            path.closeSubpath()
            context.addPath(path); context.setFillColor(NSColor.black.cgColor); context.fillPath()
            context.setBlendMode(.clear)
            context.fillEllipse(in: CGRect(x: 34, y: 42, width: 9, height: 13))
            context.fillEllipse(in: CGRect(x: 57, y: 42, width: 9, height: 13))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Fantasma"
        return image
    }()

    /// Vector silhouette shared by menu bar and settings; macOS tints templates.
    static let template: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.scaleBy(x: rect.width / 1000, y: rect.height / 1000)
            let shape = CGMutablePath()
            shape.move(to: CGPoint(x: 0, y: 180))
            shape.addCurve(to: CGPoint(x: 190, y: 10), control1: CGPoint(x: 0, y: 70), control2: CGPoint(x: 80, y: 10))
            shape.addLine(to: CGPoint(x: 650, y: 0))
            shape.addCurve(to: CGPoint(x: 820, y: 130), control1: CGPoint(x: 760, y: -5), control2: CGPoint(x: 820, y: 20))
            shape.addLine(to: CGPoint(x: 820, y: 170))
            shape.addCurve(to: CGPoint(x: 720, y: 260), control1: CGPoint(x: 820, y: 220), control2: CGPoint(x: 790, y: 240))
            shape.addLine(to: CGPoint(x: 400, y: 360))
            shape.addCurve(to: CGPoint(x: 265, y: 530), control1: CGPoint(x: 310, y: 390), control2: CGPoint(x: 290, y: 460))
            shape.addCurve(to: CGPoint(x: 125, y: 670), control1: CGPoint(x: 245, y: 595), control2: CGPoint(x: 210, y: 650))
            shape.addCurve(to: CGPoint(x: 0, y: 560), control1: CGPoint(x: 45, y: 690), control2: CGPoint(x: 0, y: 650))
            shape.closeSubpath()
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(shape); context.fillPath()
            context.translateBy(x: 1000, y: 1000)
            context.scaleBy(x: -1, y: -1)
            context.addPath(shape); context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Paste Shifter"
        return image
    }()
}
