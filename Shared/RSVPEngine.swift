import Foundation

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

    func load(words: [String], pageIndices: [Int] = [], printedPages: [Int: String] = [:]) {
        pause()
        rawWords = words
        wordPages = pageIndices.count == words.count ? pageIndices : []
        self.printedPages = printedPages
        currentIndex = 0
        rebuildChunks()
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
