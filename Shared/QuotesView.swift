import SwiftUI

struct QuotesView: View {
    @ObservedObject var quotes: QuoteStore
    @ObservedObject var library: LibraryStore

    @State private var copiedID: UUID?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Quotes grouped by book, newest book first.
    private struct QuoteGroup: Identifiable {
        let id: UUID
        let book: Book?
        let fallbackTitle: String
        let quotes: [Quote]

        var citation: String { book?.citation ?? fallbackTitle }
    }

    private var groups: [QuoteGroup] {
        var order: [UUID] = []
        var byBook: [UUID: [Quote]] = [:]
        for quote in quotes.quotes {
            if byBook[quote.bookID] == nil { order.append(quote.bookID) }
            byBook[quote.bookID, default: []].append(quote)
        }
        return order.map { id in
            let items = byBook[id] ?? []
            return QuoteGroup(
                id: id,
                book: library.books.first { $0.id == id },
                fallbackTitle: items.first?.bookTitle ?? "",
                quotes: items
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if quotes.quotes.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.quotes) { quote in
                                row(for: quote, in: group)
                            }
                        } header: {
                            sectionHeader(for: group)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Quotes")
                .font(.largeTitle.bold())
            Spacer()
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "quote.bubble")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Nothing here yet")
                .font(.title2.bold())
            Text("While reading, tap the quote icon — the sentence will be saved here along with the book and page number.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func sectionHeader(for group: QuoteGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.citation)
                .font(.headline)
                .textCase(nil)
            Spacer()
            Button {
                copy(group.quotes.map { $0.formatted(book: group.book) }.joined(separator: "\n\n"), id: group.id)
            } label: {
                Label(copiedID == group.id ? "Copied" : "Copy all", systemImage: copiedID == group.id ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .textCase(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func row(for quote: Quote, in group: QuoteGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quote.text)
                .font(.body)

            HStack {
                if let page = quote.pageLabel {
                    Text(String(format: NSLocalizedString("p. %@", comment: "page label"), page))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                Text(Self.dateFormatter.string(from: quote.dateAdded))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy(quote.formatted(book: group.book), id: quote.id)
                } label: {
                    Label(copiedID == quote.id ? "Copied" : "Copy", systemImage: copiedID == quote.id ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
        .swipeActions {
            Button(role: .destructive) {
                quotes.delete(quote)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func copy(_ text: String, id: UUID) {
        copyToClipboard(text)
        copiedID = id
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copiedID == id { copiedID = nil }
        }
    }
}
