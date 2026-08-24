import SwiftUI

private enum Screen: Equatable {
    case library
    case pageSelection(Book)
    case reading(Book)
}

struct ContentView: View {
    @StateObject private var library = LibraryStore()
    @State private var screen: Screen = .library

    var body: some View {
        Group {
            switch screen {
            case .library:
                LibraryView(library: library) { book in
                    open(book)
                }

            case .pageSelection(let book):
                PageSelectionView(book: book, pdfURL: library.pdfURL(for: book)) { pages in
                    library.updateSelectedPages(pages, for: book.id)
                    if let updated = library.books.first(where: { $0.id == book.id }) {
                        screen = .reading(updated)
                    } else {
                        screen = .library
                    }
                } onCancel: {
                    screen = .library
                }

            case .reading(let book):
                ReaderContainerView(library: library, book: book) {
                    screen = .library
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 580)
        #endif
    }

    private func open(_ book: Book) {
        screen = book.isConfigured ? .reading(book) : .pageSelection(book)
    }
}

#Preview {
    ContentView()
}
