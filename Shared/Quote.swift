import Foundation

struct Quote: Identifiable, Equatable {
    let id: UUID
    let bookID: UUID
    let bookTitle: String
    let text: String
    let dateAdded: Date
    /// 1-based page number inside the PDF file.
    var pdfPage: Int? = nil
    /// Page number as printed on the page itself, when it could be detected.
    var printedPage: String? = nil

    /// Printed page number if known, otherwise the PDF page marked as such.
    var pageLabel: String? {
        if let printedPage { return printedPage }
        if let pdfPage { return "\(pdfPage) (PDF)" }
        return nil
    }

    /// “Text” — Author. Title. Publisher, year, p. N
    func formatted(book: Book?) -> String {
        var result = "“\(text)” — \(book?.citation ?? bookTitle)"
        if let page = pageLabel { result += ", p. \(page)" }
        return result
    }
}

extension Quote: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, bookID, bookTitle, text, dateAdded, pdfPage, printedPage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bookID = try container.decode(UUID.self, forKey: .bookID)
        bookTitle = try container.decode(String.self, forKey: .bookTitle)
        text = try container.decode(String.self, forKey: .text)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        pdfPage = try container.decodeIfPresent(Int.self, forKey: .pdfPage)
        printedPage = try container.decodeIfPresent(String.self, forKey: .printedPage)
    }
}
