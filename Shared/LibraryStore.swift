import Foundation
import PDFKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []

    enum ImportError: LocalizedError {
        case cannotOpen
        var errorDescription: String? {
            "Не удалось открыть этот PDF."
        }
    }

    private let fileManager = FileManager.default
    private let baseDir: URL
    private let indexURL: URL

    var filesDir: URL { baseDir.appendingPathComponent("Files", isDirectory: true) }
    var thumbsDir: URL { baseDir.appendingPathComponent("Thumbnails", isDirectory: true) }

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDir = docs.appendingPathComponent("Library", isDirectory: true)
        indexURL = baseDir.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: filesDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        load()
    }

    func pdfURL(for book: Book) -> URL {
        filesDir.appendingPathComponent("\(book.id.uuidString).pdf")
    }

    func thumbnailURL(for book: Book) -> URL {
        thumbsDir.appendingPathComponent("\(book.id.uuidString).png")
    }

    @discardableResult
    func importPDF(from sourceURL: URL) throws -> Book {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: sourceURL) else {
            throw ImportError.cannotOpen
        }

        let id = UUID()
        let destURL = filesDir.appendingPathComponent("\(id.uuidString).pdf")
        try? fileManager.removeItem(at: destURL)
        try fileManager.copyItem(at: sourceURL, to: destURL)

        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? sourceURL.deletingPathExtension().lastPathComponent
        let author = (document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let book = Book(
            id: id,
            title: title,
            author: author,
            pageCount: document.pageCount,
            selectedPages: [],
            dateAdded: Date(),
            bookmarkChunkIndex: 0,
            totalChunks: 0
        )

        if let page = document.page(at: 0) {
            let thumb = page.thumbnail(of: CGSize(width: 300, height: 420), for: .mediaBox)
            if let data = thumb.pngData_() {
                try? data.write(to: thumbnailURL(for: book))
            }
        }

        books.insert(book, at: 0)
        persist()
        return book
    }

    func updateSelectedPages(_ pages: [Int], for bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].selectedPages = pages.sorted()
        books[idx].bookmarkChunkIndex = 0
        books[idx].totalChunks = 0
        persist()
    }

    func updateInfo(title: String, author: String, publisher: String, year: String, for bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        if !trimmedTitle.isEmpty { books[idx].title = trimmedTitle }
        books[idx].author = author.trimmingCharacters(in: .whitespaces)
        books[idx].publisher = publisher.trimmingCharacters(in: .whitespaces)
        books[idx].year = year.trimmingCharacters(in: .whitespaces)
        persist()
    }

    func updateBookmark(chunkIndex: Int, totalChunks: Int, for bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].bookmarkChunkIndex = chunkIndex
        books[idx].totalChunks = totalChunks
        persist()
    }

    func delete(_ book: Book) {
        try? fileManager.removeItem(at: pdfURL(for: book))
        try? fileManager.removeItem(at: thumbnailURL(for: book))
        books.removeAll { $0.id == book.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        books = (try? decoder.decode([Book].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(books) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
