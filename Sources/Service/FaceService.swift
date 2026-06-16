import Foundation
import GRDB
import Vision
import ImageIO
import CoreGraphics
import os.log

/// Detects faces and clusters them into persons. Manual-triggered, throttled,
/// fully off the main actor.
///
/// Pipeline (see ARCHITECTURE notes / plan):
///   1. For each photo with `facesScanned = 0`, decode a downscaled CGImage.
///   2. `VNDetectFaceRectanglesRequest` → normalized face boxes.
///   3. Crop each face (padded) → `VNGenerateImageFeaturePrintRequest` → archive
///      the observation as a BLOB. (Feature-print on the CROP, not the whole
///      image — that is what makes the distance reflect identity, not scene.)
///   4. Greedy-cluster un-assigned faces against existing persons' representative
///      prints by `VNFeaturePrintObservation.computeDistance` (lower = closer).
///
/// Apple exposes no public face *embedding* API, so clustering is approximate —
/// expect some over-splitting, fixed by manual Merge.
actor FaceService {
    static let shared = FaceService()
    private let dbQueue = DatabaseManager.shared.dbQueue
    private let logger = Logger(subsystem: "com.picshurs", category: "FaceService")

    private init() {}

    // MARK: - Tunables

    /// Max edge for the decoded image fed to Vision — keeps RAW/huge files fast.
    private let maxAnalysisPixel = 2000
    /// Faces narrower than this many pixels (in the analysis image) are dropped.
    private let minFacePixels: CGFloat = 36
    /// Padding around the detected box before feature-printing, as a fraction of
    /// box size — context improves the descriptor.
    private let cropPadding: CGFloat = 0.3
    /// Representative prints kept per person for distance comparison.
    private let repsPerPerson = 4
    /// Distance below which a face joins an existing person. Calibrated on a real
    /// scan: `VNGenerateImageFeaturePrint` distances run ~0–1.3 here; same-face
    /// variants measured ≤0.5 while different faces sat at p05≈0.61 / median≈0.82.
    /// 0.6 catches same/near-duplicate faces without merging clearly-different
    /// ones; the over-split tail (pose/lighting) is fixed with manual Merge.
    private let clusterThreshold: Float = 0.6

    private var cancelRequested = false
    private(set) var isScanning = false

    func cancel() { cancelRequested = true }

    // MARK: - Scan

    /// Detects faces in all un-scanned photos, then re-clusters. `progress` is
    /// called as `(done, total)` on the photo-detection phase.
    func scanForFaces(progress: @Sendable @escaping (Int, Int) -> Void) async {
        guard !isScanning else { return }
        isScanning = true
        cancelRequested = false
        defer { isScanning = false }

        let urls: [String] = (try? await dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT url FROM photos WHERE facesScanned = 0")
        }) ?? []

        let total = urls.count
        logger.info("Face scan starting: \(total, privacy: .public) unscanned photos")
        var done = 0
        for urlString in urls {
            if cancelRequested { logger.info("Face scan cancelled"); break }
            await detectFaces(inPhoto: urlString)
            done += 1
            progress(done, total)
            // Yield so the system stays responsive between (heavy) photos.
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        await clusterUnassignedFaces()
        logger.info("Face scan complete: processed \(done, privacy: .public) photos")
    }

    private func detectFaces(inPhoto urlString: String) async {
        let url = URL(fileURLWithPath: urlString)
        guard let cg = downsampledImage(url: url, maxPixel: maxAnalysisPixel) else {
            // Mark scanned anyway so a permanently-undecodable file isn't retried forever.
            try? await markScanned(urlString, faces: [])
            return
        }

        let imgW = CGFloat(cg.width), imgH = CGFloat(cg.height)
        let faceBoxes: [CGRect]
        do {
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            let request = VNDetectFaceRectanglesRequest()
            // The default revision can miss occluded/tilted faces (e.g. a hand
            // over one eye). Pin to the newest model the OS supports.
            if let latest = VNDetectFaceRectanglesRequest.supportedRevisions.max() {
                request.revision = latest
            }
            try handler.perform([request])
            faceBoxes = (request.results ?? []).map(\.boundingBox)
        } catch {
            logger.error("Detect failed for \(urlString, privacy: .public): \(error, privacy: .public)")
            try? await markScanned(urlString, faces: [])
            return
        }

        var records: [FaceRecord] = []
        for box in faceBoxes {
            guard box.width * imgW >= minFacePixels else { continue }
            guard let crop = croppedFace(from: cg, box: box, imgW: imgW, imgH: imgH),
                  let printData = featurePrintData(for: crop)
            else { continue }
            records.append(FaceRecord(
                id: nil, photoURL: urlString,
                rectX: box.minX, rectY: box.minY, rectW: box.width, rectH: box.height,
                featurePrint: printData, personId: nil
            ))
        }
        try? await markScanned(urlString, faces: records)
    }

    private func markScanned(_ urlString: String, faces: [FaceRecord]) async throws {
        try await dbQueue.write { db in
            for var f in faces { try f.insert(db) }
            try db.execute(sql: "UPDATE photos SET facesScanned = 1 WHERE url = ?", arguments: [urlString])
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

    /// Crops a padded face. Vision boxes are normalized with bottom-left origin;
    /// CGImage.cropping uses top-left pixel coords, so Y is flipped.
    private func croppedFace(from cg: CGImage, box: CGRect, imgW: CGFloat, imgH: CGFloat) -> CGImage? {
        var padded = box.insetBy(dx: -box.width * cropPadding, dy: -box.height * cropPadding)
        padded = padded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let px = CGRect(
            x: padded.minX * imgW,
            y: (1 - padded.maxY) * imgH,
            width: padded.width * imgW,
            height: padded.height * imgH
        ).integral
        guard px.width >= 1, px.height >= 1 else { return nil }
        return cg.cropping(to: px)
    }

    private func featurePrintData(for crop: CGImage) -> Data? {
        do {
            let handler = VNImageRequestHandler(cgImage: crop, orientation: .up, options: [:])
            let request = VNGenerateImageFeaturePrintRequest()
            try handler.perform([request])
            guard let obs = request.results?.first as? VNFeaturePrintObservation else { return nil }
            return try NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
        } catch {
            return nil
        }
    }

    private func unarchivePrint(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    // MARK: - Clustering

    /// Greedily assigns every face with no `personId` to the nearest existing
    /// person, or creates a new person. Existing persons (and their renames /
    /// merges / hidden state) are preserved because already-assigned faces only
    /// seed representatives and are never reassigned.
    private func clusterUnassignedFaces() async {
        struct Loaded { let id: Int64; let personId: String?; let print: VNFeaturePrintObservation }

        let rows: [(Int64, String?, Data)] = (try? await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, personId, featurePrint FROM faces WHERE featurePrint IS NOT NULL ORDER BY id")
                .compactMap { row -> (Int64, String?, Data)? in
                    guard let id = row["id"] as Int64?, let data = row["featurePrint"] as Data? else { return nil }
                    return (id, row["personId"] as String?, data)
                }
        }) ?? []

        var reps: [String: [VNFeaturePrintObservation]] = [:]  // personId -> representative prints
        var unassigned: [Loaded] = []
        for (id, personId, data) in rows {
            guard let print = unarchivePrint(data) else { continue }
            if let pid = personId {
                if reps[pid, default: []].count < repsPerPerson { reps[pid, default: []].append(print) }
            } else {
                unassigned.append(Loaded(id: id, personId: nil, print: print))
            }
        }

        guard !unassigned.isEmpty else { return }
        logger.info("Clustering \(unassigned.count, privacy: .public) new faces against \(reps.count, privacy: .public) existing persons")

        var assignments: [(faceId: Int64, personId: String)] = []
        var newPersons: [(id: String, coverFaceId: Int64)] = []

        for face in unassigned {
            var bestPerson: String?
            var bestDistance = Float.greatestFiniteMagnitude
            for (pid, prints) in reps {
                for rep in prints {
                    var dist: Float = 0
                    guard (try? rep.computeDistance(&dist, to: face.print)) != nil else { continue }
                    if dist < bestDistance { bestDistance = dist; bestPerson = pid }
                }
            }
            // Debug line for threshold calibration — shows the nearest-neighbour
            // distance for every face so the constant can be tuned from real data.
            logger.debug("face \(face.id) nearest=\(bestDistance, format: .fixed(precision: 2)) threshold=\(self.clusterThreshold)")

            if let pid = bestPerson, bestDistance < clusterThreshold {
                assignments.append((face.id, pid))
                if reps[pid, default: []].count < repsPerPerson { reps[pid, default: []].append(face.print) }
            } else {
                let newId = UUID().uuidString
                reps[newId] = [face.print]
                assignments.append((face.id, newId))
                newPersons.append((newId, face.id))
            }
        }

        let personsToInsert = newPersons
        let faceAssignments = assignments
        try? await dbQueue.write { db in
            for p in personsToInsert {
                try PersonRecord(id: p.id, name: nil, isHidden: false, coverFaceId: p.coverFaceId).insert(db)
            }
            for a in faceAssignments {
                try db.execute(sql: "UPDATE faces SET personId = ? WHERE id = ?", arguments: [a.personId, a.faceId])
            }
        }
        logger.info("Clustering done: \(newPersons.count, privacy: .public) new persons")
    }

    // MARK: - Maintenance

    /// Drops all face/person data and resets the scanned flag (for a clean re-scan).
    func resetFaceData() async {
        try? await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM faces")
            try db.execute(sql: "DELETE FROM persons")
            try db.execute(sql: "UPDATE photos SET facesScanned = 0")
        }
    }
}
