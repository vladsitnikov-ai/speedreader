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

/// The typeface RSVP words are shown in.
enum ReaderFont: String, CaseIterable, Identifiable {
    case sans
    case serif
    case mono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sans: return "Sans-serif"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .sans: return .system(size: size, weight: .semibold, design: .default)
        case .serif: return .system(size: size, weight: .semibold, design: .serif)
        case .mono: return .system(size: size, weight: .semibold, design: .monospaced)
        }
    }
}

final class AppSettings: ObservableObject {
    @AppStorage("appTheme") var theme: AppTheme = .system
    /// Highlight the optimal-recognition-point letter and show the fixation ticks. Off by default.
    @AppStorage("highlightPivot") var highlightPivot: Bool = false
    @AppStorage("readerFont") var readerFont: ReaderFont = .sans
}
