import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreText

enum GlavenFont {
    static let titleFamily = "PirataOne-Regular"
    static let fhTitleFamily = "GermaniaOne-Regular"
    static let bodyFamily = "SakkalMajalla-Bold"

    private static var registered = false

    static func registerFonts() {
        guard !registered else { return }
        registered = true

        let fontFiles = [
            "PirataOne-Gloomhaven.ttf",
            "germaniaone.ttf",
            "majallab.ttf"
        ]

        for filename in fontFiles {
            if let url = appResourceBundle.url(forResource: filename, withExtension: nil, subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// The signature Gloomhaven title font (PirataOne)
    static func title(size: CGFloat) -> Font {
        .custom(titleFamily, size: size)
    }

    /// Frosthaven title font (GermaniaOne)
    static func fhTitle(size: CGFloat) -> Font {
        .custom(fhTitleFamily, size: size)
    }

    /// Body text font (Majalla Bold)
    static func body(size: CGFloat) -> Font {
        .custom(bodyFamily, size: size)
    }
}
