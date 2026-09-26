import SwiftUI
import PDFKit

/// Shows the original PDF opened at the page currently being read, with the current
/// sentence (or word, as a fallback) highlighted — for checking against the source.
struct PDFCheckView: View {
    let url: URL
    let pageIndex: Int
    let pageLabel: String?
    let sentence: String?
    let word: String?
    let title: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let pageLabel {
                    Text(String(format: NSLocalizedString("· p. %@", comment: "page label"), pageLabel))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            PDFPageViewer(url: url, pageIndex: pageIndex, sentence: sentence, word: word)
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 720)
        #endif
    }
}

#if os(macOS)
private typealias PlatformViewRepresentable = NSViewRepresentable
#else
private typealias PlatformViewRepresentable = UIViewRepresentable
#endif

private struct PDFPageViewer: PlatformViewRepresentable {
    let url: URL
    let pageIndex: Int
    /// The sentence being read; the longest findable beginning of it gets highlighted.
    let sentence: String?
    /// The word being read — the fallback when nothing of the sentence can be found.
    let word: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    #if os(macOS)
    func makeNSView(context: Context) -> PDFView { makeView(context: context) }
    func updateNSView(_ nsView: PDFView, context: Context) {}
    #else
    func makeUIView(context: Context) -> PDFView { makeView(context: context) }
    func updateUIView(_ uiView: PDFView, context: Context) {}
    #endif

    private func makeView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        guard let document = PDFDocument(url: url) else { return pdfView }
        pdfView.document = document

        guard let page = document.page(at: pageIndex) else { return pdfView }
        pdfView.go(to: page)

        // Layout has not happened yet at this point; jump to the selection once it has.
        DispatchQueue.main.async {
            pdfView.go(to: page)
            if let selection = Self.findSelection(sentence: sentence, word: word, on: page) {
                selection.color = Self.highlightColor
                pdfView.highlightedSelections = [selection]
                pdfView.go(to: selection)
            }
        }
        return pdfView
    }

    /// Searches the page text itself, tolerating line breaks and words hyphenated across
    /// lines ("бы-\nли" still matches "были"). Tries the whole sentence first, then ever
    /// shorter beginnings of it, and finally the current word alone.
    private static func findSelection(sentence: String?, word: String?, on page: PDFPage) -> PDFSelection? {
        guard let text = page.string, !text.isEmpty else { return nil }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        var candidates: [[String]] = []
        if let sentence {
            let words = sentence.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            for count in stride(from: words.count, through: 1, by: -1) {
                candidates.append(Array(words.prefix(count)))
            }
        }
        if let word, !word.isEmpty {
            candidates.append([word])
        }

        for words in candidates {
            let pattern = words.map(wordPattern).joined(separator: "\\s+")
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: fullRange) else { continue }
            if let selection = page.selection(for: match.range) {
                return selection
            }
        }
        return nil
    }

    /// A pattern for one word that also matches it split by a hyphen and line break.
    private static func wordPattern(_ word: String) -> String {
        word.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "(?:-\\s*)?")
    }

    #if os(macOS)
    private static let highlightColor = NSColor.systemYellow.withAlphaComponent(0.6)
    #else
    private static let highlightColor = UIColor.systemYellow.withAlphaComponent(0.6)
    #endif

    final class Coordinator {}
}
