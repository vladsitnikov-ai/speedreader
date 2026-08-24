import Foundation

@MainActor
final class QuoteStore: ObservableObject {
    @Published private(set) var quotes: [Quote] = []

    private let fileManager = FileManager.default
    private let fileURL: URL

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Quotes", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("quotes.json")
        load()
    }

    @discardableResult
    func add(text: String, bookID: UUID, bookTitle: String) -> Quote {
        let quote = Quote(id: UUID(), bookID: bookID, bookTitle: bookTitle, text: text, dateAdded: Date())
        quotes.insert(quote, at: 0)
        persist()
        return quote
    }

    func delete(_ quote: Quote) {
        quotes.removeAll { $0.id == quote.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        quotes.remove(atOffsets: offsets)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        quotes = (try? decoder.decode([Quote].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(quotes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
