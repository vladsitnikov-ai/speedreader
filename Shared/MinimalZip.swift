import Foundation
import Compression

/// A minimal read-only ZIP reader — just enough to pull named entries (by path) out of an
/// EPUB container, without adding a third-party dependency. Supports the two compression
/// methods ZIP actually uses in practice: stored (0) and deflate (8).
struct MinimalZip {
    private struct Entry {
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    enum ZipError: Error {
        case notAZip
        case entryNotFound(String)
        case corruptEntry(String)
        case unsupportedCompression(String, UInt16)
    }

    /// Indexed from 0, unlike `Data`'s index (not always 0-based) — simpler and safe for the
    /// raw-offset arithmetic ZIP's binary format needs throughout this file.
    private let bytes: [UInt8]
    private let entries: [String: Entry]

    init(data: Data) throws {
        self.bytes = [UInt8](data)
        self.entries = try Self.readCentralDirectory(bytes)
    }

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    var paths: [String] { Array(entries.keys) }

    func contents(of path: String) throws -> Data {
        guard let entry = entries[path] else { throw ZipError.entryNotFound(path) }
        return try extract(entry)
    }

    func text(of path: String) throws -> String {
        let raw: Data = try contents(of: path)
        return String(data: raw, encoding: .utf8) ?? String(decoding: raw, as: UTF8.self)
    }

    // MARK: - Central directory

    /// Scans backward from the end of the file for the End Of Central Directory record, then
    /// walks the central directory it points to. The EOCD can be followed by a short free-text
    /// comment, so it isn't necessarily the very last bytes of the file.
    private static func readCentralDirectory(_ bytes: [UInt8]) throws -> [String: Entry] {
        let eocdSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let searchWindow = min(bytes.count, 66_000) // max comment length (64KB) + record size
        let searchStart = bytes.count - searchWindow
        var eocdOffset: Int?
        if searchStart >= 0, bytes.count >= 22 {
            var i = bytes.count - 22
            while i >= searchStart {
                if bytes[i] == eocdSignature[0], Array(bytes[i..<i + 4]) == eocdSignature {
                    eocdOffset = i
                    break
                }
                i -= 1
            }
        }
        guard let eocd = eocdOffset else { throw ZipError.notAZip }

        let entryCount = Int(readUInt16(bytes, at: eocd + 10))
        let centralDirOffset = Int(readUInt32(bytes, at: eocd + 16))

        var entries: [String: Entry] = [:]
        var offset = centralDirOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count, readUInt32(bytes, at: offset) == 0x02014b50 else { break }
            let compressionMethod = readUInt16(bytes, at: offset + 10)
            let compressedSize = readUInt32(bytes, at: offset + 20)
            let uncompressedSize = readUInt32(bytes, at: offset + 24)
            let nameLength = Int(readUInt16(bytes, at: offset + 28))
            let extraLength = Int(readUInt16(bytes, at: offset + 30))
            let commentLength = Int(readUInt16(bytes, at: offset + 32))
            let localHeaderOffset = readUInt32(bytes, at: offset + 42)

            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { break }
            let nameBytes = Array(bytes[nameStart..<nameStart + nameLength])
            let name = String(decoding: nameBytes, as: UTF8.self)
            entries[name] = Entry(
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            )
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    // MARK: - Extraction

    private func extract(_ entry: Entry) throws -> Data {
        let offset = Int(entry.localHeaderOffset)
        guard offset + 30 <= bytes.count, Self.readUInt32(bytes, at: offset) == 0x04034b50 else {
            throw ZipError.corruptEntry("bad local header")
        }
        let nameLength = Int(Self.readUInt16(bytes, at: offset + 26))
        let extraLength = Int(Self.readUInt16(bytes, at: offset + 28))
        let dataStart = offset + 30 + nameLength + extraLength
        let dataEnd = dataStart + Int(entry.compressedSize)
        guard dataEnd <= bytes.count else { throw ZipError.corruptEntry("truncated entry") }
        let compressed = Array(bytes[dataStart..<dataEnd])

        switch entry.compressionMethod {
        case 0:
            return Data(compressed)
        case 8:
            return try inflate(compressed, uncompressedSize: Int(entry.uncompressedSize))
        default:
            throw ZipError.unsupportedCompression("unsupported method", entry.compressionMethod)
        }
    }

    /// Raw DEFLATE (no zlib/gzip header) — Apple's Compression framework decodes this under
    /// the `COMPRESSION_ZLIB` algorithm identifier despite the name.
    private func inflate(_ compressed: [UInt8], uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        var destination = [UInt8](repeating: 0, count: uncompressedSize)
        let decodedCount = destination.withUnsafeMutableBufferPointer { destPtr -> Int in
            compressed.withUnsafeBufferPointer { srcPtr in
                compression_decode_buffer(
                    destPtr.baseAddress!, uncompressedSize,
                    srcPtr.baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == uncompressedSize else {
            throw ZipError.corruptEntry("inflate produced \(decodedCount) bytes, expected \(uncompressedSize)")
        }
        return Data(destination)
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }
}
