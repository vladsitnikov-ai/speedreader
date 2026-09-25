import Foundation

/// Command-line flags used for screenshots and UI checks; they do nothing in normal launches.
///
///   --open-first-book   start in the reader on the first configured book of the library
///   --show-pdf          with --open-first-book: open the "check in PDF" page right away
///   --tab quotes        start on the Quotes tab
enum LaunchOptions {
    private static let arguments = CommandLine.arguments

    static let openFirstBook = arguments.contains("--open-first-book")
    static let showPDF = arguments.contains("--show-pdf")
    static let startsOnQuotes: Bool = {
        guard let index = arguments.firstIndex(of: "--tab"), index + 1 < arguments.count else { return false }
        return arguments[index + 1] == "quotes"
    }()
}
