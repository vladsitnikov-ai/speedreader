import Foundation
import PDFKit

enum PDFTextExtractor {
    enum ExtractionError: LocalizedError {
        case cannotOpen
        case noText

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                return "Не удалось открыть этот PDF."
            case .noText:
                return "На выбранных страницах не найден текстовый слой — вероятно, это скан без OCR."
            }
        }
    }

    /// Extracts a title and page count without reading the whole text body — used right after import.
    static func quickInfo(from url: URL) throws -> (title: String, pageCount: Int) {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpen
        }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        return (title, document.pageCount)
    }

    /// Extracts words in reading order from the given (0-based) page indices, in the order supplied.
    static func extractWords(from url: URL, pages: [Int]) throws -> [String] {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpen
        }

        var words: [String] = []
        for index in pages {
            guard let page = document.page(at: index) else { continue }
            let pageText = page.string ?? ""
            let pageWords = pageText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            words.append(contentsOf: pageWords)
        }

        guard !words.isEmpty else { throw ExtractionError.noText }
        return words
    }
}
