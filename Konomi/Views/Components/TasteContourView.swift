import SwiftUI

struct TasteContourView: View {
    enum Strength {
        case compact
        case full
    }

    var strength: Strength = .full

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let opacities: [Double] = strength == .full ? [1, 0.62, 0.34] : [0.56, 0.34, 0.20]
            let width = max(1.5, min(size.width, size.height) * 0.035)
            for (path, opacity) in zip(TasteContourGeometry.paths(in: rect), opacities) {
                context.stroke(
                    Path(path),
                    with: .color(KonomiTheme.persimmon.opacity(opacity)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                )
            }
            let center = TasteContourGeometry.dotCenter(in: rect)
            let diameter = max(5, min(size.width, size.height) * 0.085)
            let dotRect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            context.fill(Path(ellipseIn: dotRect), with: .color(KonomiTheme.tasteViolet))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
