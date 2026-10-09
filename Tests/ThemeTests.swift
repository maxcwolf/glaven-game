import XCTest
import SwiftUI
@testable import GlavenGameLib

/// The menus and sheets around the board wear the board's colours, so leaving the board doesn't
/// change the look. (The other selectable themes keep their own palettes.)
final class ThemeTests: XCTestCase {

    /// Regression: the default dark theme was slate blue with a light-blue accent, while the
    /// board, town and results were warm dark brown with brass.
    func testTheDefaultDarkThemeIsTheBoards() {
        let (theme, light) = (GlavenTheme.activeTheme, GlavenTheme.isLight)
        defer { GlavenTheme.activeTheme = theme; GlavenTheme.isLight = light }
        GlavenTheme.activeTheme = "default"
        GlavenTheme.isLight = false
        XCTAssertEqual(GlavenTheme.background, BoardTheme.sheet)
        XCTAssertEqual(GlavenTheme.cardBackground, BoardTheme.raised)
        XCTAssertEqual(GlavenTheme.primaryText, BoardTheme.text)
        XCTAssertEqual(GlavenTheme.secondaryText, BoardTheme.secondaryText)
        XCTAssertEqual(GlavenTheme.accentText, BoardTheme.brass)

        GlavenTheme.activeTheme = "fh"
        XCTAssertNotEqual(GlavenTheme.background, BoardTheme.sheet, "Frosthaven keeps its cool blue")
    }
}
