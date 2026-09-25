import SwiftUI

private enum Screen: Equatable {
    case library
    case pageSelection(UUID)
    /// `startWordIndex` opens the book at a bookmark instead of the saved position.
    case reading(UUID, startWordIndex: Int?)
}

struct ContentView: View {
    @StateObject private var library = LibraryStore()
    @StateObject private var quotes = QuoteStore()
    @StateObject private var bookmarks = BookmarkStore()
    @StateObject private var settings = AppSettings()
    @State private var isSettingsPresented = false
    @State private var selectedTab: Tab = LaunchOptions.startsOnQuotes ? .quotes : .library

    private enum Tab: Hashable { case library, quotes }

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryFlow(library: library, quotes: quotes, bookmarks: bookmarks, onOpenSettings: { isSettingsPresented = true })
                .tabItem { Label("Библиотека", systemImage: "books.vertical") }
                .tag(Tab.library)

            QuotesView(quotes: quotes, library: library)
                .tabItem { Label("Цитатник", systemImage: "quote.bubble") }
                .tag(Tab.quotes)
        }
        .environmentObject(settings)
        .preferredColorScheme(settings.theme.colorScheme)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(settings: settings) { isSettingsPresented = false }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 580)
        #endif
    }
}

private struct LibraryFlow: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var quotes: QuoteStore
    @ObservedObject var bookmarks: BookmarkStore
    let onOpenSettings: () -> Void

    @State private var screen: Screen
    @State private var bookForBookmarks: Book?

    init(library: LibraryStore, quotes: QuoteStore, bookmarks: BookmarkStore, onOpenSettings: @escaping () -> Void) {
        self.library = library
        self.quotes = quotes
        self.bookmarks = bookmarks
        self.onOpenSettings = onOpenSettings
        if LaunchOptions.openFirstBook, let book = library.books.first(where: { $0.isConfigured }) {
            _screen = State(initialValue: .reading(book.id, startWordIndex: nil))
        } else {
            _screen = State(initialValue: .library)
        }
    }

    var body: some View {
        Group {
            switch screen {
            case .library:
                LibraryView(
                    library: library,
                    bookmarks: bookmarks,
                    onOpen: { open($0) },
                    onShowBookmarks: { bookForBookmarks = $0 },
                    onOpenSettings: onOpenSettings
                )

            case .pageSelection(let id):
                // Always resolved fresh from the store rather than captured once, so a stale
                // snapshot can never overwrite a bookmark that was saved after this case was set.
                if let book = library.books.first(where: { $0.id == id }) {
                    PageSelectionView(book: book, pdfURL: library.pdfURL(for: book)) { pages in
                        library.updateSelectedPages(pages, for: book.id)
                        screen = .reading(book.id, startWordIndex: nil)
                    } onCancel: {
                        screen = .library
                    }
                } else {
                    Color.clear.onAppear { screen = .library }
                }

            case .reading(let id, let startWordIndex):
                if let book = library.books.first(where: { $0.id == id }) {
                    ReaderContainerView(
                        library: library,
                        quotes: quotes,
                        bookmarkStore: bookmarks,
                        book: book,
                        startWordIndex: startWordIndex
                    ) {
                        screen = .library
                    }
                } else {
                    Color.clear.onAppear { screen = .library }
                }
            }
        }
        .sheet(item: $bookForBookmarks) { book in
            BookmarksView(
                bookTitle: book.title,
                bookmarks: bookmarks.bookmarks(for: book.id),
                onSelect: { bookmark in
                    bookForBookmarks = nil
                    open(book, at: bookmark.wordIndex)
                },
                onRename: { bookmark, name in bookmarks.rename(bookmark, to: name) },
                onDelete: { bookmarks.delete($0) },
                onClose: { bookForBookmarks = nil }
            )
        }
    }

    private func open(_ book: Book, at wordIndex: Int? = nil) {
        screen = book.isConfigured ? .reading(book.id, startWordIndex: wordIndex) : .pageSelection(book.id)
    }
}

#Preview {
    ContentView()
}
