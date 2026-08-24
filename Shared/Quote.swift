import Foundation

struct Quote: Identifiable, Codable, Equatable {
    let id: UUID
    let bookID: UUID
    let bookTitle: String
    let text: String
    let dateAdded: Date
}
