import SpriteKit
import Foundation

/// Visual node for a figure (character, monster, summon, objective) on the board.
class PieceSpriteNode: SKNode {
    let pieceID: PieceID

    private let bodyNode: SKShapeNode
    private let labelNode: SKLabelNode
    private var hpBarBg: SKShapeNode?
    private var hpBarFill: SKShapeNode?

    private static let standeeSize: CGFloat = 30
    private static let characterSize: CGFloat = 36
    private static let eliteColor = SKColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1.0)
    private static let normalColor = SKColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
    private static let characterColor = SKColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)
    private static let summonColor = SKColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0)
    private static let objectiveColor = SKColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)

    /// Create a piece sprite with optional character appearance data.
    init(pieceID: PieceID, characterColor: SKColor? = nil, thumbnailImage: PlatformImage? = nil) {
        self.pieceID = pieceID

        // Create body shape — characters get a circular token, others keep squares
        switch pieceID {
        case .character:
            let size = Self.characterSize
            bodyNode = SKShapeNode(circleOfRadius: size / 2)
            bodyNode.lineWidth = 3
        default:
            let size = Self.standeeSize
            let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            bodyNode = SKShapeNode(rect: rect, cornerRadius: 4)
            bodyNode.lineWidth = 2
        }

        // Label
        labelNode = SKLabelNode(fontNamed: "Helvetica-Bold")
        labelNode.fontSize = 10
        labelNode.verticalAlignmentMode = .center
        labelNode.horizontalAlignmentMode = .center
        labelNode.fontColor = .white
        labelNode.zPosition = 2

        super.init()

        // Configure appearance based on piece type
        switch pieceID {
        case .character(let charID):
            let color = characterColor ?? Self.characterColor
            bodyNode.strokeColor = color
            labelNode.fontSize = 11

            // Try to add thumbnail image inside the circle
            if let image = thumbnailImage {
                let texSize = Self.characterSize - 6
                let texture = SKTexture(image: image)
                let sprite = SKSpriteNode(texture: texture, size: CGSize(width: texSize, height: texSize))
                let cropNode = SKCropNode()
                let mask = SKShapeNode(circleOfRadius: texSize / 2)
                mask.fillColor = .white
                cropNode.maskNode = mask
                cropNode.addChild(sprite)
                cropNode.zPosition = 1
                addChild(cropNode)

                // Dark fill behind texture for transparency edges
                bodyNode.fillColor = SKColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
                // Hide label when thumbnail is shown
                labelNode.isHidden = true
            } else {
                // Fallback: colored circle with abbreviation
                bodyNode.fillColor = color.withAlphaComponent(0.8)
                let name = charID.split(separator: "-").last.map(String.init) ?? charID
                labelNode.text = String(name.prefix(2)).uppercased()
            }

        case .monster(_, let standee):
            bodyNode.fillColor = SKColor(red: 0.6, green: 0.15, blue: 0.15, alpha: 1.0)
            bodyNode.strokeColor = Self.normalColor
            labelNode.text = "\(standee)"

        case .summon:
            bodyNode.fillColor = Self.summonColor.withAlphaComponent(0.8)
            bodyNode.strokeColor = Self.summonColor
            labelNode.text = "S"

        case .objective(let id):
            bodyNode.fillColor = Self.objectiveColor.withAlphaComponent(0.6)
            bodyNode.strokeColor = Self.objectiveColor
            labelNode.text = "\(id)"
        }

        addChild(bodyNode)
        addChild(labelNode)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Size

    /// The effective size of this piece (characters are larger).
    private var effectiveSize: CGFloat {
        if case .character = pieceID { return Self.characterSize }
        return Self.standeeSize
    }

    // MARK: - Updates

    /// Update the visual to reflect elite status.
    func setElite(_ isElite: Bool) {
        if isElite {
            bodyNode.strokeColor = Self.eliteColor
            bodyNode.lineWidth = 3
        } else {
            bodyNode.strokeColor = Self.normalColor
            bodyNode.lineWidth = 2
        }
    }

    /// Show/update the HP bar.
    func updateHealthBar(current: Int, max: Int) {
        let barWidth: CGFloat = effectiveSize
        let barHeight: CGFloat = 4
        let yOffset: CGFloat = -effectiveSize / 2 - 6

        // Remove old bars
        hpBarBg?.removeFromParent()
        hpBarFill?.removeFromParent()

        // Background
        let bg = SKShapeNode(rect: CGRect(x: -barWidth / 2, y: yOffset, width: barWidth, height: barHeight), cornerRadius: 1)
        bg.fillColor = SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.8)
        bg.strokeColor = .clear
        bg.zPosition = 1
        addChild(bg)
        hpBarBg = bg

        // Fill
        let fraction = max > 0 ? CGFloat(current) / CGFloat(max) : 0
        let fillWidth = barWidth * min(1, fraction)
        let fill = SKShapeNode(rect: CGRect(x: -barWidth / 2, y: yOffset, width: fillWidth, height: barHeight), cornerRadius: 1)
        let hpColor: SKColor = fraction > 0.5 ? .green : fraction > 0.25 ? .yellow : .red
        fill.fillColor = hpColor
        fill.strokeColor = .clear
        fill.zPosition = 2
        addChild(fill)
        hpBarFill = fill
    }

    // MARK: - Animations

    /// Animate an attack lunge toward a target position.
    func animateAttack(toward target: CGPoint, completion: @escaping () -> Void) {
        let origin = position
        let direction = CGPoint(
            x: (target.x - origin.x) * 0.3,
            y: (target.y - origin.y) * 0.3
        )
        let lunge = SKAction.moveBy(x: direction.x, y: direction.y, duration: 0.15)
        let returnAction = SKAction.move(to: origin, duration: 0.15)
        run(SKAction.sequence([lunge, returnAction])) {
            completion()
        }
    }

    /// Animate damage number floating up.
    func animateDamage(amount: Int) {
        let damageLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        damageLabel.text = "-\(amount)"
        damageLabel.fontSize = 16
        damageLabel.fontColor = .red
        damageLabel.position = CGPoint(x: 0, y: effectiveSize / 2 + 5)
        damageLabel.zPosition = 20
        addChild(damageLabel)

        let fadeUp = SKAction.group([
            SKAction.moveBy(x: 0, y: 30, duration: 0.8),
            SKAction.sequence([
                SKAction.wait(forDuration: 0.4),
                SKAction.fadeOut(withDuration: 0.4)
            ])
        ])
        damageLabel.run(fadeUp) {
            damageLabel.removeFromParent()
        }
    }

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
