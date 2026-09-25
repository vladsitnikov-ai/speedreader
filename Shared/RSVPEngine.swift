import Foundation

/// A chapter or section start, for the table of contents.
struct Chapter: Identifiable, Equatable {
    var id: Int { wordIndex }
    let title: String
    /// Nesting depth in the PDF outline (0 = top level).
    let level: Int
    let wordIndex: Int
    let pageLabel: String?
}

/// One text-search match with a little context around it.
struct SearchHit: Identifiable {
    var id: Int { wordIndex }
    let wordIndex: Int
    let before: String
    let match: String
    let after: String
    let pageLabel: String?
}

struct Chunk: Identifiable {
    let id: Int
    let text: String
    let wordCount: Int
    /// Index range into the engine's flat word list, used to reconstruct surrounding context (e.g. for quotes).
    let startWordIndex: Int
    let endWordIndex: Int
}

@MainActor
final class RSVPEngine: ObservableObject {
    @Published private(set) var chunks: [Chunk] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published var wordsPerMinute: Double = 300

    @Published var wordsPerChunk: Int = 1 {
        didSet {
            guard oldValue != wordsPerChunk else { return }
            rebuildChunks()
        }
    }

    private var rawWords: [String] = []
    /// PDF page index for each word in `rawWords` (empty when the source has no page info).
    private var wordPages: [Int] = []
    /// PDF page index → page number as printed on the page.
    private var printedPages: [Int: String] = [:]
    private(set) var chapters: [Chapter] = []
    /// Lazily built search index: all words lowercased and stripped of edge punctuation,
    /// space-separated, plus the UTF-16 offset where each word starts.
    private var searchText: NSString?
    private var searchWordOffsets: [Int] = []
    private var workItem: DispatchWorkItem?

    var progress: Double {
        guard chunks.count > 1 else { return 0 }
        return Double(currentIndex) / Double(chunks.count - 1)
    }

    var currentChunk: Chunk? {
        guard chunks.indices.contains(currentIndex) else { return nil }
        return chunks[currentIndex]
    }

    var totalWordCount: Int { rawWords.count }
    var isFinished: Bool { !chunks.isEmpty && currentIndex >= chunks.count - 1 }

    /// Index into the word list of the first word on screen.
    var currentWordIndex: Int? { currentChunk?.startWordIndex }

    /// Jumps to the chunk containing the given word (a bookmark), pausing playback.
    func seek(toWordIndex wordIndex: Int) {
        pause()
        guard !chunks.isEmpty else { return }
        if let index = chunks.firstIndex(where: { $0.startWordIndex <= wordIndex && wordIndex < $0.endWordIndex }) {
            currentIndex = index
        } else {
            currentIndex = wordIndex < 0 ? 0 : chunks.count - 1
        }
    }

    /// 0-based PDF page index of the word currently on screen.
    var currentPageIndex: Int? {
        guard let chunk = currentChunk, wordPages.indices.contains(chunk.startWordIndex) else { return nil }
        return wordPages[chunk.startWordIndex]
    }

    /// Page number as printed on the current page, if it was detected.
    var currentPrintedPage: String? {
        currentPageIndex.flatMap { printedPages[$0] }
    }

    /// Printed page number when known, otherwise the 1-based PDF page — for the progress label.
    var currentPageLabel: String? {
        guard let index = currentPageIndex else { return nil }
        return printedPages[index] ?? "\(index + 1)"
    }

    func load(
        words: [String],
        pageIndices: [Int] = [],
        printedPages: [Int: String] = [:],
        headings: [PDFTextExtractor.Heading] = []
    ) {
        pause()
        rawWords = words
        wordPages = pageIndices.count == words.count ? pageIndices : []
        self.printedPages = printedPages
        searchText = nil
        searchWordOffsets = []
        currentIndex = 0
        rebuildChunks()
        chapters = headings.map {
            Chapter(title: $0.title, level: $0.level, wordIndex: $0.wordIndex, pageLabel: pageLabel(forWordIndex: $0.wordIndex))
        }
    }

    /// Printed page number when known, otherwise the 1-based PDF page, for any word.
    func pageLabel(forWordIndex wordIndex: Int) -> String? {
        guard wordPages.indices.contains(wordIndex) else { return nil }
        let page = wordPages[wordIndex]
        return printedPages[page] ?? "\(page + 1)"
    }

    // MARK: - Search

    /// Finds every place the phrase occurs (matching from the start of a word, so "дожд"
    /// also finds "дождя"), with a few words of context on each side.
    func search(_ rawQuery: String, limit: Int = 200) -> [SearchHit] {
        let queryWords = rawQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map { Self.searchable(String($0)) }
            .filter { !$0.isEmpty }
        guard !queryWords.isEmpty else { return [] }
        let query = queryWords.joined(separator: " ")

        if searchText == nil { buildSearchIndex() }
        guard let text = searchText, text.length > 0 else { return [] }

        var hits: [SearchHit] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while hits.count < limit {
            let found = text.range(of: query, options: [.diacriticInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }
            let wordIndex = wordIndex(atOffset: found.location)
            if searchWordOffsets[wordIndex] == found.location {
                hits.append(makeHit(at: wordIndex, wordCount: queryWords.count))
            }
            let next = found.location + max(found.length, 1)
            guard next < text.length else { break }
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return hits
    }

    private static func searchable(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    private func buildSearchIndex() {
        var text = ""
        text.reserveCapacity(rawWords.count * 8)
        var offsets: [Int] = []
        offsets.reserveCapacity(rawWords.count)
        var length = 0
        for (index, word) in rawWords.enumerated() {
            if index > 0 {
                text.append(" ")
                length += 1
            }
            offsets.append(length)
            let cleaned = Self.searchable(word)
            text.append(cleaned)
            length += cleaned.utf16.count
        }
        searchText = text as NSString
        searchWordOffsets = offsets
    }

    /// The word whose start offset is the last one at or before `offset`.
    private func wordIndex(atOffset offset: Int) -> Int {
        var low = 0
        var high = searchWordOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if searchWordOffsets[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private func makeHit(at wordIndex: Int, wordCount: Int) -> SearchHit {
        let matchEnd = min(wordIndex + wordCount, rawWords.count)
        let before = rawWords[max(0, wordIndex - 5)..<wordIndex].joined(separator: " ")
        let match = rawWords[wordIndex..<matchEnd].joined(separator: " ")
        let after = rawWords[matchEnd..<min(matchEnd + 6, rawWords.count)].joined(separator: " ")
        return SearchHit(wordIndex: wordIndex, before: before, match: match, after: after, pageLabel: pageLabel(forWordIndex: wordIndex))
    }

    /// Jumps to a previously saved position (bookmark) without starting playback.
    func restore(currentIndex: Int) {
        pause()
        self.currentIndex = chunks.isEmpty ? 0 : min(max(currentIndex, 0), chunks.count - 1)
    }

    private func rebuildChunks() {
        let wasPlaying = isPlaying
        pause()

        var result: [Chunk] = []
        var i = 0
        var idCounter = 0
        while i < rawWords.count {
            let end = min(i + wordsPerChunk, rawWords.count)
            let slice = rawWords[i..<end]
            result.append(Chunk(
                id: idCounter,
                text: slice.joined(separator: " "),
                wordCount: slice.count,
                startWordIndex: i,
                endWordIndex: end
            ))
            idCounter += 1
            i = end
        }
        chunks = result

        currentIndex = min(currentIndex, max(chunks.count - 1, 0))
        if wasPlaying { play() }
    }

    func play() {
        guard !chunks.isEmpty else { return }
        if currentIndex >= chunks.count - 1 { currentIndex = 0 }
        isPlaying = true
        scheduleNext()
    }

    func pause() {
        isPlaying = false
        workItem?.cancel()
        workItem = nil
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func stepForward() {
        pause()
        guard currentIndex < chunks.count - 1 else { return }
        currentIndex += 1
    }

    func stepBackward() {
        pause()
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func seek(to fraction: Double) {
        pause()
        guard !chunks.isEmpty else { return }
        let idx = Int((fraction * Double(chunks.count - 1)).rounded())
        currentIndex = min(max(idx, 0), chunks.count - 1)
    }

    func restart() {
        pause()
        currentIndex = 0
    }

    /// The sentence surrounding the current word — used by the "save to quotes" button.
    func currentSentence() -> String? {
        guard let chunk = currentChunk, rawWords.indices.contains(chunk.startWordIndex) else { return nil }

        var start = chunk.startWordIndex
        while start > 0, !endsSentence(rawWords[start - 1]) {
            start -= 1
        }

        var end = chunk.startWordIndex
        while end < rawWords.count - 1, !endsSentence(rawWords[end]) {
            end += 1
        }

        return rawWords[start...end].joined(separator: " ")
    }

    private func endsSentence(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespaces).last else { return false }
        return ".!?".contains(last)
    }

    private func interval(for chunk: Chunk) -> TimeInterval {
        let baseWordInterval = 60.0 / max(wordsPerMinute, 30)
        var multiplier = Double(chunk.wordCount)

        let trimmed = chunk.text.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last {
            if ".!?".contains(last) {
                multiplier += 1.4
            } else if ",;:".contains(last) {
                multiplier += 0.6
            }
        }
        if trimmed.count > 9 { multiplier += 0.2 }

        return baseWordInterval * multiplier
    }

    private func scheduleNext() {
        guard isPlaying, let chunk = currentChunk else { return }
        let delay = interval(for: chunk)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying else { return }
            if self.currentIndex < self.chunks.count - 1 {
                self.currentIndex += 1
                self.scheduleNext()
            } else {
                self.pause()
            }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
