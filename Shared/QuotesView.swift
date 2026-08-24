import SwiftUI

struct QuotesView: View {
    @ObservedObject var quotes: QuoteStore
    @State private var copiedID: UUID?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if quotes.quotes.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(quotes.quotes) { quote in
                        row(for: quote)
                    }
                    .onDelete(perform: quotes.delete)
                }
                .listStyle(.plain)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Цитатник")
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
            Text("Пока пусто")
                .font(.title2.bold())
            Text("Во время чтения нажмите на значок цитаты, чтобы сохранить текущее предложение сюда.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func row(for quote: Quote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quote.text)
                .font(.body)

            HStack {
                Text("\(quote.bookTitle) · \(Self.dateFormatter.string(from: quote.dateAdded))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyToClipboard(quote.text)
                    copiedID = quote.id
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        if copiedID == quote.id { copiedID = nil }
                    }
                } label: {
                    Label(copiedID == quote.id ? "Скопировано" : "Копировать", systemImage: copiedID == quote.id ? "checkmark" : "doc.on.doc")
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
                Label("Удалить", systemImage: "trash")
            }
        }
    }
}
