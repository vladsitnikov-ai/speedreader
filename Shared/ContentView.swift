import SwiftUI

private enum Screen: Equatable {
    case library
    case pageSelection(UUID)
    case reading(UUID)
}

struct ContentView: View {
    @StateObject private var library = LibraryStore()
    @StateObject private var quotes = QuoteStore()
    @StateObject private var settings = AppSettings()
    @State private var isSettingsPresented = false

    var body: some View {
        TabView {
            LibraryFlow(library: library, quotes: quotes, onOpenSettings: { isSettingsPresented = true })
                .tabItem { Label("Библиотека", systemImage: "books.vertical") }

            QuotesView(quotes: quotes)
                .tabItem { Label("Цитатник", systemImage: "quote.bubble") }
        }
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
    let onOpenSettings: () -> Void

    @State private var screen: Screen = .library

    var body: some View {
        Group {
            switch screen {
            case .library:
                LibraryView(library: library, onOpen: open, onOpenSettings: onOpenSettings)

            case .pageSelection(let id):
                // Always resolved fresh from the store rather than captured once, so a stale
                // snapshot can never overwrite a bookmark that was saved after this case was set.
                if let book = library.books.first(where: { $0.id == id }) {
                    PageSelectionView(book: book, pdfURL: library.pdfURL(for: book)) { pages in
                        library.updateSelectedPages(pages, for: book.id)
                        screen = .reading(book.id)
                    } onCancel: {
                        screen = .library
                    }
                } else {
                    Color.clear.onAppear { screen = .library }
                }

            case .reading(let id):
                if let book = library.books.first(where: { $0.id == id }) {
                    ReaderContainerView(library: library, quotes: quotes, book: book) {
                        screen = .library
                    }
                } else {
                    Color.clear.onAppear { screen = .library }
                }
            }
        }
    }

    private func open(_ book: Book) {
        screen = book.isConfigured ? .reading(book.id) : .pageSelection(book.id)
    }
}

#Preview {
    ContentView()
}
