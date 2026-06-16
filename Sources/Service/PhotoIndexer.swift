import Foundation
import GRDB
import os.log

actor PhotoIndexer {
    static let shared = PhotoIndexer()
    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.picshurs", category: "PhotoIndexer")
    // UTC to match the v5 migration's SQL strftime (which operates in UTC) —
    // a mismatch would split photos near midnight across different dayKeys.
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private init() {
        dbQueue = DatabaseManager.shared.dbQueue
    }

    static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    func indexFolder(_ url: URL, excludedPaths: Set<String> = [], includeSubfolders: Bool = true) async {
        let folderPath = url.path

        // With subfolders off, scope the diff to direct contents only — the
        // delete pass below would otherwise treat unscanned subfolder records
        // as "removed from disk" and wipe them.
        let existingRecords: [PhotoRecord]
        do {
            existingRecords = try await dbQueue.read { db in
                if includeSubfolders {
                    return try PhotoRecord
                        .filter(Column("folderPath") == folderPath
                            || Column("folderPath").like(folderPath + "/%"))
                        .fetchAll(db)
                } else {
                    return try PhotoRecord
                        .filter(Column("folderPath") == folderPath)
                        .fetchAll(db)
                }
            }
        } catch {
            logger.error("Failed to read existing records for \(folderPath, privacy: .public): \(error, privacy: .public)")
            return
        }

        let existingByPath = Dictionary(
            uniqueKeysWithValues: existingRecords.map { ($0.url, $0) }
        )

        // Skip the expensive ImageIO/EXIF read for files whose size + mtime
        // are unchanged — they won't be written to the DB anyway.
        let diskFiles = FolderScanner.scan(url, includeSubfolders: includeSubfolders) { path, size, modDate in
            guard let existing = existingByPath[path] else { return true }
            return existing.modificationDate != modDate || existing.fileSize != size
        }
        let diskPaths = Set(diskFiles.map { $0.url.path })

        do {
            try await dbQueue.write { db in
                for file in diskFiles {
                    guard !excludedPaths.contains(file.folderPath) else { continue }
                    let path = file.url.path
                    if let existing = existingByPath[path] {
                        if existing.modificationDate != file.modificationDate
                            || existing.fileSize != file.fileSize
                        {
                            var updated = existing
                            updated.filename = file.filename
                            updated.fileSize = file.fileSize
                            updated.modificationDate = file.modificationDate
                            updated.folderPath = file.folderPath
                            updated.width = file.width.map(Double.init)
                            updated.height = file.height.map(Double.init)
                            updated.cameraModel = file.cameraModel
                            updated.lensModel = file.lensModel
                            updated.focalLength = file.focalLength
                            updated.aperture = file.aperture
                            updated.shutterSpeed = file.shutterSpeed
                            updated.iso = file.iso
                            updated.dateTakenOriginal = file.dateTakenOriginal
                            updated.latitude = file.latitude
                            updated.longitude = file.longitude
                            updated.dayKey = Self.dayKey(for: file.dateTakenOriginal ?? file.modificationDate)
                            do { try updated.update(db) } catch {
                                self.logger.error("Failed to update record for \(path, privacy: .public): \(error, privacy: .public)")
                            }
                        }
                    } else {
                        var record = PhotoRecord(
                            url: path,
                            filename: file.filename,
                            fileSize: file.fileSize,
                            modificationDate: file.modificationDate,
                            folderPath: file.folderPath,
                            dotColor: 0,
                            isPinned: false,
                            isStarred: false,
                            trayOrder: nil,
                            width: file.width.map(Double.init),
                            height: file.height.map(Double.init),
                            cameraModel: file.cameraModel,
                            lensModel: file.lensModel,
                            focalLength: file.focalLength,
                            aperture: file.aperture,
                            shutterSpeed: file.shutterSpeed,
                            iso: file.iso,
                            dateTakenOriginal: file.dateTakenOriginal,
                            dayKey: Self.dayKey(for: file.dateTakenOriginal ?? file.modificationDate),
                            latitude: file.latitude,
                            longitude: file.longitude
                        )
                        do { try record.insert(db) } catch {
                            self.logger.error("Failed to insert record for \(path, privacy: .public): \(error, privacy: .public)")
                        }
                    }
                }

                for existing in existingRecords {
                    let removedFromDisk = !diskPaths.contains(existing.url)
                    let parentExcluded = excludedPaths.contains(existing.folderPath)
                    if removedFromDisk || parentExcluded {
                        do {
                            try PhotoRecord
                                .filter(Column("url") == existing.url)
                                .deleteAll(db)
                        } catch {
                            self.logger.error("Failed to delete record for \(existing.url, privacy: .public): \(error, privacy: .public)")
                        }
                    }
                }
            }
        } catch {
            logger.error("DB write transaction failed for \(folderPath, privacy: .public): \(error, privacy: .public)")
        }
    }

    func indexAllFolders(_ folders: [LibraryFolder], excludedPaths: Set<String> = [], includeSubfolders: Bool = true) async {
        for folder in folders {
            guard let url = folder.url else { continue }
            await indexFolder(url, excludedPaths: excludedPaths, includeSubfolders: includeSubfolders)
        }
    }

    func fetchRecords(forFolderPath folderPath: String, includeSubfolders: Bool = true) async -> [PhotoRecord] {
        (try? await dbQueue.read { db in
            if includeSubfolders {
                return try PhotoRecord.filter(
                    Column("folderPath") == folderPath
                        || Column("folderPath").like(folderPath + "/%")
                ).fetchAll(db)
            } else {
                return try PhotoRecord.filter(Column("folderPath") == folderPath).fetchAll(db)
            }
        }) ?? []
    }

    func fetchAllRecords() async -> [PhotoRecord] {
        (try? await dbQueue.read { db in
            try PhotoRecord.fetchAll(db)
        }) ?? []
    }

    func fetchPinnedRecords() async -> [PhotoRecord] {
        (try? await dbQueue.read { db in
            try PhotoRecord
                .filter(Column("isPinned") == true)
                .order(
                    PhotoRecord.Columns.trayOrder.ascNullsLast,
                    PhotoRecord.Columns.id.asc
                )
                .fetchAll(db)
        }) ?? []
    }
}
