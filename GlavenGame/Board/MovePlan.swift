import CoreGraphics

/// How a move looks on the board. Each kind reads differently at a glance: a walk steps hex by
/// hex, a jump arcs over what's in between, a flyer stays lifted the whole way, a teleport
/// vanishes and reappears, and a push or pull shoves the figure without its own footwork.
enum MoveAnimation: Equatable {
    case walk, jump, fly, teleport, forced

    init(_ style: MovementStyle) {
        switch style {
        case .normal: self = .walk
        case .jump: self = .jump
        case .fly: self = .fly
        case .forced: self = .forced
        }
    }
}

/// A move as data: where the figure goes, how long each leg takes, how high it's lifted, and
/// whether it fades out and in. The scene turns it into SpriteKit actions.
struct MovePlan: Equatable {
    enum Timing: Equatable { case linear, easeIn, easeOut, easeInEaseOut }

    struct Leg: Equatable {
        var to: CGPoint
        var duration: Double
        var timing: Timing
    }

    var legs: [Leg]
    /// How much bigger the figure draws at the top of its lift (1 = on the ground). A lifted
    /// figure also casts a shadow.
    var lift: CGFloat = 1
    /// Jumps rise and fall over the move; flyers rise, hold and land.
    var holdsLift = false
    /// Vanish at the start and reappear at the end (a teleport).
    var fades = false

    var duration: Double { legs.reduce(0) { $0 + $1.duration } + (fades ? 2 * MovePlan.fadeDuration : 0) }

    static let stepDuration = 0.2
    static let fadeDuration = 0.18

    /// The plan for moving through `points` (the hex centres, the first being where the figure
    /// stands). Reduced motion keeps every move readable but drops the lifting and bobbing.
    static func plan(_ kind: MoveAnimation, through points: [CGPoint], reduceMotion: Bool = false) -> MovePlan {
        let steps = Array(points.dropFirst())
        guard let last = steps.last else { return MovePlan(legs: []) }
        func legs(duration: Double, eased: Bool) -> [Leg] {
            steps.enumerated().map { index, point in
                let timing: Timing
                if !eased { timing = .linear }
                else if steps.count == 1 { timing = .easeInEaseOut }
                else if index == 0 { timing = .easeIn }
                else if index == steps.count - 1 { timing = .easeOut }
                else { timing = .linear }
                return Leg(to: point, duration: duration, timing: timing)
            }
        }
        switch kind {
        case .walk:
            return MovePlan(legs: legs(duration: stepDuration, eased: true))
        case .jump:
            // Over the hexes in between in one arc, quicker than walking them.
            let total = max(0.35, Double(steps.count) * 0.13)
            return MovePlan(legs: [Leg(to: last, duration: total, timing: .easeInEaseOut)],
                            lift: reduceMotion ? 1 : 1.3)
        case .fly:
            return MovePlan(legs: legs(duration: 0.17, eased: true), lift: reduceMotion ? 1 : 1.18, holdsLift: true)
        case .teleport:
            return MovePlan(legs: [Leg(to: last, duration: 0, timing: .linear)], fades: true)
        case .forced:
            // Shoved: quick, even legs with no wind-up.
            return MovePlan(legs: legs(duration: 0.12, eased: false))
        }
    }
}
