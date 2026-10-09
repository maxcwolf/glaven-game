import Foundation

/// One hex of an area-of-effect pattern from monster ability data.
/// Input format: "(x,y,type)|(x,y,type:value)|..."
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
