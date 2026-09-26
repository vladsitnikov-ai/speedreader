import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var bookmarks: BookmarkStore
    let onOpen: (Book) -> Void
    let onShowBookmarks: (Book) -> Void
    let onOpenSettings: () -> Void

    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var bookPendingDelete: Book?
    @State private var bookForInfo: Book?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if library.books.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            "Error",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(LocalizedStringKey(errorMessage ?? ""))
        }
        .confirmationDialog(
            String(format: NSLocalizedString("Delete “%@”?", comment: "confirm delete book"), bookPendingDelete?.title ?? ""),
            isPresented: Binding(get: { bookPendingDelete != nil }, set: { if !$0 { bookPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let book = bookPendingDelete { library.delete(book) }
                bookPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { bookPendingDelete = nil }
        }
        .sheet(item: $bookForInfo) { book in
            BookInfoView(book: book) { title, author, publisher, year in
                library.updateInfo(title: title, author: author, publisher: publisher, year: year, for: book.id)
                bookForInfo = nil
            } onCancel: {
                bookForInfo = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Library")
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 12)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            Button {
                isImporting = true
            } label: {
                Label("Add PDF", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Nothing here yet")
                .font(.title2.bold())
            Text("Add a PDF — pick a file on disk or from Google Drive via the system file picker.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 24) {
                ForEach(library.books) { book in
                    BookCell(
                        book: book,
                        thumbnailURL: library.thumbnailURL(for: book),
                        bookmarkCount: bookmarks.bookmarks(for: book.id).count
                    )
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(book) }
                        .contextMenu {
                            Button {
                                onOpen(book)
                            } label: {
                                Label("Read", systemImage: "book")
                            }
                            Button {
                                onShowBookmarks(book)
                            } label: {
                                Label("Bookmarks…", systemImage: "bookmark")
                            }
                            Button {
                                bookForInfo = book
                            } label: {
                                Label("Edition details…", systemImage: "info.circle")
                            }
                            Divider()
                            Button(role: .destructive) {
                                bookPendingDelete = book
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let book = try library.importPDF(from: url)
                onOpen(book)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct BookCell: View {
    let book: Book
    let thumbnailURL: URL
    var bookmarkCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                cover
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if book.isConfigured && book.progressFraction > 0 {
                    ProgressView(value: book.progressFraction)
                        .tint(.accentColor)
                        .padding(6)
                }
            }

            Text(book.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            if !book.author.isEmpty {
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !book.isConfigured {
                Label("Choose pages", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if book.progressFraction > 0 {
                Text(String(format: NSLocalizedString("%d%% read", comment: "reading progress"), Int(book.progressFraction * 100)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: NSLocalizedString("%d pages selected", comment: "pages selected count"), book.selectedPages.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if bookmarkCount > 0 {
                Label("\(bookmarkCount)", systemImage: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        #if os(macOS)
        if let image = NSImage(contentsOf: thumbnailURL) {
            Image(platformImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            placeholder
        }
        #else
        if let data = try? Data(contentsOf: thumbnailURL), let image = UIImage(data: data) {
            Image(platformImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            placeholder
        }
        #endif
    }

    private var placeholder: some View {
        Image(systemName: "doc.text")
            .font(.system(size: 36))
            .foregroundStyle(.secondary)
    }
}
