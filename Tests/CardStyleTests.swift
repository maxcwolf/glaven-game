import XCTest
import SwiftUI
import SwiftData
@testable import GlavenGameLib

/// The players' card style (the scans or the drawn cards) and card size (Settings → Cards): kept,
/// and followed by every place a character's ability card is shown.
@MainActor
final class CardStyleTests: XCTestCase {
    private var gm: GameManager!

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
    }

    private var brute: GameCharacter { gm.game.characters[0] }
    private var trample: AbilityModel {
        gm.editionStore.deckData(name: "brute", edition: "gh")!.abilities.first { $0.name == "Trample" }!
    }

    func testTheStyleChoosesTheScanOrTheDrawnCard() {
        XCTAssertNotNil(AbilityCardFace.scan(of: trample, edition: "gh", style: .scans), "the printed card, the default")
        XCTAssertNil(AbilityCardFace.scan(of: trample, edition: "gh", style: .drawn), "the drawn card when chosen")
        XCTAssertEqual(SettingsManager(modelContext: ModelContext(try! ModelContainer(
            for: Schema([SettingsModel.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))).cardStyle,
                       .scans, "a new player sees the scans")
    }

    /// Three of the Beast Tyrant's cards aren't in the data: drawn, they would be blank.
    func testACardTheDataDoesntHaveShowsItsScanInEitherStyle() throws {
        let swap = try XCTUnwrap(gm.editionStore.deckData(name: "two-mini", edition: "gh")?.abilities.first { $0.name == "Spirit Swap" })
        XCTAssertNotNil(AbilityCardFace.scan(of: swap, edition: "gh", style: .drawn))
    }

    func testTheCardSizeGrowsTheCardAtItsShape() {
        XCTAssertEqual(AbilityCardFace.size(height: 190, scale: 1), CGSize(width: 127, height: 190))
        XCTAssertEqual(AbilityCardFace.size(height: 190, scale: 1.5), CGSize(width: 190, height: 285))
        XCTAssertEqual(AbilityCardFace.size(height: 150, scale: 2), CGSize(width: 200, height: 300))
    }

    func testTheStyleAndSizeAreKept() throws {
        let container = try ModelContainer(for: Schema([SettingsModel.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let settings = SettingsManager(modelContext: context)
        settings.cardStyle = .drawn
        settings.cardScale = 1.45
        settings.saveSettings()
        let again = SettingsManager(modelContext: context)
        XCTAssertEqual(again.cardStyle, .drawn)
        XCTAssertEqual(again.cardScale, 1.45, accuracy: 0.001)

        // A size kept from outside the slider's range comes back inside it.
        settings.cardScale = 9
        settings.saveSettings()
        XCTAssertEqual(SettingsManager(modelContext: context).cardScale,
                       SettingsManager.cardScaleRange.upperBound)
    }

    // MARK: - Drawn

    /// A card as the face draws it, at a card style and size (the hand's 190 points tall).
    private func render(style: CardStyle, scale: CGFloat, followsCardSize: Bool = true) throws -> CGImage {
        let face = AbilityCardFace(card: trample, edition: "gh", height: CardSelectionPanel.cardHeight,
                                   followsCardSize: followsCardSize)
            .environment(\.cardStyle, style)
            .environment(\.cardScale, scale)
        let renderer = ImageRenderer(content: face)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    func testACardGrowsWithTheCardSize() throws {
        XCTAssertEqual(try render(style: .scans, scale: 1).height, 190)
        XCTAssertEqual(try render(style: .scans, scale: 1.5).height, 285, "the scan half as tall again")
        XCTAssertEqual(try render(style: .drawn, scale: 1.5).height, 285, "the drawn card too")
        XCTAssertEqual(try render(style: .drawn, scale: 1.5).width, 190)
        XCTAssertEqual(try render(style: .scans, scale: 1.5, followsCardSize: false).height, 190,
                       "a card already sized to fit (town, the preview) keeps its size")
    }

    /// Where a drawn card's lowest white text ends, as a share of its height.
    private func lowestText(scale: CGFloat) throws -> CGFloat {
        let face = AbilityCardFace(card: trample, edition: "gh", height: CardSelectionPanel.cardHeight)
            .environment(\.cardStyle, .drawn)
            .environment(\.cardScale, scale)
        let renderer = ImageRenderer(content: face)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        for y in stride(from: bitmap.pixelsHigh - 1, through: 0, by: -1) {
            for x in 0..<bitmap.pixelsWide {
                if let c = bitmap.colorAt(x: x, y: y), c.redComponent > 0.85, c.greenComponent > 0.85, c.blueComponent > 0.85 {
                    return CGFloat(y) / CGFloat(bitmap.pixelsHigh)
                }
            }
        }
        return 0
    }

    /// Regression: a crowded half (Trample's bottom) shrank to its smallest type at 100% but not
    /// at 150%; its type now shrinks by the same share at any card size.
    func testACrowdedHalfShrinksAlikeAtAnySize() throws {
        let normal = try lowestText(scale: 1)
        let large = try lowestText(scale: 1.5)
        XCTAssertGreaterThan(normal, 0.8, "the half's lines reach down the card")
        XCTAssertEqual(normal, large, accuracy: 0.04)
    }

    func testACardIsShownInTheChosenStyle() throws {
        let scan = try XCTUnwrap(render(style: .scans, scale: 1).dataProvider?.data) as Data
        let drawn = try XCTUnwrap(render(style: .drawn, scale: 1).dataProvider?.data) as Data
        XCTAssertNotEqual(scan, drawn, "the drawn card in place of the scan")
    }

    /// `CARD_SHEET_OUT=/tmp/cards.png swift test --filter testRenderCardSheet` draws a few of a
    /// class's cards (CARD_SHEET_CLASS, the Brute by default) in both styles at 100% and 150%, and
    /// `…_settings.png` beside it the settings' Cards section.
    func testRenderCardSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["CARD_SHEET_OUT"] else {
            throw XCTSkip("set CARD_SHEET_OUT to draw the card sheet")
        }
        GlavenFont.registerFonts()
        let name = ProcessInfo.processInfo.environment["CARD_SHEET_CLASS"] ?? "brute"
        let all = gm.editionStore.deckData(name: name, edition: "gh")!.abilities
        let start = Int(ProcessInfo.processInfo.environment["CARD_SHEET_FROM"] ?? "0") ?? 0
        let cards = Array(all.dropFirst(start).prefix(5))
        let sheet = VStack(alignment: .leading, spacing: 16) {
            ForEach([CGFloat(1), 1.5], id: \.self) { scale in
                ForEach(CardStyle.allCases, id: \.self) { style in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(cards, id: \.cardId) { card in
                            AbilityCardFace(card: card, edition: "gh", color: .red, height: CardSelectionPanel.cardHeight,
                                            labelResolver: { self.gm.editionStore.resolveCustomText($0, edition: "gh") })
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .environment(\.cardStyle, style)
                    .environment(\.cardScale, scale)
                }
            }
        }
        .padding(16)
        .background(BoardTheme.sheet)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        try XCTUnwrap(NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage)).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))

        gm.settingsManager.cardScale = 1.3
        let settings = ImageRenderer(content: PreferencesSheet().environment(gm).frame(width: 620, height: 1500))
        settings.scale = 1
        try XCTUnwrap(NSBitmapImageRep(cgImage: XCTUnwrap(settings.cgImage)).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out.replacingOccurrences(of: ".png", with: "_settings.png")))
    }

    /// Every place a character's ability card is shown draws it through `AbilityCardFace`, so the
    /// style and size reach them all. These read the game's sources.
    func testEveryCharacterCardIsDrawnThroughTheCardFace() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GlavenGame")
        // Where else a card is drawn, and why.
        let allowed: [String: Int] = [
            "AbilityCardFace.swift": 2,  // the face itself
            "ImageLoader.swift": 1,      // the loader
            "HowToPlayBook.swift": 1,    // teaches the printed card
            "BoardView.swift": 1,        // a monster's ability card when its scan fails to load
        ]
        var found: [String: Int] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
        while let path = enumerator.nextObject() as? String {
            guard path.hasSuffix(".swift") else { continue }
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            let count = source.components(separatedBy: "abilityCardImage(").count - 1
                + source.components(separatedBy: "BoardAbilityCardView(").count - 1
            if count > 0 { found[(path as NSString).lastPathComponent] = count }
        }
        XCTAssertEqual(found, allowed, "a character's card drawn without AbilityCardFace ignores the card style and size")
    }
}
