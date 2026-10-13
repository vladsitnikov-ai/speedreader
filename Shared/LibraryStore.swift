import Foundation
import PDFKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []

    enum ImportError: LocalizedError {
        case cannotOpen
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                return "Couldn’t open this file."
            case .unsupportedFormat:
                return "This file type isn’t supported — add a PDF, EPUB, FB2, or plain text file."
            }
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

    func fileURL(for book: Book) -> URL {
        filesDir.appendingPathComponent("\(book.id.uuidString).\(book.format.fileExtension)")
    }

    /// Recognised (OCR) text of a PDF whose own text layer is unusable; absent for most books.
    func ocrURL(for book: Book) -> URL {
        filesDir.appendingPathComponent("\(book.id.uuidString).ocr.json")
    }

    func thumbnailURL(for book: Book) -> URL {
        thumbsDir.appendingPathComponent("\(book.id.uuidString).png")
    }

    @discardableResult
    func importBook(from sourceURL: URL) throws -> Book {
        let isZippedFB2 = sourceURL.pathExtension.lowercased() == "zip"
            && sourceURL.deletingPathExtension().pathExtension.lowercased() == "fb2"
        guard let format = isZippedFB2 ? .fb2 : BookFormat.from(fileExtension: sourceURL.pathExtension) else {
            throw ImportError.unsupportedFormat
        }

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let destURL = filesDir.appendingPathComponent("\(id.uuidString).\(format.fileExtension)")

        switch format {
        case .pdf:
            guard let document = PDFDocument(url: sourceURL) else { throw ImportError.cannotOpen }
            try copy(sourceURL, to: destURL)
            let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
                .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                ?? sourceURL.deletingPathExtension().lastPathComponent
            let author = (document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let book = Book(
                id: id, title: title, author: author, format: .pdf, pageCount: document.pageCount,
                selectedPages: [], dateAdded: Date(), bookmarkChunkIndex: 0, totalChunks: 0
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

        case .epub:
            guard let info = try? EPUBTextExtractor.quickInfo(from: sourceURL) else { throw ImportError.cannotOpen }
            try copy(sourceURL, to: destURL)
            let book = Book(
                id: id, title: info.title, author: info.author, format: .epub, pageCount: info.pageCount,
                selectedPages: [], dateAdded: Date(), bookmarkChunkIndex: 0, totalChunks: 0
            )
            books.insert(book, at: 0)
            persist()
            return book

        case .fb2:
            // A .fb2.zip holds the book as a single .fb2 entry — store it unpacked.
            if isZippedFB2 {
                guard let zip = try? MinimalZip(url: sourceURL),
                      let entry = zip.paths.first(where: { $0.lowercased().hasSuffix(".fb2") }),
                      let data = try? zip.contents(of: entry) else { throw ImportError.cannotOpen }
                try? fileManager.removeItem(at: destURL)
                try data.write(to: destURL)
            } else {
                try copy(sourceURL, to: destURL)
            }
            guard let info = try? FB2TextExtractor.quickInfo(from: destURL) else {
                try? fileManager.removeItem(at: destURL)
                throw ImportError.cannotOpen
            }
            let book = Book(
                id: id, title: info.title, author: info.author, format: .fb2, pageCount: info.pageCount,
                selectedPages: [], dateAdded: Date(), bookmarkChunkIndex: 0, totalChunks: 0
            )
            books.insert(book, at: 0)
            persist()
            return book

        case .txt:
            try copy(sourceURL, to: destURL)
            let info = TxtTextExtractor.quickInfo(from: sourceURL)
            // No meaningful page split for plain text — it's ready to read as soon as it's imported.
            let book = Book(
                id: id, title: info.title, author: "", format: .txt, pageCount: info.pageCount,
                selectedPages: [0], dateAdded: Date(), bookmarkChunkIndex: 0, totalChunks: 0
            )
            books.insert(book, at: 0)
            persist()
            return book
        }
    }

    private func copy(_ sourceURL: URL, to destURL: URL) throws {
        try? fileManager.removeItem(at: destURL)
        try fileManager.copyItem(at: sourceURL, to: destURL)
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
        try? fileManager.removeItem(at: fileURL(for: book))
        try? fileManager.removeItem(at: ocrURL(for: book))
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
