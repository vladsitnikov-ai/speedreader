import SwiftUI

struct ReaderContainerView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var quotes: QuoteStore
    let book: Book
    let onClose: () -> Void

    @StateObject private var engine = RSVPEngine()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Назад в библиотеку", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if isLoading {
                ProgressView("Загружаю текст…")
                    .padding()
            } else {
                ReaderView(engine: engine, documentTitle: book.title, onSaveQuote: saveCurrentQuote) {
                    saveProgress()
                    onClose()
                }
            }
        }
        .task { await loadBook() }
        .onDisappear { saveProgress() }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active { saveProgress() }
        }
    }

    private func loadBook() async {
        do {
            let url = library.pdfURL(for: book)
            let pages = book.selectedPages.isEmpty ? Array(0..<book.pageCount) : book.selectedPages
            let words = try PDFTextExtractor.extractWords(from: url, pages: pages)
            engine.load(words: words)
            engine.restore(currentIndex: book.bookmarkChunkIndex)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func saveProgress() {
        guard !engine.chunks.isEmpty else { return }
        library.updateBookmark(chunkIndex: engine.currentIndex, totalChunks: engine.chunks.count, for: book.id)
    }

    @discardableResult
    private func saveCurrentQuote() -> Bool {
        guard let sentence = engine.currentSentence() else { return false }
        quotes.add(text: sentence, bookID: book.id, bookTitle: book.title)
        return true
    }
}
