import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    let onOpen: (Book) -> Void

    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var bookPendingDelete: Book?

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
            "Ошибка",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("ОК", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Удалить «\(bookPendingDelete?.title ?? "")»?",
            isPresented: Binding(get: { bookPendingDelete != nil }, set: { if !$0 { bookPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let book = bookPendingDelete { library.delete(book) }
                bookPendingDelete = nil
            }
            Button("Отмена", role: .cancel) { bookPendingDelete = nil }
        }
    }

    private var header: some View {
        HStack {
            Text("Библиотека")
                .font(.largeTitle.bold())
            Spacer()
            Button {
                isImporting = true
            } label: {
                Label("Добавить PDF", systemImage: "plus")
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
            Text("Пока пусто")
                .font(.title2.bold())
            Text("Добавьте PDF — можно выбрать файл на диске или из Google Диска через системный проводник.")
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
                    BookCell(book: book, thumbnailURL: library.thumbnailURL(for: book))
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(book) }
                        .contextMenu {
                            Button(role: .destructive) {
                                bookPendingDelete = book
                            } label: {
                                Label("Удалить", systemImage: "trash")
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

            if !book.isConfigured {
                Label("Выберите страницы", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if book.progressFraction > 0 {
                Text("\(Int(book.progressFraction * 100))% прочитано")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(book.selectedPages.count) стр. выбрано")
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
