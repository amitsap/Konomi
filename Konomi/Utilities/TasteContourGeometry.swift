import CoreGraphics

enum TasteContourGeometry {
    static let dot = CGPoint(x: 0.72, y: 0.30)
    static let iconInset: CGFloat = 0.078125

    static func paths(in rect: CGRect) -> [CGPath] {
        [
            loop(in: rect, inset: 0.05, phase: 0),
            loop(in: rect, inset: 0.20, phase: 0.035),
            loop(in: rect, inset: 0.35, phase: -0.025)
        ]
    }

    static func dotCenter(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * dot.x, y: rect.minY + rect.height * dot.y)
    }

    private static func loop(in rect: CGRect, inset: CGFloat, phase: CGFloat) -> CGPath {
        let x0 = rect.minX + rect.width * (inset + phase)
        let y0 = rect.minY + rect.height * inset
        let x1 = rect.maxX - rect.width * inset
        let y1 = rect.maxY - rect.height * inset
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0 + (x1 - x0) * 0.50, y: y0))
        path.addCurve(
            to: CGPoint(x: x1, y: y0 + (y1 - y0) * 0.46),
            control1: CGPoint(x: x0 + (x1 - x0) * 0.83, y: y0 - rect.height * 0.02),
            control2: CGPoint(x: x1 + rect.width * 0.025, y: y0 + (y1 - y0) * 0.17)
        )
        path.addCurve(
            to: CGPoint(x: x0 + (x1 - x0) * 0.44, y: y1),
            control1: CGPoint(x: x1 - rect.width * 0.01, y: y0 + (y1 - y0) * 0.78),
            control2: CGPoint(x: x0 + (x1 - x0) * 0.76, y: y1 + rect.height * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: x0, y: y0 + (y1 - y0) * 0.50),
            control1: CGPoint(x: x0 + (x1 - x0) * 0.14, y: y1 - rect.height * 0.01),
            control2: CGPoint(x: x0 - rect.width * 0.03, y: y0 + (y1 - y0) * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: x0 + (x1 - x0) * 0.50, y: y0),
            control1: CGPoint(x: x0 + rect.width * 0.01, y: y0 + (y1 - y0) * 0.17),
            control2: CGPoint(x: x0 + (x1 - x0) * 0.23, y: y0 + rect.height * 0.015)
        )
        path.closeSubpath()
        return path
    }
}
