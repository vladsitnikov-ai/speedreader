import Foundation

/// Extracts text from a plain .txt file. There's no meaningful page/chapter split, so a .txt
/// book is always a single "page" and skips the page-selection screen entirely.
enum TxtTextExtractor {
    enum ExtractionError: LocalizedError {
        case cannotOpen
        case noText

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                return "Couldn’t open this text file."
            case .noText:
                return "This text file appears to be empty."
            }
        }
    }

    static func quickInfo(from url: URL) -> (title: String, pageCount: Int) {
        (url.deletingPathExtension().lastPathComponent, 1)
    }

    static func extract(from url: URL) throws -> ExtractedText {
        guard let text = readText(from: url) else { throw ExtractionError.cannotOpen }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { (text: $0, page: 0, isHeading: looksLikeHeading($0)) }

        let (words, wordPages, headings) = tokenizeLines(lines)
        guard !words.isEmpty else { throw ExtractionError.noText }

        return ExtractedText(words: words, wordPageIndices: wordPages, printedPageNumbers: [:], headings: headings)
    }

    /// Tries UTF-8 first, then a couple of legacy single-byte encodings still common in
    /// older Russian text files.
    private static func readText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let windows1251 = String(data: data, encoding: .windowsCP1251) { return windows1251 }
        return String(data: data, encoding: .isoLatin1)
    }
}
