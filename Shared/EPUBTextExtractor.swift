import Foundation

/// Extracts text from EPUB files: a zip container holding an OPF package document (metadata,
/// manifest, and the spine — the chapter reading order) plus one XHTML file per chapter.
/// "Pages" here are spine indices (chapters), reusing the same page-selection mechanism PDFs use.
enum EPUBTextExtractor {
    enum ExtractionError: LocalizedError {
        case cannotOpen
        case noText

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                return "Couldn’t open this EPUB."
            case .noText:
                return "No readable chapters were found in this EPUB."
            }
        }
    }

    private struct Package {
        let title: String?
        let author: String?
        /// Zip paths of the spine's chapter files, in reading order.
        let spinePaths: [String]
    }

    static func quickInfo(from url: URL) throws -> (title: String, author: String, pageCount: Int) {
        let package = try readPackage(from: url)
        let title = package.title
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        return (title, package.author ?? "", package.spinePaths.count)
    }

    /// A short label per spine item (its first heading/line of text, or a "Chapter N" fallback),
    /// for the page-selection screen's chapter list.
    static func chapterTitles(from url: URL) throws -> [String] {
        let zip = try openZip(url)
        let package = try readPackage(from: url, zip: zip)
        return package.spinePaths.enumerated().map { index, path in
            let fallback = String(format: NSLocalizedString("Chapter %d", comment: "fallback epub chapter label"), index + 1)
            guard let xhtml = try? zip.text(of: path), let firstLine = parseChapter(xhtml).first?.text else {
                return fallback
            }
            return firstLine
        }
    }

    static func extract(from url: URL, pages: [Int]) throws -> ExtractedText {
        let zip = try openZip(url)
        let package = try readPackage(from: url, zip: zip)

        var keptLines: [(text: String, page: Int, isHeading: Bool)] = []
        for index in pages where package.spinePaths.indices.contains(index) {
            guard let xhtml = try? zip.text(of: package.spinePaths[index]) else { continue }
            for line in parseChapter(xhtml) {
                keptLines.append((line.text, index, line.isHeading))
            }
        }

        let (words, wordPages, headings) = tokenizeLines(keptLines)
        guard !words.isEmpty else { throw ExtractionError.noText }

        return ExtractedText(words: words, wordPageIndices: wordPages, printedPageNumbers: [:], headings: headings)
    }

    // MARK: - Package parsing (container.xml + the OPF it points to)

    private static func openZip(_ url: URL) throws -> MinimalZip {
        guard let zip = try? MinimalZip(url: url) else { throw ExtractionError.cannotOpen }
        return zip
    }

    private static func readPackage(from url: URL) throws -> Package {
        try readPackage(from: url, zip: try openZip(url))
    }

    private static func readPackage(from url: URL, zip: MinimalZip) throws -> Package {
        guard let containerXML = try? zip.text(of: "META-INF/container.xml") else { throw ExtractionError.cannotOpen }
        let container = ContainerParserDelegate()
        parseXML(containerXML, with: container)
        guard let opfPath = container.rootfilePath, let opfXML = try? zip.text(of: opfPath) else {
            throw ExtractionError.cannotOpen
        }

        let opfDirectory = (opfPath as NSString).deletingLastPathComponent
        let opf = OPFParserDelegate()
        parseXML(opfXML, with: opf)

        let spinePaths = opf.spineIdrefs.compactMap { idref -> String? in
            guard let href = opf.manifest[idref] else { return nil }
            return opfDirectory.isEmpty ? href : (opfDirectory as NSString).appendingPathComponent(href)
        }
        guard !spinePaths.isEmpty else { throw ExtractionError.noText }

        return Package(title: opf.title, author: opf.creator, spinePaths: spinePaths)
    }

    // MARK: - Chapter HTML → text

    private static func parseChapter(_ xhtml: String) -> [(text: String, isHeading: Bool)] {
        let delegate = ChapterParserDelegate()
        parseXML(xhtml, with: delegate)
        return delegate.lines
    }

    private static func parseXML(_ xml: String, with delegate: XMLParserDelegate) {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
    }
}

/// Strips a namespace prefix ("dc:title" → "title") — namespace processing is off, so element
/// names arrive with their raw prefix intact.
private func localName(_ qualified: String) -> String {
    guard let colon = qualified.firstIndex(of: ":") else { return qualified }
    return String(qualified[qualified.index(after: colon)...])
}

/// Reads `<rootfile full-path="…">` out of META-INF/container.xml.
private final class ContainerParserDelegate: NSObject, XMLParserDelegate {
    var rootfilePath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if rootfilePath == nil, localName(elementName) == "rootfile" {
            rootfilePath = attributeDict["full-path"]
        }
    }
}

/// Reads title/creator from `<metadata>`, the id→href manifest, and the spine's reading order.
private final class OPFParserDelegate: NSObject, XMLParserDelegate {
    var title: String?
    var creator: String?
    var manifest: [String: String] = [:]
    var spineIdrefs: [String] = []

    private var inMetadata = false
    private var currentElement = ""
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = localName(elementName)
        currentElement = name
        currentText = ""
        switch name {
        case "metadata":
            inMetadata = true
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href.removingPercentEncoding ?? href
            }
        case "itemref":
            if let idref = attributeDict["idref"] { spineIdrefs.append(idref) }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "title" || currentElement == "creator" { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        switch name {
        case "metadata":
            inMetadata = false
        case "title":
            if inMetadata, title == nil { title = currentText.trimmingCharacters(in: .whitespacesAndNewlines) }
        case "creator":
            if inMetadata, creator == nil { creator = currentText.trimmingCharacters(in: .whitespacesAndNewlines) }
        default:
            break
        }
        currentText = ""
    }
}

/// Walks a chapter's XHTML, turning block-level elements into lines and tracking whether each
/// line was inside a heading tag.
private final class ChapterParserDelegate: NSObject, XMLParserDelegate {
    private(set) var lines: [(text: String, isHeading: Bool)] = []

    private static let blockTags: Set<String> = ["p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "tr", "td"]
    private static let headingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]

    private var buffer = ""
    private var headingDepth = 0
    /// >0 inside <head> — document metadata (e.g. <title>), not visible body content.
    private var headDepth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = localName(elementName).lowercased()
        if name == "head" { headDepth += 1 }
        if Self.blockTags.contains(name) { flush() }
        if Self.headingTags.contains(name) { headingDepth += 1 }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard headDepth == 0 else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName).lowercased()
        if Self.blockTags.contains(name) { flush() }
        if Self.headingTags.contains(name) { headingDepth = max(0, headingDepth - 1) }
        if name == "head" { headDepth = max(0, headDepth - 1) }
    }

    private func flush() {
        let collapsed = buffer.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !trimmed.isEmpty else { return }
        lines.append((trimmed, headingDepth > 0 || looksLikeHeading(trimmed)))
    }
}
