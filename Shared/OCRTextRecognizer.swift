import Foundation
import PDFKit
import Vision
import CoreGraphics

/// On-device text recognition (Apple Vision) for PDFs whose own text layer is missing or
/// unreadable — scans, or files with a broken font encoding. Recognised lines are cached per
/// page next to the book, so the work is done once.
enum OCRTextRecognizer {
    enum OCRError: LocalizedError {
        case cannotOpen

        var errorDescription: String? {
            "Couldn’t open this PDF."
        }
    }

    /// Page index → recognised lines, top to bottom.
    static func load(from cacheURL: URL) -> [Int: [String]] {
        guard let data = try? Data(contentsOf: cacheURL),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, lines in Int(key).map { ($0, lines) } })
    }

    /// Recognises the given pages one by one (skipping those already cached), saving the cache
    /// every few pages so an interrupted run keeps its progress. Blocking — call from a
    /// background task; stops early if that task is cancelled. `progress` gets the number of
    /// pages finished so far.
    static func recognize(pdfURL: URL, pages: [Int], cacheURL: URL, progress: @Sendable (Int) -> Void) throws {
        guard let document = PDFDocument(url: pdfURL) else { throw OCRError.cannotOpen }
        var cache = load(from: cacheURL)
        var sinceSave = 0

        for (done, index) in pages.enumerated() {
            try Task.checkCancellation()
            if cache[index] == nil, let page = document.page(at: index) {
                cache[index] = recognizeLines(on: page)
                sinceSave += 1
                if sinceSave >= 5 { save(cache, to: cacheURL); sinceSave = 0 }
            }
            progress(done + 1)
        }
        save(cache, to: cacheURL)
    }

    private static func save(_ cache: [Int: [String]], to url: URL) {
        let raw = Dictionary(uniqueKeysWithValues: cache.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(raw) { try? data.write(to: url, options: .atomic) }
    }

    private static func recognizeLines(on page: PDFPage) -> [String] {
        guard let image = render(page) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ru-RU", "en-US"]
        if #available(iOS 16.0, macOS 13.0, *) { request.automaticallyDetectsLanguage = true }

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return []
        }
        // Vision's origin is bottom-left: higher midY = higher on the page.
        let observations = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    /// Draws the page onto a white bitmap whose long edge is ~2400px — enough detail for
    /// body text without ballooning memory on large pages.
    private static func render(_ page: PDFPage, longEdge: CGFloat = 2400) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = longEdge / max(box.width, box.height)
        let width = max(Int(box.width * scale), 1)
        let height = max(Int(box.height * scale), 1)

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
