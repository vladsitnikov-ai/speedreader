import SwiftUI

/// The bookmarks of one book. Tapping a row jumps to it (via `onSelect`).
struct BookmarksView: View {
    let bookTitle: String
    let bookmarks: [Bookmark]
    let onSelect: (Bookmark) -> Void
    let onRename: (Bookmark, String) -> Void
    let onDelete: (Bookmark) -> Void
    let onClose: () -> Void

    @State private var bookmarkToRename: Bookmark?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bookmarks")
                        .font(.headline)
                    Text(bookTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            if bookmarks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bookmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No bookmarks yet")
                        .font(.title3.bold())
                    Text("In the reader, tap the bookmark icon → “Add bookmark here”.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                List {
                    ForEach(bookmarks) { bookmark in
                        Button {
                            onSelect(bookmark)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(Self.dateFormatter.string(from: bookmark.dateAdded))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let page = bookmark.pageLabel {
                                    Text(String(format: NSLocalizedString("p. %@", comment: "page label"), page))
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                bookmarkToRename = bookmark
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDelete(bookmark)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                onDelete(bookmark)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $bookmarkToRename) { bookmark in
            BookmarkNameView(title: "Rename bookmark", defaultName: bookmark.title, pageLabel: bookmark.pageLabel) { name in
                onRename(bookmark, name)
                bookmarkToRename = nil
            } onCancel: {
                bookmarkToRename = nil
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}

/// Asks for a bookmark's name.
struct BookmarkNameView: View {
    let title: String
    let pageLabel: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(title: String, defaultName: String, pageLabel: String?, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.pageLabel = pageLabel
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: defaultName)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Save") { onSave(trimmedName) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .padding()
            Divider()

            Form {
                Section {
                    TextField("Bookmark name", text: $name)
                        .focused($isNameFocused)
                } footer: {
                    if let pageLabel {
                        Text(String(format: NSLocalizedString("Page %@. The bookmark will bring you back to this exact word.", comment: "bookmark footer"), pageLabel))
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { isNameFocused = true }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 220)
        #endif
    }
}
