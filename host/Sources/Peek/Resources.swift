import CoreText
import Foundation

/// The resource archive sent by the dev server: "PEEKRES1", then for every file
/// a big-endian UInt16 path length, the path, a big-endian UInt32 size and the bytes.
enum ResourceArchive {
    struct Malformed: LocalizedError {
        var errorDescription: String? { "The resource archive from the dev server is malformed." }
    }

    static func unpack(_ data: Data, into folder: URL) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, String(decoding: bytes[0..<8], as: UTF8.self) == "PEEKRES1" else { throw Malformed() }
        var offset = 8

        func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, offset + count <= bytes.count else { throw Malformed() }
            defer { offset += count }
            return bytes[offset..<offset + count]
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        while offset < bytes.count {
            let nameLength = try take(2).reduce(0) { $0 << 8 | Int($1) }
            let name = String(decoding: try take(nameLength), as: UTF8.self)
            let size = try take(4).reduce(0) { $0 << 8 | Int($1) }
            let contents = try take(size)
            let parts = name.split(separator: "/")
            guard !parts.isEmpty, !parts.contains(".."), !name.hasPrefix("/") else { throw Malformed() }
            let file = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents).write(to: file)
        }
    }

    /// Makes bundled fonts usable by name, as `UIAppFonts` would in a real app.
    static func registerFonts(in folder: URL) {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}
