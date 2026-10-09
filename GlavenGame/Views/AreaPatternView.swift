import SwiftUI

/// An ability's area drawn as on the card: the attacker's hex grey, attacked hexes red, hexes
/// marked for an enhancement dashed; `highlighted` (one of the marked hexes) in brass.
struct AreaPatternView: View {
    let pattern: String
    var highlighted: ActionHex? = nil
    /// Center to corner of one hex.
    var radius: CGFloat = 10

    private var hexes: [ActionHex] {
        ActionHex.parse(pattern).filter { [.active, .target, .conditional, .enhance].contains($0.type) }
    }

    /// Pointy-top hexes, odd rows shifted half a hex right (the pattern's own coordinates).
    private func center(_ hex: ActionHex) -> CGPoint {
        CGPoint(x: sqrt(3) * radius * (CGFloat(hex.x) + (hex.y & 1 == 1 ? 0.5 : 0)), y: 1.5 * radius * CGFloat(hex.y))
    }

    var body: some View {
        let centers = hexes.map(center)
        let minX = (centers.map(\.x).min() ?? 0) - sqrt(3) / 2 * radius
        let minY = (centers.map(\.y).min() ?? 0) - radius
        let width = (centers.map(\.x).max() ?? 0) + sqrt(3) / 2 * radius - minX
        let height = (centers.map(\.y).max() ?? 0) + radius - minY
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(hexes, centers).enumerated()), id: \.offset) { _, pair in
                let (hex, point) = pair
                let shape = HexShape(center: CGPoint(x: point.x - minX, y: point.y - minY), radius: radius * 0.92)
                let isHighlighted = hex.type == .enhance && hex.x == highlighted?.x && hex.y == highlighted?.y
                shape.fill(fill(hex, highlighted: isHighlighted))
                if hex.type == .enhance {
                    shape.stroke(isHighlighted ? BoardTheme.brass : BoardTheme.secondaryText,
                                 style: StrokeStyle(lineWidth: 1.5, dash: isHighlighted ? [] : [3, 2]))
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func fill(_ hex: ActionHex, highlighted: Bool) -> Color {
        switch hex.type {
        case .active: return BoardTheme.secondaryText.opacity(0.6)
        case .target, .conditional: return BoardTheme.defeat.opacity(0.85)
        default: return highlighted ? BoardTheme.brass.opacity(0.5) : .clear
        }
    }
}

private struct HexShape: Shape {
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for corner in 0..<6 {
            let angle = CGFloat(corner) * .pi / 3 - .pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
