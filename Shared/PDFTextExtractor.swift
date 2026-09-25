import Foundation
import PDFKit

enum PDFTextExtractor {
    struct ExtractedText {
        let words: [String]
        /// 0-based PDF page index each word came from (same length as `words`).
        let wordPageIndices: [Int]
        /// PDF page index → page number as printed on the page, when one was detected.
        let printedPageNumbers: [Int: String]
    }

    enum ExtractionError: LocalizedError {
        case cannotOpen
        case noText

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                return "Не удалось открыть этот PDF."
            case .noText:
                return "На выбранных страницах не найден текстовый слой — вероятно, это скан без OCR."
            }
        }
    }

    /// Extracts a title and page count without reading the whole text body — used right after import.
    static func quickInfo(from url: URL) throws -> (title: String, pageCount: Int) {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpen
        }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        return (title, document.pageCount)
    }

    /// Extracts words in reading order from the given (0-based) page indices, dropping page
    /// numbers and running headers/footers, and re-joining words hyphenated across lines.
    static func extract(from url: URL, pages: [Int]) throws -> ExtractedText {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpen
        }

        var pageLines: [(page: Int, lines: [String])] = []
        for index in pages {
            guard let page = document.page(at: index) else { continue }
            let lines = (page.string ?? "")
                .replacingOccurrences(of: "\u{00AD}", with: "") // soft hyphens
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            pageLines.append((index, lines))
        }

        let runningLines = repeatedEdgeLines(in: pageLines.map(\.lines))
        var printedPageNumbers: [Int: String] = [:]
        var keptLines: [(text: String, page: Int)] = []

        for (pageIndex, lines) in pageLines {
            for (position, line) in lines.enumerated() {
                let isEdge = position < edgeLineCount || position >= lines.count - edgeLineCount
                if isEdge {
                    if let number = pageNumber(in: line) {
                        if printedPageNumbers[pageIndex] == nil { printedPageNumbers[pageIndex] = number }
                        continue
                    }
                    if runningLines.contains(normalize(line)) {
                        if printedPageNumbers[pageIndex] == nil, let number = embeddedPageNumber(in: line) {
                            printedPageNumbers[pageIndex] = number
                        }
                        continue
                    }
                }
                keptLines.append((line, pageIndex))
            }
        }

        let (words, wordPages) = tokenize(keptLines)
        guard !words.isEmpty else { throw ExtractionError.noText }
        return ExtractedText(words: words, wordPageIndices: wordPages, printedPageNumbers: printedPageNumbers)
    }

    // MARK: - Running headers / footers

    /// How many lines at the top and bottom of a page are considered header/footer territory.
    private static let edgeLineCount = 2
    /// Running headers are short; anything longer than this is treated as body text.
    private static let maxRunningLineLength = 60

    /// Normalized edge lines that show up on enough pages to be running headers or footers
    /// (book title, chapter name, author) rather than body text.
    private static func repeatedEdgeLines(in pages: [[String]]) -> Set<String> {
        guard pages.count >= 3 else { return [] }

        var frequency: [String: Int] = [:]
        for lines in pages {
            var seenOnThisPage = Set<String>()
            for (position, line) in lines.enumerated()
            where position < edgeLineCount || position >= lines.count - edgeLineCount {
                let key = normalize(line)
                guard key.count >= 2, key.count <= maxRunningLineLength,
                      seenOnThisPage.insert(key).inserted else { continue }
                frequency[key, default: 0] += 1
            }
        }

        let threshold = max(3, Int((Double(pages.count) * 0.25).rounded(.up)))
        return Set(frequency.filter { $0.value >= threshold }.keys)
    }

    /// Lowercased letters only, whitespace collapsed — so "ГЛАВА 2 · 15" and "Глава 2 · 16" compare equal.
    private static func normalize(_ line: String) -> String {
        let letters = line.lowercased().unicodeScalars
            .map { CharacterSet.letters.contains($0) ? Character($0) : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    // MARK: - Page numbers

    private static let pageNumberPattern = try! NSRegularExpression(
        pattern: #"^[\s\-–—•·|\[\]()]*(?:(?:стр|с|page|p)\.?\s*)?(\d{1,4}|[ivxlcdm]{1,8})[\s\-–—•·|\[\]()]*$"#,
        options: [.caseInsensitive]
    )

    private static let embeddedNumberPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,4})\b|\b(\d{1,4})\s*$"#
    )

    /// The number when the whole line is just a page number ("12", "— 12 —", "xiv", "стр. 12").
    private static func pageNumber(in line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pageNumberPattern.firstMatch(in: line, range: range),
              let numberRange = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[numberRange])
    }

    /// A number at the very start or end of a running header ("Глава 2 · 15" → "15").
    private static func embeddedPageNumber(in line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = embeddedNumberPattern.firstMatch(in: line, range: range) else { return nil }
        for group in 1...2 {
            if let numberRange = Range(match.range(at: group), in: line) {
                return String(line[numberRange])
            }
        }
        return nil
    }

    // MARK: - Words

    /// Splits lines into words, joining words that were hyphenated across a line break:
    /// "пере-" + "нос" → "перенос", while "Санкт-" + "Петербург" keeps its hyphen.
    private static func tokenize(_ lines: [(text: String, page: Int)]) -> ([String], [Int]) {
        var words: [String] = []
        var pages: [Int] = []
        var pending: (word: String, page: Int)?

        for (text, page) in lines {
            var tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !tokens.isEmpty else { continue }
            var tokenPages = Array(repeating: page, count: tokens.count)

            if let carried = pending {
                var head = carried.word
                if tokens[0].first?.isLowercase == true {
                    head.removeLast() // the hyphen only existed because of the line break
                }
                tokens[0] = head + tokens[0]
                tokenPages[0] = carried.page
                pending = nil
            }

            if let last = tokens.last, isHyphenatedBreak(last) {
                pending = (last, tokenPages[tokens.count - 1])
                tokens.removeLast()
                tokenPages.removeLast()
            }

            words.append(contentsOf: tokens)
            pages.append(contentsOf: tokenPages)
        }

        if let carried = pending {
            words.append(carried.word)
            pages.append(carried.page)
        }
        return (words, pages)
    }

    private static func isHyphenatedBreak(_ token: String) -> Bool {
        guard token.count >= 2, let last = token.last, last == "-" || last == "\u{2010}" else { return false }
        let beforeHyphen = token[token.index(token.endIndex, offsetBy: -2)]
        return beforeHyphen.isLetter
    }
}
