import Foundation
import PDFKit

enum PDFTextExtractor {
    struct ExtractedText {
        let words: [String]
        /// 0-based PDF page index each word came from (same length as `words`).
        let wordPageIndices: [Int]
        /// PDF page index → page number as printed on the page, when one was detected.
        let printedPageNumbers: [Int: String]
        /// Chapter starts: the PDF's own outline when it has one, otherwise headings spotted in the text.
        let headings: [Heading]
    }

    struct Heading {
        let title: String
        /// Nesting depth (0 = top level); always 0 for headings spotted in the text.
        let level: Int
        let wordIndex: Int
        let pageIndex: Int
    }

    enum ExtractionError: LocalizedError {
        case cannotOpen
        case noText

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                return "Couldn’t open this PDF."
            case .noText:
                return "No text layer was found on the selected pages — this is likely a scan without OCR."
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
        var keptLines: [(text: String, page: Int, isHeading: Bool)] = []
        // A chapter/part title that runs in the header on every page of that chapter is kept
        // once (so it still becomes a real chapter marker) and stripped on every later repeat.
        var seenAsHeadingOnce: Set<String> = []

        for (pageIndex, lines) in pageLines {
            for (position, line) in lines.enumerated() {
                let isEdge = position < edgeLineCount || position >= lines.count - edgeLineCount
                if isEdge {
                    if let number = pageNumber(in: line) {
                        if printedPageNumbers[pageIndex] == nil { printedPageNumbers[pageIndex] = number }
                        continue
                    }
                    let key = normalize(line)
                    if runningLines.alwaysStrip.contains(key) {
                        if printedPageNumbers[pageIndex] == nil, let number = embeddedPageNumber(in: line) {
                            printedPageNumbers[pageIndex] = number
                        }
                        continue
                    }
                    if runningLines.keepFirstAsHeading.contains(key) {
                        if seenAsHeadingOnce.contains(key) {
                            if printedPageNumbers[pageIndex] == nil, let number = embeddedPageNumber(in: line) {
                                printedPageNumbers[pageIndex] = number
                            }
                            continue
                        }
                        seenAsHeadingOnce.insert(key)
                    }
                }
                keptLines.append((line, pageIndex, looksLikeHeading(line)))
            }
        }

        let (words, wordPages, textHeadings) = tokenize(keptLines)
        guard !words.isEmpty else { throw ExtractionError.noText }

        let outline = outlineHeadings(in: document, wordPages: wordPages)
        return ExtractedText(
            words: words,
            wordPageIndices: wordPages,
            printedPageNumbers: printedPageNumbers,
            headings: outline.isEmpty ? textHeadings : outline
        )
    }

    // MARK: - Chapters

    private static let chapterPattern = try! NSRegularExpression(
        pattern: #"^\s*(глава|часть|раздел|книга|пролог|эпилог|введение|заключение|предисловие|послесловие|chapter|part|book|prologue|epilogue|introduction|conclusion|preface|afterword)\b"#,
        options: [.caseInsensitive]
    )

    /// Short lines that start like a chapter title ("Глава 3", "ЧАСТЬ ВТОРАЯ", "Пролог")
    /// or are set entirely in capitals.
    private static func looksLikeHeading(_ line: String) -> Bool {
        let words = line.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty, words.count <= 10, line.count <= 80 else { return false }
        if let last = line.last, ",;:".contains(last) { return false }

        if chapterPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
            return true
        }
        let letters = line.filter { $0.isLetter }
        guard letters.count >= 5 else { return false }
        return letters.allSatisfy { $0.isUppercase }
    }

    /// The PDF's own outline (bookmarks panel), mapped onto the first word of each entry's page.
    private static func outlineHeadings(in document: PDFDocument, wordPages: [Int]) -> [Heading] {
        guard let root = document.outlineRoot else { return [] }
        var result: [Heading] = []

        func visit(_ node: PDFOutline, level: Int) {
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { continue }
                let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty, let page = child.destination?.page {
                    let pageIndex = document.index(for: page)
                    if let wordIndex = wordPages.firstIndex(where: { $0 >= pageIndex }) {
                        result.append(Heading(title: title, level: level, wordIndex: wordIndex, pageIndex: wordPages[wordIndex]))
                    }
                }
                if level < 2 { visit(child, level: level + 1) }
            }
        }
        visit(root, level: 0)
        return result
    }

    // MARK: - Running headers / footers

    /// How many lines at the top and bottom of a page are considered header/footer territory.
    private static let edgeLineCount = 2
    /// Running headers are short; anything longer than this is treated as body text.
    private static let maxRunningLineLength = 60

    private struct RunningLines {
        /// Constant across the whole book (author name, book title) — stripped every time.
        let alwaysStrip: Set<String>
        /// A chapter/part/book title that recurs in the header or footer of consecutive pages
        /// but changes between sections (so it never reaches a book-wide frequency) — the first
        /// occurrence is kept as the chapter's own heading, every later repeat is stripped.
        let keepFirstAsHeading: Set<String>
    }

    /// A short line recurring in even just 2 pages is repeated for a reason: running headers
    /// and footers never do that by chance, unlike a coincidentally short piece of body text.
    private static let minRepeatCount = 2

    /// Normalized edge lines that show up often enough to be running headers or footers
    /// (book title, chapter name, part name, author) rather than body text.
    private static func repeatedEdgeLines(in pages: [[String]]) -> RunningLines {
        guard pages.count >= 2 else { return RunningLines(alwaysStrip: [], keepFirstAsHeading: []) }

        var frequency: [String: Int] = [:]
        var isHeadingLike: [String: Bool] = [:]
        for lines in pages {
            var seenOnThisPage = Set<String>()
            for (position, line) in lines.enumerated()
            where position < edgeLineCount || position >= lines.count - edgeLineCount {
                let key = normalize(line)
                guard key.count >= 2, key.count <= maxRunningLineLength,
                      seenOnThisPage.insert(key).inserted else { continue }
                frequency[key, default: 0] += 1
                if isHeadingLike[key] == nil { isHeadingLike[key] = looksLikeHeading(line) }
            }
        }

        // Constant headers/footers (author, book title) — needs a real majority of the book,
        // since a short line of body text could plausibly repeat once or twice by coincidence.
        let globalThreshold = max(3, Int((Double(pages.count) * 0.25).rounded(.up)))

        var alwaysStrip: Set<String> = []
        var keepFirstAsHeading: Set<String> = []
        for (key, count) in frequency {
            if count >= globalThreshold {
                alwaysStrip.insert(key)
            } else if count >= minRepeatCount, isHeadingLike[key] == true {
                // A chapter/part-like line (matches "Глава…"/"Part…" or is set in capitals)
                // repeating verbatim is a running header for that section, not a coincidence.
                keepFirstAsHeading.insert(key)
            }
        }
        return RunningLines(alwaysStrip: alwaysStrip, keepFirstAsHeading: keepFirstAsHeading)
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
    private static func tokenize(_ lines: [(text: String, page: Int, isHeading: Bool)]) -> ([String], [Int], [Heading]) {
        var words: [String] = []
        var pages: [Int] = []
        var headings: [Heading] = []
        var pending: (word: String, page: Int)?

        for (text, page, isHeading) in lines {
            var tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !tokens.isEmpty else { continue }
            var tokenPages = Array(repeating: page, count: tokens.count)

            if isHeading {
                headings.append(Heading(title: text, level: 0, wordIndex: words.count, pageIndex: page))
            }

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
        return (words, pages, headings)
    }

    private static func isHyphenatedBreak(_ token: String) -> Bool {
        guard token.count >= 2, let last = token.last, last == "-" || last == "\u{2010}" else { return false }
        let beforeHyphen = token[token.index(token.endIndex, offsetBy: -2)]
        return beforeHyphen.isLetter
    }
}
