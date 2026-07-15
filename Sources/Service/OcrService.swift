import Foundation
import GRDB
import Vision
import ImageIO
import CoreGraphics
import os.log

/// Recognizes text inside photos (signs, receipts, screenshots, slides) and
/// stores it for full-text search. Manual-triggered, throttled, fully off the
/// main actor — mirrors `FaceService`'s incremental scan pattern.
///
/// Pipeline:
///   1. For each photo with `ocrScanned = 0`, decode a downscaled CGImage.
///   2. `VNRecognizeTextRequest` (.accurate, language correction) → text lines.
///   3. Join the lines and store them in `photos.ocrText`.
///
/// Photos with no text are still marked scanned (text = NULL) so a permanently
/// text-free file isn't re-OCR'd on every scan. All on-device; no model ships.
actor OcrService {
    static let shared = OcrService()
    private let dbQueue = DatabaseManager.shared.dbQueue
    private let logger = Logger(subsystem: "com.picshurs", category: "OcrService")

    private init() {}

    // MARK: - Tunables

    /// Max edge for the decoded image fed to Vision — keeps RAW/huge files fast
    /// while leaving enough resolution to read small text (signs, fine print).
    private let maxAnalysisPixel = 2500
    /// Recognized lines shorter than this (after trimming) are dropped as noise.
    private let minTextLength = 2

    private var cancelRequested = false
    private(set) var isScanning = false

    func cancel() { cancelRequested = true }

    // MARK: - Scan

    /// Recognizes text in every un-scanned photo. `progress` is `(done, total)`
    /// reported on each photo.
    func scanForText(progress: @Sendable @escaping (Int, Int) -> Void) async {
        guard !isScanning else { return }
        isScanning = true
        cancelRequested = false
        defer { isScanning = false }

        let urls: [String] = (try? await dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT url FROM photos WHERE ocrScanned = 0 AND mediaKind = ?",
                arguments: [MediaKind.image.rawValue]
            )
        }) ?? []

        let total = urls.count
        logger.info("Text scan starting: \(total, privacy: .public) unscanned photos")
        var done = 0
        for urlString in urls {
            if cancelRequested { logger.info("Text scan cancelled"); break }
            await recognizeText(inPhoto: urlString)
            done += 1
            progress(done, total)
            // Yield so the system stays responsive between (heavy) photos.
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        logger.info("Text scan complete: processed \(done, privacy: .public) photos")
    }

    private func recognizeText(inPhoto urlString: String) async {
        let url = URL(fileURLWithPath: urlString)
        guard let cg = downsampledImage(url: url, maxPixel: maxAnalysisPixel) else {
            // Mark scanned anyway so a permanently-undecodable file isn't retried forever.
            try? await store(urlString, text: "")
            return
        }

        let text: String
        do {
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap {
                $0.topCandidates(1).first?.string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { $0.count >= minTextLength }
            text = lines.joined(separator: "\n")
        } catch {
            logger.error("OCR failed for \(urlString, privacy: .public): \(error, privacy: .public)")
            try? await store(urlString, text: "")
            return
        }
        try? await store(urlString, text: text)
    }

    private func store(_ urlString: String, text: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE photos SET ocrText = ?, ocrScanned = 1 WHERE url = ?",
                arguments: [text.isEmpty ? nil : text, urlString]
            )
        }
    }

    // MARK: - Image helpers

    private func downsampledImage(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true  // bake EXIF orientation
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    // MARK: - Maintenance

    /// Clears all OCR text and resets the scanned flag (for a clean re-scan).
    func resetTextData() async {
        try? await dbQueue.write { db in
            try db.execute(sql: "UPDATE photos SET ocrText = NULL, ocrScanned = 0")
        }
    }
}
