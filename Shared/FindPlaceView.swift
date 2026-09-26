import SwiftUI

/// Table of contents and full-text search in one place: with an empty query the chapters
/// are listed, otherwise the matches. Picking a row jumps there (via `onSelect`).
struct FindPlaceView: View {
    @ObservedObject var engine: RSVPEngine
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var results: [SearchHit] = []
    @FocusState private var isSearchFocused: Bool

    private static let resultLimit = 200

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Find place")
                    .font(.headline)
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            searchField
                .padding(.horizontal)
                .padding(.bottom, 10)
            Divider()

            if trimmedQuery.isEmpty {
                chapters
            } else {
                matches
            }
        }
        .onChange(of: query) { newValue in
            results = engine.search(newValue, limit: Self.resultLimit)
        }
        .onAppear { isSearchFocused = true }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 540)
        #endif
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Word or phrase", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var chapters: some View {
        if engine.chapters.isEmpty {
            hint(
                icon: "list.bullet.indent",
                title: "No table of contents",
                text: "This PDF has no built-in table of contents, and chapter headings weren't detected in the text. Type a word or phrase to find your place."
            )
        } else {
            List {
                Section {
                    ForEach(engine.chapters) { chapter in
                        Button {
                            onSelect(chapter.wordIndex)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(chapter.title)
                                    .font(chapter.level == 0 ? .body.weight(.medium) : .body)
                                    .foregroundStyle(.primary)
                                    .padding(.leading, CGFloat(chapter.level) * 16)
                                Spacer()
                                pageBadge(chapter.pageLabel)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Table of Contents")
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var matches: some View {
        if results.isEmpty {
            hint(icon: "text.magnifyingglass", title: "Nothing found", text: "Try a different word or the start of one — search matches from the beginning of a word.")
        } else {
            List {
                Section {
                    ForEach(results) { hit in
                        Button {
                            onSelect(hit.wordIndex)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                (Text(hit.before.isEmpty ? "" : hit.before + " ")
                                    + Text(hit.match).bold().foregroundColor(.accentColor)
                                    + Text(hit.after.isEmpty ? "" : " " + hit.after))
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                                Spacer()
                                pageBadge(hit.pageLabel)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    if results.count >= Self.resultLimit {
                        Text(String(format: NSLocalizedString("First %d matches", comment: "search results header, capped"), Self.resultLimit))
                    } else {
                        Text(String(format: NSLocalizedString("Found: %d", comment: "search results header, count"), results.count))
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func pageBadge(_ label: String?) -> some View {
        if let label {
            Text(String(format: NSLocalizedString("p. %@", comment: "page label"), label))
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .fixedSize()
        }
    }

    private func hint(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(title))
                .font(.title3.bold())
            Text(LocalizedStringKey(text))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}
