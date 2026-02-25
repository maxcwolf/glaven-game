import SwiftUI

/// Parses and renders AoE hex grid patterns from monster ability data.
/// Input format: "(x,y,type)|(x,y,type:value)|..."
struct HexGridView: View {
    let pattern: String
    var small: Bool = false
    @Environment(\.uiScale) private var scale

    private var hexSize: CGFloat { small ? 12 : 18 }
    private var scaledHexSize: CGFloat { hexSize * scale }

    private var hexes: [ActionHex] {
        ActionHex.parse(pattern)
    }

    var body: some View {
        let visibleHexes = hexes.filter { $0.type != .invisible }
        guard !visibleHexes.isEmpty else { return AnyView(EmptyView()) }

        let minX = visibleHexes.map(\.x).min() ?? 0
        let maxX = visibleHexes.map(\.x).max() ?? 0
        let minY = visibleHexes.map(\.y).min() ?? 0
        let maxY = visibleHexes.map(\.y).max() ?? 0

        let hexW = scaledHexSize * 2
        let hexH = scaledHexSize * 1.73
        let colSpacing = hexW * 0.75
        let rowSpacing = hexH

        let totalW = CGFloat(maxX - minX) * colSpacing + hexW
        let totalH = CGFloat(maxY - minY) * rowSpacing + hexH * 1.5

        return AnyView(
            ZStack {
                ForEach(visibleHexes) { hex in
                    let offsetX = CGFloat(hex.x - minX) * colSpacing
                    let offsetY = CGFloat(hex.y - minY) * rowSpacing + (hex.x % 2 == 1 ? hexH * 0.5 : 0)

                    AoEHexCell(type: hex.type, condition: hex.value, size: scaledHexSize)
                        .position(x: offsetX + hexW / 2, y: offsetY + hexH / 2)
                }
            }
            .frame(width: totalW, height: totalH)
        )
    }
}

// MARK: - Hex Data

struct ActionHex: Identifiable {
    let id: String
    let x: Int
    let y: Int
    let type: HexType
    let value: String

    init(x: Int, y: Int, type: HexType, value: String = "") {
        self.id = "\(x)-\(y)"
        self.x = x
        self.y = y
        self.type = type
        self.value = value
    }

    enum HexType: String {
        case active, target, conditional, ally, blank, enhance, invisible
    }

    /// Parses "(x,y,type[:value])|(x,y,type[:value])|..."
    static func parse(_ pattern: String) -> [ActionHex] {
        pattern.split(separator: "|").compactMap { token in
            let s = String(token).trimmingCharacters(in: .init(charactersIn: "()"))
            let parts = s.split(separator: ",", maxSplits: 2)
            guard parts.count >= 3,
                  let x = Int(parts[0]),
                  let y = Int(parts[1]) else { return nil }

            let typeAndValue = String(parts[2])
            let typeValue = typeAndValue.split(separator: ":", maxSplits: 1)
            let typeStr = String(typeValue[0])
            let value = typeValue.count > 1 ? String(typeValue[1]) : ""

            guard let hexType = HexType(rawValue: typeStr) else { return nil }
            return ActionHex(x: x, y: y, type: hexType, value: value)
        }
    }
}

// MARK: - Hex Cell

private struct AoEHexCell: View {
    let type: ActionHex.HexType
    let condition: String
    let size: CGFloat

    var body: some View {
        ZStack {
            HexagonShape()
                .fill(fillColor)
            HexagonShape()
                .stroke(strokeColor, lineWidth: 1)

            // Target marker
            if type == .target {
                Circle()
                    .fill(Color.red.opacity(0.6))
                    .frame(width: size * 0.5, height: size * 0.5)
            }

            // Condition overlay
            if !condition.isEmpty {
                BundledImage(ImageLoader.conditionIcon(condition), size: size * 0.6, systemName: "bolt.fill")
            }
        }
        .frame(width: size * 2, height: size * 1.73)
    }

    private var fillColor: Color {
        switch type {
        case .active: return Color(red: 0.6, green: 0.15, blue: 0.15).opacity(0.7)
        case .target: return Color(red: 0.2, green: 0.2, blue: 0.2).opacity(0.7)
        case .conditional: return Color.orange.opacity(0.4)
        case .ally: return Color.blue.opacity(0.4)
        case .blank: return Color.gray.opacity(0.15)
        case .enhance: return Color.yellow.opacity(0.2)
        case .invisible: return Color.clear
        }
    }

    private var strokeColor: Color {
        switch type {
        case .active: return Color(red: 0.8, green: 0.2, blue: 0.2)
        case .target: return Color.gray.opacity(0.6)
        case .conditional: return Color.orange.opacity(0.6)
        case .ally: return Color.blue.opacity(0.6)
        case .blank: return Color.gray.opacity(0.3)
        case .enhance: return Color.yellow.opacity(0.5)
        case .invisible: return Color.clear
        }
    }
}

// MARK: - Hexagon Shape

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY

        // Flat-top hexagon
        var path = Path()
        path.move(to: CGPoint(x: cx + w * 0.5, y: cy))
        path.addLine(to: CGPoint(x: cx + w * 0.25, y: cy - h * 0.5))
        path.addLine(to: CGPoint(x: cx - w * 0.25, y: cy - h * 0.5))
        path.addLine(to: CGPoint(x: cx - w * 0.5, y: cy))
        path.addLine(to: CGPoint(x: cx - w * 0.25, y: cy + h * 0.5))
        path.addLine(to: CGPoint(x: cx + w * 0.25, y: cy + h * 0.5))
        path.closeSubpath()
        return path
    }
}
