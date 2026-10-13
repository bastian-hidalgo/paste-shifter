import AppKit
import SwiftUI

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

/// Compact Orbital symbol: the Paste Shifter mark as a planet, crossed by its
/// local orbit and accompanied by a small moon. Scales from widget controls to
/// settings cards without relying on a generic system glyph.
struct OrbitalMark: View {
    var size: CGFloat = 24
    var isActive = true

    private let violet = Color(red: 0.58, green: 0.25, blue: 0.96)
    private let deepViolet = Color(red: 0.25, green: 0.08, blue: 0.52)

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(violet.opacity(isActive ? 0.72 : 0.42), lineWidth: max(0.8, size * 0.045))
                .frame(width: size * 1.06, height: size * 0.43)
                .rotationEffect(.degrees(-28))

            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(LinearGradient(colors: [violet, deepViolet], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.64, height: size * 0.64)
                .overlay {
                    Image(nsImage: BrandIcon.template)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .padding(size * 0.15)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: max(0.6, size * 0.035))
                }
                .shadow(color: violet.opacity(isActive ? 0.24 : 0.08), radius: size * 0.14, y: size * 0.04)

            Circle()
                .fill(isActive ? Color(red: 0.84, green: 0.66, blue: 1) : Color.secondary.opacity(0.7))
                .frame(width: size * 0.17, height: size * 0.17)
                .offset(x: size * 0.43, y: -size * 0.24)
        }
        .frame(width: size * 1.15, height: size * 1.15)
        .accessibilityLabel("Orbital de Paste Shifter")
    }
}
