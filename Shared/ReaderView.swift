import SwiftUI

struct ReaderView: View {
    @ObservedObject var engine: RSVPEngine
    @EnvironmentObject private var settings: AppSettings
    let documentTitle: String
    let bookmarks: [Bookmark]
    let onSaveQuote: () -> Bool
    let onOpenPDF: () -> Void
    let onAddBookmark: () -> Void
    let onJumpToBookmark: (Bookmark) -> Void
    let onShowBookmarks: () -> Void
    let onFindPlace: () -> Void
    let onClose: () -> Void

    @State private var justSavedQuote = false

    private static let speedStep: Double = 25
    private static let speedRange: ClosedRange<Double> = 100...900

    var body: some View {
        VStack(spacing: 20) {
            header

            Spacer(minLength: 0)

            displayArea
                .frame(maxWidth: .infinity, minHeight: 140)

            Spacer(minLength: 0)

            progressBar
            transportControls
            speedControls
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var displayArea: some View {
        if let chunk = engine.currentChunk {
            ORPWordView(word: chunk.text, highlightPivot: settings.highlightPivot)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                Text("Done")
                    .font(.title2)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Label("Library", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(documentTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            HStack(spacing: 4) {
                Menu {
                    Button(action: onFindPlace) {
                        Label(engine.chapters.isEmpty ? "Find place…" : "Contents & search…", systemImage: "text.magnifyingglass")
                    }
                    .disabled(engine.currentChunk == nil)

                    Divider()

                    Button(action: onAddBookmark) {
                        Label("Add bookmark here", systemImage: "bookmark.fill")
                    }
                    .disabled(engine.currentChunk == nil)

                    if !bookmarks.isEmpty {
                        Divider()
                        ForEach(bookmarks.prefix(6)) { bookmark in
                            Button {
                                onJumpToBookmark(bookmark)
                            } label: {
                                if let page = bookmark.pageLabel {
                                    Text(String(format: NSLocalizedString("%@ · p. %@", comment: "bookmark title · page"), bookmark.title, page))
                                } else {
                                    Text(bookmark.title)
                                }
                            }
                        }
                    }

                    Divider()
                    Button(action: onShowBookmarks) {
                        Label {
                            if bookmarks.isEmpty {
                                Text("All bookmarks…")
                            } else {
                                Text(String(format: NSLocalizedString("All bookmarks (%d)…", comment: "bookmarks menu item with count"), bookmarks.count))
                            }
                        } icon: {
                            Image(systemName: "list.bullet")
                        }
                    }
                } label: {
                    Image(systemName: bookmarks.isEmpty ? "list.bullet" : "bookmark.fill")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .plainMenuStyle()
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Navigation: contents, search, bookmarks")

                Button(action: onOpenPDF) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(engine.currentChunk == nil)
                .accessibilityLabel("Open this place in the PDF")

                Button(action: saveQuote) {
                    Image(systemName: justSavedQuote ? "checkmark.circle.fill" : "quote.bubble")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(engine.currentChunk == nil)
                .accessibilityLabel("Save to quotes")
            }
        }
    }

    private func saveQuote() {
        guard onSaveQuote() else { return }
        justSavedQuote = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            justSavedQuote = false
        }
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { engine.progress },
                    set: { engine.seek(to: $0) }
                ),
                in: 0...1
            )
            HStack {
                Text("\(String(min(engine.currentIndex + 1, engine.chunks.count))) / \(String(max(engine.chunks.count, 1)))")
                if let page = engine.currentPageLabel {
                    Text(String(format: NSLocalizedString("· p. %@", comment: "page label"), page))
                }
                Spacer()
                Text(String(format: NSLocalizedString("%d wpm", comment: "words per minute"), Int(engine.wordsPerMinute)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var transportControls: some View {
        HStack(spacing: 32) {
            Button(action: engine.restart) {
                Image(systemName: "backward.end.fill")
            }
            .accessibilityLabel("Restart")
            Button(action: engine.stepBackward) {
                Image(systemName: "backward.frame.fill")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .accessibilityLabel("Previous word")
            Button(action: engine.togglePlay) {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
            }
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            Button(action: engine.stepForward) {
                Image(systemName: "forward.frame.fill")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .accessibilityLabel("Next word")
        }
        .font(.system(size: 22))
        .buttonStyle(.plain)
    }

    private var speedControls: some View {
        VStack(spacing: 10) {
            HStack {
                Button { adjustSpeed(by: -Self.speedStep) } label: {
                    Image(systemName: "tortoise.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.downArrow, modifiers: [])
                .accessibilityLabel("Slower")

                Slider(value: $engine.wordsPerMinute, in: Self.speedRange, step: 10)

                Button { adjustSpeed(by: Self.speedStep) } label: {
                    Image(systemName: "hare.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.upArrow, modifiers: [])
                .accessibilityLabel("Faster")
            }
            Stepper(
                String(format: NSLocalizedString("Words at a time: %d", comment: "words-per-chunk stepper"), engine.wordsPerChunk),
                value: $engine.wordsPerChunk,
                in: 1...4
            )
        }
    }

    private func adjustSpeed(by delta: Double) {
        let target = engine.wordsPerMinute + delta
        engine.wordsPerMinute = min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, target))
    }
}

private extension View {
    /// An icon-only menu: no button chrome on macOS, the default (already plain) look on iOS.
    @ViewBuilder
    func plainMenuStyle() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton)
        #else
        self
        #endif
    }
}
