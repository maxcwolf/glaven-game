import XCTest
import ImageIO
import SwiftData
@testable import GlavenGameLib

/// The app icon (Settings → Look): every choice has its art, its icon set and its place in the
/// project, and the choice is kept.
@MainActor
final class AppIconTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private var catalog: URL { root.appendingPathComponent("GlavenGame/Assets.xcassets") }

    func testTheCrestIsTheDefaultAndTheChoiceIsKept() throws {
        let container = try ModelContainer(for: Schema([SettingsModel.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let settings = SettingsManager(modelContext: context)
        XCTAssertEqual(settings.appIcon, .crest, "a new player has the crest")
        XCTAssertNil(AppIconChoice.crest.alternateIconName, "the crest is the primary icon")

        settings.appIcon = .elements
        settings.saveSettings()
        XCTAssertEqual(SettingsManager(modelContext: context).appIcon, .elements)

        // An icon a later version dropped falls back to the crest.
        try XCTUnwrap(context.fetch(FetchDescriptor<SettingsModel>()).first).appIcon = "gone"
        XCTAssertEqual(SettingsManager(modelContext: context).appIcon, .crest)
    }

    /// The picker's thumbnail and the Mac's Dock icon are in the bundle, drawn from a source.
    func testEveryChoiceHasItsArtAndItsSource() {
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(choice.image(), "\(choice.label): no thumbnail in Resources/Images/app-icons")
            XCTAssertNotNil(choice.image(shaped: true), "\(choice.label): no Dock icon in Resources/Images/app-icons")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/app-icons/\(choice.rawValue).svg").path),
                          "\(choice.label): no docs/app-icons/\(choice.rawValue).svg to render it from")
        }
    }

    /// iPadOS finds each alternate icon by name: an icon set in the catalog, named in project.yml.
    func testEveryAlternateIsInTheCatalogAndTheProject() throws {
        let alternates = AppIconChoice.allCases.compactMap(\.alternateIconName)
        XCTAssertEqual(Set(alternates).count, AppIconChoice.allCases.count - 1, "one primary icon, the rest alternates")

        let sets = try FileManager.default.contentsOfDirectory(atPath: catalog.path)
            .filter { $0.hasSuffix(".appiconset") }.map { String($0.dropLast(".appiconset".count)) }
        XCTAssertEqual(Set(sets), Set(alternates + ["AppIcon"]), "an icon set for each choice, and no others")

        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try XCTUnwrap(project.split(separator: "\n").first { $0.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES") })
        let named = try XCTUnwrap(line.split(separator: ":", maxSplits: 1).last)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"")))
            .split(separator: " ").map(String.init)
        XCTAssertEqual(Set(named), Set(alternates), "project.yml names every alternate icon")
    }

    /// Each set's images are there: the iPadOS icon in the Home Screen's light, dark and tinted
    /// looks — light opaque (the App Store refuses an alpha channel), dark with no background of its
    /// own (the system's gradient shows through) — and the primary set has every macOS size.
    func testEveryIconSetIsWhole() throws {
        let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
        for name in AppIconChoice.allCases.map({ $0.alternateIconName ?? "AppIcon" }) {
            let folder = catalog.appendingPathComponent("\(name).appiconset")
            let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("Contents.json")))
            let images = try XCTUnwrap((contents as? [String: Any])?["images"] as? [[String: Any]])
            var looks: Set<String> = []
            for image in images {
                let file = try XCTUnwrap(image["filename"] as? String, "\(name): a slot with no image")
                let url = folder.appendingPathComponent(file)
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "\(name): \(file) missing")
                let cgImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                guard image["platform"] as? String == "ios" else { continue }
                let look = (image["appearances"] as? [[String: String]])?.first { $0["appearance"] == "luminosity" }?["value"] ?? "light"
                looks.insert(look)
                XCTAssertEqual(cgImage.width, 1024, "\(name): \(file)")
                if look == "dark" {
                    XCTAssertFalse(opaque.contains(cgImage.alphaInfo), "\(name): the dark icon has its own background")
                } else {
                    XCTAssertTrue(opaque.contains(cgImage.alphaInfo), "\(name): \(file) has an alpha channel")
                }
            }
            XCTAssertEqual(looks, ["light", "dark", "tinted"], "\(name): an iPadOS icon for every Home Screen look")
            if name == "AppIcon" {
                let mac = images.compactMap { $0 as? [String: String] }.filter { $0["idiom"] == "mac" }
                let macSizes = Set(mac.map { "\($0["size"]!)@\($0["scale"]!)" })
                XCTAssertEqual(macSizes, Set(["16x16", "32x32", "128x128", "256x256", "512x512"].flatMap { ["\($0)@1x", "\($0)@2x"] }))
            }
        }
    }
}
