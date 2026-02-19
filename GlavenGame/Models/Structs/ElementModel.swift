import Foundation

struct ElementModel: Codable, Hashable, Identifiable {
    var id: ElementType { type }
    var type: ElementType
    var state: ElementState

    init(type: ElementType, state: ElementState = .inert) {
        self.type = type
        self.state = state
    }

    static func defaultBoard() -> [ElementModel] {
        ElementType.gameElements.map { ElementModel(type: $0) }
    }
}
