import Foundation

/// Extracts text from FictionBook (.fb2) files — a single XML document. "Pages" are the
/// top-level sections of the main body (chapters), reusing the same selection mechanism as EPUB.
enum FB2TextExtractor {
    enum ExtractionError: LocalizedError {
        case cannotOpen
        case noText

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                return "Couldn’t open this FB2 book."
            case .noText:
                return "No readable text was found in this FB2 book."
            }
        }
    }

    fileprivate typealias Line = (text: String, headingLevel: Int?)

    private static func parse(_ url: URL) throws -> FB2Delegate {
        guard let data = try? Data(contentsOf: url) else { throw ExtractionError.cannotOpen }
        let delegate = FB2Delegate()
        let parser = XMLParser(data: data) // honours the encoding declared in the XML prolog (e.g. windows-1251)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        let finished = parser.parse()
        // A truncated or slightly malformed file still yields whatever was read before the error.
        guard finished || !delegate.sections.isEmpty else { throw ExtractionError.cannotOpen }
        return delegate
    }

    static func quickInfo(from url: URL) throws -> (title: String, author: String, pageCount: Int) {
        let book = try parse(url)
        let title = book.bookTitle.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        guard !book.sections.isEmpty else { throw ExtractionError.noText }
        return (title, book.author, book.sections.count)
    }

    /// A short label per chapter: its title, or its first line of text, or "Chapter N".
    static func chapterTitles(from url: URL) throws -> [String] {
        let book = try parse(url)
        return book.sections.enumerated().map { index, lines in
            if let heading = lines.first(where: { $0.headingLevel != nil }) { return heading.text }
            if let first = lines.first { return String(first.text.prefix(60)) }
            return String(format: NSLocalizedString("Chapter %d", comment: "fallback chapter label"), index + 1)
        }
    }

    static func extract(from url: URL, pages: [Int]) throws -> ExtractedText {
        let book = try parse(url)
        var words: [String] = []
        var wordPages: [Int] = []
        var headings: [Heading] = []

        for index in pages where book.sections.indices.contains(index) {
            for line in book.sections[index] {
                let tokens = line.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard !tokens.isEmpty else { continue }
                if let level = line.headingLevel {
                    headings.append(Heading(title: line.text, level: level, wordIndex: words.count, pageIndex: index))
                }
                words.append(contentsOf: tokens)
                wordPages.append(contentsOf: Array(repeating: index, count: tokens.count))
            }
        }
        guard !words.isEmpty else { throw ExtractionError.noText }
        return ExtractedText(words: words, wordPageIndices: wordPages, printedPageNumbers: [:], headings: headings)
    }
}

private final class FB2Delegate: NSObject, XMLParserDelegate {
    var bookTitle: String?
    var author = ""
    var sections: [[FB2TextExtractor.Line]] = []

    private static let paragraphTags: Set<String> = ["p", "v", "subtitle", "text-author", "th", "td", "empty-line"]

    private var path: [String] = []
    private var inMainBody = false
    private var seenMainBody = false
    private var sectionDepth = 0
    private var currentSection = -1
    private var buffer = ""
    private var titleDepth = 0
    private var titleParts: [String] = []
    private var binaryDepth = 0
    private var noteLinkDepth = 0
    /// Text of the description field being read (book-title / first-name / last-name).
    private var field = ""
    private var authorSeen = false
    private var authorParts: [String: String] = [:]

    private var inTitleInfo: Bool { path.contains("title-info") }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        path.append(name)
        switch name {
        case "binary":
            binaryDepth += 1
        case "body":
            if !seenMainBody, attributeDict["name"]?.lowercased() != "notes" {
                inMainBody = true
                seenMainBody = true
            }
        case "section" where inMainBody:
            sectionDepth += 1
            if sectionDepth == 1 {
                sections.append([])
                currentSection = sections.count - 1
            }
        case "title" where inMainBody:
            flush()
            titleDepth += 1
        case "a":
            if attributeDict["type"] == "note" || attributeDict["l:type"] == "note" { noteLinkDepth += 1 }
        default:
            break
        }
        if inMainBody, FB2Delegate.paragraphTags.contains(name) { flush() }
        if inTitleInfo { field = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard binaryDepth == 0 else { return }
        if inTitleInfo, !inMainBody { field += string; return }
        guard inMainBody, noteLinkDepth == 0 else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if inMainBody, FB2Delegate.paragraphTags.contains(name) { flush() }

        switch name {
        case "binary":
            binaryDepth = max(0, binaryDepth - 1)
        case "body":
            inMainBody = false
        case "section" where inMainBody:
            sectionDepth = max(0, sectionDepth - 1)
            if sectionDepth == 0 { currentSection = -1 }
        case "title" where inMainBody:
            flush()
            titleDepth = max(0, titleDepth - 1)
            if titleDepth == 0, !titleParts.isEmpty {
                let heading = titleParts.joined(separator: " ")
                titleParts = []
                // A title before the first section is the book's own title page — not a chapter.
                if currentSection >= 0 {
                    sections[currentSection].append((heading, min(max(sectionDepth - 1, 0), 2)))
                }
            }
        case "a":
            noteLinkDepth = max(0, noteLinkDepth - 1)
        case "book-title" where inTitleInfo:
            if bookTitle == nil { bookTitle = field.trimmingCharacters(in: .whitespacesAndNewlines) }
        case "first-name", "last-name":
            if inTitleInfo, !authorSeen, path.dropLast().last == "author" {
                authorParts[name] = field.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "author":
            if inTitleInfo, !authorSeen {
                author = [authorParts["first-name"], authorParts["last-name"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                authorSeen = true
            }
        default:
            break
        }
        _ = path.popLast()
    }

    private func flush() {
        let collapsed = buffer.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let text = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !text.isEmpty else { return }
        if titleDepth > 0 {
            titleParts.append(text)
            return
        }
        if currentSection < 0 {
            sections.append([])
            currentSection = sections.count - 1
        }
        sections[currentSection].append((text, nil))
    }
}
