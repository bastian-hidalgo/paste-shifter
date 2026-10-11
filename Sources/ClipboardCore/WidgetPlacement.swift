import CoreGraphics

public enum WidgetPlacement {
    public static func nearMouse(_ mouse: CGPoint, size: CGSize, in screen: CGRect) -> CGPoint {
        let gap: CGFloat = 14, margin: CGFloat = 8
        var x = mouse.x + gap
        var y = mouse.y - size.height - gap
        if x + size.width > screen.maxX - margin { x = mouse.x - size.width - gap }
        if y < screen.minY + margin { y = mouse.y + gap }
        x = max(screen.minX + margin, min(x, screen.maxX - size.width - margin))
        y = max(screen.minY + margin, min(y, screen.maxY - size.height - margin))
        return CGPoint(x: x, y: y)
    }
}
