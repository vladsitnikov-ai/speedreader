import Foundation

/// A named place in a book the reader can jump back to.
struct Bookmark: Identifiable, Codable, Equatable {
    let id: UUID
    let bookID: UUID
    var title: String
    /// Index into the book's word list — independent of the words-per-chunk setting.
    let wordIndex: Int
    let pdfPage: Int?
    let printedPage: String?
    let dateAdded: Date

    var pageLabel: String? {
        if let printedPage { return printedPage }
        if let pdfPage { return "\(pdfPage) (PDF)" }
        return nil
    }
}

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []

    private let fileManager = FileManager.default
    private let fileURL: URL

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Bookmarks", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bookmarks.json")
        load()
    }

    /// Bookmarks of one book in reading order.
    func bookmarks(for bookID: UUID) -> [Bookmark] {
        bookmarks.filter { $0.bookID == bookID }.sorted { $0.wordIndex < $1.wordIndex }
    }

    @discardableResult
    func add(title: String, bookID: UUID, wordIndex: Int, pdfPage: Int?, printedPage: String?) -> Bookmark {
        let bookmark = Bookmark(
            id: UUID(),
            bookID: bookID,
            title: title,
            wordIndex: wordIndex,
            pdfPage: pdfPage,
            printedPage: printedPage,
            dateAdded: Date()
        )
        bookmarks.append(bookmark)
        persist()
        return bookmark
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[idx].title = title
        persist()
    }

    func delete(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    func deleteAll(for bookID: UUID) {
        bookmarks.removeAll { $0.bookID == bookID }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        bookmarks = (try? decoder.decode([Bookmark].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bookmarks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
