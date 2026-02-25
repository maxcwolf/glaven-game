import Foundation

/// Returns the bundle containing app resources.
/// Uses Bundle.module when built via SPM, Bundle.main when built via Xcode project.
var appResourceBundle: Bundle {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle.main
    #endif
}
