import Foundation

struct Book: Identifiable, Equatable {
    let id: UUID
    var title: String
    var author: String = ""
    var publisher: String = ""
    var year: String = ""
    var pageCount: Int
    /// 0-based page indices to read, in reading order. Empty = not configured yet (needs page selection).
    var selectedPages: [Int]
    var dateAdded: Date
    /// Chunk index the reader stopped at last time (the bookmark).
    var bookmarkChunkIndex: Int
    /// Total chunk count as of the last save, used to compute a progress percentage.
    var totalChunks: Int

    var isConfigured: Bool { !selectedPages.isEmpty }

    var progressFraction: Double {
        guard totalChunks > 1 else { return 0 }
        return Double(bookmarkChunkIndex) / Double(totalChunks - 1)
    }

    /// "Автор. Название. Издательство, год" — whatever parts are filled in.
    var citation: String {
        var parts: [String] = []
        if !author.isEmpty { parts.append(author) }
        parts.append(title)
        let edition = [publisher, year].filter { !$0.isEmpty }.joined(separator: ", ")
        if !edition.isEmpty { parts.append(edition) }
        return parts.joined(separator: ". ")
    }
}

extension Book: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, author, publisher, year, pageCount, selectedPages, dateAdded, bookmarkChunkIndex, totalChunks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        year = try container.decodeIfPresent(String.self, forKey: .year) ?? ""
        pageCount = try container.decode(Int.self, forKey: .pageCount)
        selectedPages = try container.decode([Int].self, forKey: .selectedPages)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        bookmarkChunkIndex = try container.decode(Int.self, forKey: .bookmarkChunkIndex)
        totalChunks = try container.decode(Int.self, forKey: .totalChunks)
    }
}
