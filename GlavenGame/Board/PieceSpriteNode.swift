import SpriteKit
import Foundation

/// How a figure's token looks: its portrait, the colour of its rim and the badge it carries.
struct PieceAppearance {
    enum Rank: Equatable {
        case character, normal, elite, boss, summon, objective
    }

    var rank: Rank
    /// Character or monster portrait; nil draws `initials` instead.
    var portrait: PlatformImage?
    /// Rim colour: the character's colour, a summon's owner's colour, or the monster rank's colour.
    var rimColor: SKColor
    /// Standee number for monsters.
    var badge: String?
    var initials: String
    /// Characters, summons, escorts and allied monsters: their HP bars are green, enemies' red.
    var isPlayerSide: Bool

    static let normalRim = SKColor(red: 0.91, green: 0.89, blue: 0.85, alpha: 1)
    static let eliteRim = SKColor(red: 0.89, green: 0.70, blue: 0.24, alpha: 1)
    static let bossRim = SKColor(red: 0.78, green: 0.27, blue: 0.23, alpha: 1)
    static let objectiveRim = SKColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)

    /// A plain token for `pieceID` when nothing more is known about it.
    static func fallback(for pieceID: PieceID) -> PieceAppearance {
        switch pieceID {
        case .character(let id):
            return PieceAppearance(rank: .character, portrait: nil,
                                   rimColor: SKColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1), badge: nil,
                                   initials: String(GameText.titleCased(id).prefix(2)).uppercased(), isPlayerSide: true)
        case .monster(let name, let standee):
            return PieceAppearance(rank: .normal, portrait: nil, rimColor: normalRim, badge: "\(standee)",
                                   initials: String(GameText.titleCased(name).prefix(1)), isPlayerSide: false)
        case .summon:
            return PieceAppearance(rank: .summon, portrait: nil,
                                   rimColor: SKColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1), badge: nil, initials: "S",
                                   isPlayerSide: true)
        case .objective(let id):
            return PieceAppearance(rank: .objective, portrait: nil, rimColor: objectiveRim, badge: nil, initials: "\(id)",
                                   isPlayerSide: true)
        }
    }
}

/// What a figure's token shows about its state.
struct PieceStatus: Equatable {
    var health: Int
    var maxHealth: Int
    /// Active conditions, in display order.
    var conditions: [ConditionName]
}

/// Visual node for a figure (character, monster, summon, objective) on the board: a round
/// portrait token with a rim showing its side and rank, a standee badge, an HP bar and the icons
/// of its active conditions.
class PieceSpriteNode: SKNode {
    let pieceID: PieceID
    private(set) var appearance: PieceAppearance
    /// The state the token last displayed (nil until the first `apply(status:)`).
    private(set) var status: PieceStatus?
    /// The conditions shown as icons (at most `maxConditionIcons`).
    private(set) var shownConditions: [ConditionName] = []

    private let rimNode: SKShapeNode
    private var badgeNode: SKShapeNode?
    private let hpBar = SKNode()
    private let hpFill: SKSpriteNode
    private let conditionLayer = SKNode()

    static let maxConditionIcons = 4
    /// Token radius; characters are a little larger than standees, as on the table.
    static func radius(for pieceID: PieceID) -> CGFloat {
        if case .character = pieceID { return HexMath.cellStepX * 0.40 }
        return HexMath.cellStepX * 0.37
    }

    private var radius: CGFloat { Self.radius(for: pieceID) }

    init(pieceID: PieceID, appearance: PieceAppearance) {
        self.pieceID = pieceID
        self.appearance = appearance
        let radius = Self.radius(for: pieceID)

        rimNode = SKShapeNode(circleOfRadius: radius)
        rimNode.fillColor = SKColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1)
        rimNode.strokeColor = appearance.rimColor
        rimNode.lineWidth = appearance.rank == .elite || appearance.rank == .boss ? 4 : 3
        rimNode.glowWidth = 0

        let barWidth = radius * 1.5
        hpFill = SKSpriteNode(color: .green, size: CGSize(width: barWidth - 2, height: 4))

        super.init()

        // A soft shadow under the token separates it from the map art.
        let shadow = SKShapeNode(circleOfRadius: radius)
        shadow.fillColor = SKColor(white: 0, alpha: 0.45)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -2.5)
        shadow.zPosition = -1
        addChild(shadow)
        addChild(rimNode)

        if let portrait = appearance.portrait, let texture = Self.circularTexture(portrait, diameter: radius * 2 - 4) {
            let sprite = SKSpriteNode(texture: texture, size: CGSize(width: radius * 2 - 4, height: radius * 2 - 4))
            sprite.zPosition = 1
            sprite.name = "portrait"
            addChild(sprite)
        } else {
            let label = SKLabelNode(fontNamed: "Helvetica-Bold")
            label.text = appearance.initials
            label.fontSize = radius * 0.7
            label.fontColor = appearance.rimColor
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 1
            addChild(label)
        }

        if let badge = appearance.badge {
            let badgeRadius = radius * 0.36
            let disc = SKShapeNode(circleOfRadius: badgeRadius)
            disc.fillColor = appearance.rank == .elite ? PieceAppearance.eliteRim
                : appearance.rank == .boss ? PieceAppearance.bossRim : PieceAppearance.normalRim
            disc.strokeColor = SKColor(white: 0, alpha: 0.6)
            disc.lineWidth = 1
            disc.position = CGPoint(x: radius * 0.74, y: radius * 0.74)
            disc.zPosition = 3
            let label = SKLabelNode(fontNamed: "Helvetica-Bold")
            label.text = badge
            label.fontSize = badgeRadius * 1.25
            label.fontColor = appearance.rank == .boss ? .white : SKColor(red: 0.1, green: 0.08, blue: 0.06, alpha: 1)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            disc.addChild(label)
            addChild(disc)
            badgeNode = disc
        }

        // HP bar under the token: a dark track and a fill scaled to the remaining health.
        let track = SKSpriteNode(color: SKColor(red: 0.12, green: 0.08, blue: 0.07, alpha: 0.95),
                                 size: CGSize(width: barWidth, height: 6))
        hpBar.addChild(track)
        hpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpFill.position = CGPoint(x: -(barWidth - 2) / 2, y: 0)
        hpFill.zPosition = 1
        hpBar.addChild(hpFill)
        hpBar.position = CGPoint(x: 0, y: -radius - 5)
        hpBar.zPosition = 3
        hpBar.isHidden = true
        addChild(hpBar)

        conditionLayer.zPosition = 4
        addChild(conditionLayer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Size

    /// The effective size of this piece (its diameter).
    private var effectiveSize: CGFloat { radius * 2 }

    // MARK: - Updates

    /// Show the figure's health and conditions.
    /// Make a just-gained condition's icon pop, so the eye finds it.
    func popCondition(_ condition: ConditionName) {
        guard let chip = conditionLayer.childNode(withName: "condition-\(condition.rawValue)") else { return }
        chip.setScale(0.2)
        let grow = SKAction.scale(to: 1.5, duration: 0.14)
        grow.timingMode = .easeOut
        let settle = SKAction.scale(to: 1, duration: 0.16)
        settle.timingMode = .easeIn
        chip.run(.sequence([grow, settle]))
    }

    func apply(status newStatus: PieceStatus) {
        guard newStatus != status else { return }
        status = newStatus

        let fraction = newStatus.maxHealth > 0
            ? min(1, max(0, CGFloat(newStatus.health) / CGFloat(newStatus.maxHealth))) : 0
        hpFill.xScale = fraction
        hpFill.color = appearance.isPlayerSide
            ? SKColor(red: 0.37, green: 0.66, blue: 0.27, alpha: 1)
            : SKColor(red: 0.85, green: 0.28, blue: 0.23, alpha: 1)
        hpBar.isHidden = newStatus.maxHealth <= 0

        let shown = Array(newStatus.conditions.prefix(Self.maxConditionIcons))
        guard shown != shownConditions else { return }
        shownConditions = shown
        conditionLayer.removeAllChildren()
        // Icons sit on the token's left edge, clear of the badge and of the tokens above and below.
        let iconRadius = radius * 0.3
        for (index, condition) in shown.enumerated() {
            let angle = CGFloat.pi * (0.78 + 0.22 * CGFloat(index))
            let chip = SKShapeNode(circleOfRadius: iconRadius)
            chip.fillColor = SKColor(red: 0.1, green: 0.08, blue: 0.07, alpha: 0.95)
            chip.strokeColor = SKColor(white: 1, alpha: 0.5)
            chip.lineWidth = 1
            chip.position = CGPoint(x: cos(angle) * (radius + 1), y: sin(angle) * (radius + 1))
            chip.name = "condition-\(condition.rawValue)"
            if let texture = Self.conditionTexture(condition) {
                let icon = SKSpriteNode(texture: texture, size: CGSize(width: iconRadius * 1.6, height: iconRadius * 1.6))
                chip.addChild(icon)
            }
            conditionLayer.addChild(chip)
        }
    }

    // MARK: - Textures

    private static var conditionTextures: [ConditionName: SKTexture] = [:]

    private static func conditionTexture(_ condition: ConditionName) -> SKTexture? {
        if let cached = conditionTextures[condition] { return cached }
        guard let image = ImageLoader.conditionIcon(condition.rawValue) else { return nil }
        let texture = SKTexture(image: image)
        conditionTextures[condition] = texture
        return texture
    }

    private static var portraitTextures: [ObjectIdentifier: SKTexture] = [:]

    /// The portrait cut to a circle once, so tokens need no crop node and batch together.
    static func circularTexture(_ image: PlatformImage, diameter: CGFloat) -> SKTexture? {
        let key = ObjectIdentifier(image)
        if let cached = portraitTextures[key] { return cached }
        let pixels = Int(diameter * 2)
        #if os(macOS)
        var rect = CGRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        #else
        guard let source = image.cgImage else { return nil }
        #endif
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        context.addEllipse(in: bounds)
        context.clip()
        // Fill the circle with the portrait's centre square.
        let side = min(source.width, source.height)
        let crop = CGRect(x: (source.width - side) / 2, y: (source.height - side) / 2, width: side, height: side)
        guard let square = source.cropping(to: crop) else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: bounds)
        guard let circular = context.makeImage() else { return nil }
        let texture = SKTexture(cgImage: circular)
        portraitTextures[key] = texture
        return texture
    }

    // MARK: - Animations

    /// Animate alpha to translucent (invisible condition) or back to full opacity.
    func setInvisible(_ invisible: Bool) {
        let targetAlpha: CGFloat = invisible ? 0.35 : 1.0
        run(SKAction.fadeAlpha(to: targetAlpha, duration: 0.3))
    }

    /// Animate death (fade + shrink).
    func animateDeath(completion: @escaping () -> Void) {
        let death = SKAction.group([
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.scale(to: 0.3, duration: 0.3)
        ])
        run(death) {
            self.removeFromParent()
            completion()
        }
    }
}

// MARK: - SKColor Hex Init

extension SKColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        guard hexSanitized.count == 6, let int = UInt64(hexSanitized, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
