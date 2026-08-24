import Foundation

struct Book: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var pageCount: Int
    /// 0-based page indices to read, in reading order. Empty = not configured yet (needs page selection).
    var selectedPages: [Int]
    var dateAdded: Date
    /// Chunk index the reader stopped at last time (the bookmark).
    var bookmarkChunkIndex: Int
    /// Total chunk count as of the last save, used to compute a progress percentage.
    var totalChunks: Int

    var isConfigured: Bool { !selectedPages.isEmpty }

    var progressFraction: Double {
        guard totalChunks > 1 else { return 0 }
        return Double(bookmarkChunkIndex) / Double(totalChunks - 1)
    }
}
