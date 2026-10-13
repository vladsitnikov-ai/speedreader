import SwiftUI

struct ReaderContainerView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var quotes: QuoteStore
    @ObservedObject var bookmarkStore: BookmarkStore
    let book: Book
    /// When set, reading starts at this word (a bookmark) instead of the saved position.
    var startWordIndex: Int? = nil
    let onClose: () -> Void

    @StateObject private var engine = RSVPEngine()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingPDF = false
    @State private var isShowingBookmarks = false
    @State private var isNamingBookmark = false
    @State private var isFindingPlace = false
    @State private var ocrProgress: (done: Int, total: Int)?
    @State private var ocrTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let ocrProgress {
                VStack(spacing: 16) {
                    ProgressView(value: Double(ocrProgress.done), total: Double(max(ocrProgress.total, 1)))
                        .frame(maxWidth: 320)
                    Text(String(format: NSLocalizedString("Recognizing text… %d of %d pages", comment: "OCR progress"), ocrProgress.done, ocrProgress.total))
                    Text("This runs on your device and can take a few minutes. Recognized text is saved, so it only happens once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Cancel") { ocrTask?.cancel() }
                }
                .padding()
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey(errorMessage))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    if canRecognizeText {
                        Button("Recognize text (OCR)", action: startOCR)
                            .buttonStyle(.borderedProminent)
                        Button("Back to library", action: onClose)
                    } else {
                        Button("Back to library", action: onClose)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            } else if isLoading {
                ProgressView("Loading text…")
                    .padding()
            } else {
                ReaderView(
                    engine: engine,
                    documentTitle: book.title,
                    bookmarks: bookmarkStore.bookmarks(for: book.id),
                    onSaveQuote: saveCurrentQuote,
                    onOpenPDF: book.format == .pdf ? openPDF : nil,
                    onAddBookmark: { engine.pause(); isNamingBookmark = true },
                    onJumpToBookmark: { engine.seek(toWordIndex: $0.wordIndex) },
                    onShowBookmarks: { engine.pause(); isShowingBookmarks = true },
                    onFindPlace: { engine.pause(); isFindingPlace = true }
                ) {
                    saveProgress()
                    onClose()
                }
            }
        }
        .sheet(isPresented: $isFindingPlace) {
            FindPlaceView(engine: engine) { wordIndex in
                isFindingPlace = false
                engine.seek(toWordIndex: wordIndex)
            } onClose: {
                isFindingPlace = false
            }
        }
        .sheet(isPresented: $isNamingBookmark) {
            BookmarkNameView(
                title: "New bookmark",
                defaultName: defaultBookmarkName(),
                pageLabel: engine.currentPageLabel
            ) { name in
                addBookmark(named: name)
                isNamingBookmark = false
            } onCancel: {
                isNamingBookmark = false
            }
        }
        .sheet(isPresented: $isShowingBookmarks) {
            BookmarksView(
                bookTitle: book.title,
                bookmarks: bookmarkStore.bookmarks(for: book.id),
                onSelect: { bookmark in
                    isShowingBookmarks = false
                    engine.seek(toWordIndex: bookmark.wordIndex)
                },
                onRename: { bookmark, name in bookmarkStore.rename(bookmark, to: name) },
                onDelete: { bookmarkStore.delete($0) },
                onClose: { isShowingBookmarks = false }
            )
        }
        .fullScreenPresentation(isPresented: $isShowingPDF) {
            PDFCheckView(
                url: library.fileURL(for: book),
                pageIndex: engine.currentPageIndex ?? 0,
                pageLabel: engine.currentPageLabel,
                sentence: engine.currentSentence(),
                word: engine.currentChunk?.text,
                title: book.title
            ) {
                isShowingPDF = false
            }
        }
        .task { await loadBook() }
        .onDisappear { saveProgress() }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active { saveProgress() }
        }
    }

    private var selectedPages: [Int] {
        book.selectedPages.isEmpty ? Array(0..<book.pageCount) : book.selectedPages
    }

    /// OCR can rescue a PDF that has no (or unreadable) text of its own.
    private var canRecognizeText: Bool {
        book.format == .pdf && lastErrorIsTextLayer
    }

    @State private var lastErrorIsTextLayer = false

    private func startOCR() {
        let url = library.fileURL(for: book)
        let cacheURL = library.ocrURL(for: book)
        let pages = selectedPages
        ocrProgress = (0, pages.count)
        ocrTask = Task.detached(priority: .userInitiated) {
            do {
                try OCRTextRecognizer.recognize(pdfURL: url, pages: pages, cacheURL: cacheURL) { done in
                    Task { @MainActor in ocrProgress = (done, pages.count) }
                }
                await MainActor.run {
                    ocrProgress = nil
                    errorMessage = nil
                    isLoading = true
                }
                await loadBook()
            } catch {
                await MainActor.run { ocrProgress = nil }
            }
        }
    }

    private func loadBook() async {
        do {
            let url = library.fileURL(for: book)
            let pages = selectedPages
            let extracted: ExtractedText
            switch book.format {
            case .pdf:
                let ocr = OCRTextRecognizer.load(from: library.ocrURL(for: book))
                extracted = try PDFTextExtractor.extract(from: url, pages: pages, ocrPages: ocr)
            case .epub:
                extracted = try EPUBTextExtractor.extract(from: url, pages: pages)
            case .fb2:
                extracted = try FB2TextExtractor.extract(from: url, pages: pages)
            case .txt:
                extracted = try TxtTextExtractor.extract(from: url)
            }
            engine.load(
                words: extracted.words,
                pageIndices: extracted.wordPageIndices,
                printedPages: extracted.printedPageNumbers,
                headings: extracted.headings
            )
            if let startWordIndex {
                engine.seek(toWordIndex: startWordIndex)
            } else {
                engine.restore(currentIndex: book.bookmarkChunkIndex)
            }
            isLoading = false
            if LaunchOptions.showPDF, book.format == .pdf {
                isShowingPDF = true
            }
        } catch {
            if let pdfError = error as? PDFTextExtractor.ExtractionError {
                lastErrorIsTextLayer = pdfError == .noText || pdfError == .corruptedTextLayer
            }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// The first few words of the current sentence, as a suggested bookmark name.
    private func defaultBookmarkName() -> String {
        let source = engine.currentSentence() ?? engine.currentChunk?.text ?? ""
        let words = source.split(whereSeparator: { $0.isWhitespace })
        let head = words.prefix(6).joined(separator: " ")
        return words.count > 6 ? head + "…" : head
    }

    private func addBookmark(named name: String) {
        guard let wordIndex = engine.currentWordIndex else { return }
        bookmarkStore.add(
            title: name,
            bookID: book.id,
            wordIndex: wordIndex,
            pdfPage: engine.currentPageIndex.map { $0 + 1 },
            printedPage: engine.currentPrintedPage
        )
    }

    private func openPDF() {
        engine.pause()
        saveProgress()
        isShowingPDF = true
    }

    private func saveProgress() {
        guard !engine.chunks.isEmpty else { return }
        library.updateBookmark(chunkIndex: engine.currentIndex, totalChunks: engine.chunks.count, for: book.id)
    }

    @discardableResult
    private func saveCurrentQuote() -> Bool {
        guard let sentence = engine.currentSentence() else { return false }
        quotes.add(
            text: sentence,
            bookID: book.id,
            bookTitle: book.title,
            pdfPage: engine.currentPageIndex.map { $0 + 1 },
            printedPage: engine.currentPrintedPage
        )
        return true
    }
}

private extension View {
    /// Full screen on iPhone and iPad (a form sheet is too small to read a PDF page),
    /// a regular sheet window on macOS.
    @ViewBuilder
    func fullScreenPresentation<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        self.sheet(isPresented: isPresented, content: content)
        #else
        self.fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}
