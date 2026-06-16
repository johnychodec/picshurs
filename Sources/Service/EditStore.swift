import Foundation
import CryptoKit

/// Reads and writes non-destructive edit sidecar JSON files.
///
/// Sidecars are stored in `~/Library/Application Support/Picshurs/edits/`
/// with filenames derived from a SHA256 hash of the original photo path.
enum EditStore {
    private static let editsDir: URL = {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("Picshurs/edits", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            fatalError("Cannot access or create edits directory in Application Support: \(error)")
        }
    }()

    private static func sidecarURL(for photoURL: URL) -> URL {
        editsDir.appendingPathComponent("\(safeKey(for: photoURL)).json")
    }

    // SHA256 of the path gives a fixed 64-char hex filename regardless of
    // how deep or long the original path is, avoiding HFS+/APFS 255-byte limit.
    private static func safeKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.path.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func load(for photoURL: URL) -> EditPayload? {
        let url = sidecarURL(for: photoURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EditPayload.self, from: data)
    }

    /// Saves `payload` as a sidecar JSON file.
    /// - Throws: If encoding or writing the file fails, so the caller can
    ///   surface the error rather than silently losing edits.
    static func save(_ payload: EditPayload, for photoURL: URL) throws {
        let url = sidecarURL(for: photoURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    static func delete(for photoURL: URL) {
        let url = sidecarURL(for: photoURL)
        try? FileManager.default.removeItem(at: url)
    }

    static func exists(for photoURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: sidecarURL(for: photoURL).path)
    }
}
