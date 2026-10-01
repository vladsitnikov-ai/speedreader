import Foundation

/// The result of extracting readable text from a book file, independent of its source format.
struct ExtractedText {
    let words: [String]
    /// 0-based "page" index each word came from (same length as `words`) — a PDF page, an
    /// EPUB chapter (spine index), or always 0 for a plain text file.
    let wordPageIndices: [Int]
    /// Page index → page number as printed on the page, when one was detected (PDF only).
    let printedPageNumbers: [Int: String]
    /// Chapter starts: the source's own table of contents when it has one, otherwise headings
    /// spotted in the text.
    let headings: [Heading]
}

struct Heading {
    let title: String
    /// Nesting depth (0 = top level); always 0 for headings spotted in the text.
    let level: Int
    let wordIndex: Int
    let pageIndex: Int
}

private let chapterPattern = try! NSRegularExpression(
    pattern: #"^\s*(глава|часть|раздел|книга|пролог|эпилог|введение|заключение|предисловие|послесловие|chapter|part|book|prologue|epilogue|introduction|conclusion|preface|afterword)\b"#,
    options: [.caseInsensitive]
)

/// Short lines that start like a chapter title ("Глава 3", "ЧАСТЬ ВТОРАЯ", "Пролог")
/// or are set entirely in capitals — shared between PDF, EPUB and plain-text extraction.
func looksLikeHeading(_ line: String) -> Bool {
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

/// Splits already-cleaned lines into words, tagging the first word of each heading line.
/// Unlike PDF text, plain lines (EPUB chapters, .txt files) have no artificial line-break
/// hyphenation to undo — paragraphs are already properly reflowed.
func tokenizeLines(_ lines: [(text: String, page: Int, isHeading: Bool)]) -> ([String], [Int], [Heading]) {
    var words: [String] = []
    var pages: [Int] = []
    var headings: [Heading] = []

    for (text, page, isHeading) in lines {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { continue }
        if isHeading {
            headings.append(Heading(title: text, level: 0, wordIndex: words.count, pageIndex: page))
        }
        words.append(contentsOf: tokens)
        pages.append(contentsOf: Array(repeating: page, count: tokens.count))
    }
    return (words, pages, headings)
}
