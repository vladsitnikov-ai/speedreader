import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class AppSettings: ObservableObject {
    @AppStorage("appTheme") var theme: AppTheme = .system
    /// Highlight the optimal-recognition-point letter and show the fixation ticks. Off by default.
    @AppStorage("highlightPivot") var highlightPivot: Bool = false
}
