import SwiftUI

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private struct IsCompactKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }

    var isCompact: Bool {
        get { self[IsCompactKey.self] }
        set { self[IsCompactKey.self] = newValue }
    }
}

func dynamicTypeForScale(_ scale: CGFloat) -> DynamicTypeSize {
    switch scale {
    case ..<0.9: return .small
    case ..<1.05: return .medium
    case ..<1.2: return .large
    case ..<1.4: return .xLarge
    default: return .xxLarge
    }
}
