import Foundation

protocol Figure: AnyObject, Identifiable {
    var name: String { get }
    var edition: String { get }
    var level: Int { get set }
    var off: Bool { get set }
    var active: Bool { get set }
    var figureType: FigureType { get }
    var effectiveInitiative: Double { get }
}
