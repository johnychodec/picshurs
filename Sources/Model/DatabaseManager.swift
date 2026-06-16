import Foundation
import GRDB
import AppKit

final class DatabaseManager {
    static let shared: DatabaseManager = {
        do {
            return try DatabaseManager()
        } catch {
            DatabaseManager.handleInitError(error)
            fatalError("Picshurs could not initialize database: \(error.localizedDescription)")
        }
    }()

    static func handleInitError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Picshurs could not open its database."
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reset Database")
        alert.addButton(withTitle: "Quit")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let appSupport = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ) {
                let dbPath = appSupport.appendingPathComponent("Picshurs/picshurs.sqlite").path
                try? FileManager.default.removeItem(atPath: dbPath)
            }
        }
        NSApplication.shared.terminate(nil)
    }

    let dbQueue: DatabaseQueue

    private init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbDir = appSupport.appendingPathComponent("Picshurs")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            let dbPath = dbDir.appendingPathComponent("picshurs.sqlite").path
        dbQueue = try DatabaseQueue(path: dbPath)
        try migrate()
    }

    func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "photos") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("url", .text).notNull().unique()
                t.column("filename", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("modificationDate", .datetime).notNull()
                t.column("folderPath", .text).notNull()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("trayOrder", .integer)
                t.column("width", .double)
                t.column("height", .double)
            }

            try db.create(table: "libraryFolders") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("path", .text).notNull().unique()
                t.column("bookmarkData", .blob).notNull()
            }

            try db.create(index: "photos_on_folderPath", on: "photos", columns: ["folderPath"])
            try db.create(index: "photos_on_isPinned", on: "photos", columns: ["isPinned"])
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "photos") { t in
                t.add(column: "dotColor", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "photos_on_dotColor", on: "photos", columns: ["dotColor"])
        }

        migrator.registerMigration("v3") { db in
            try db.alter(table: "photos") { t in
                t.add(column: "cameraModel", .text)
                t.add(column: "lensModel", .text)
                t.add(column: "focalLength", .double)
                t.add(column: "aperture", .double)
                t.add(column: "shutterSpeed", .text)
                t.add(column: "iso", .integer)
                t.add(column: "dateTakenOriginal", .datetime)
            }
        }

        migrator.registerMigration("v4") { db in
            try db.alter(table: "photos") { t in
                t.add(column: "isStarred", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "photos_on_isStarred", on: "photos", columns: ["isStarred"])
        }

        migrator.registerMigration("v5") { db in
            try db.alter(table: "photos") { t in
                t.add(column: "dayKey", .text)
            }
            try db.execute(sql: """
                UPDATE photos SET dayKey = strftime('%Y-%m-%d', modificationDate)
            """)
            try db.create(
                index: "photos_on_dayKey",
                on: "photos",
                columns: ["dayKey"]
            )
            try db.create(
                index: "photos_on_filename",
                on: "photos",
                columns: ["filename"]
            )
            try db.create(
                index: "photos_on_modificationDate",
                on: "photos",
                columns: ["modificationDate"]
            )
            try db.create(
                index: "photos_on_fileSize",
                on: "photos",
                columns: ["fileSize"]
            )
        }

        // Recompute all dayKeys in UTC — earlier indexer builds wrote them in
        // local time, mismatching the v5 migration's UTC strftime.
        migrator.registerMigration("v6") { db in
            try db.execute(sql: """
                UPDATE photos SET dayKey = strftime('%Y-%m-%d', modificationDate)
            """)
        }

        // dayKey now derives from the EXIF capture date when present — file
        // copies bump modificationDate, which threw copied photos into the
        // current year's groups.
        migrator.registerMigration("v7") { db in
            try db.execute(sql: """
                UPDATE photos
                SET dayKey = strftime('%Y-%m-%d', COALESCE(dateTakenOriginal, modificationDate))
            """)
        }

        // GPS coordinates parsed from EXIF, for the Map view. Nullable — existing
        // rows stay NULL until their file is re-indexed (mtime/size change).
        migrator.registerMigration("v8") { db in
            try db.alter(table: "photos") { t in
                t.add(column: "latitude", .double)
                t.add(column: "longitude", .double)
            }
            try db.create(index: "photos_on_latitude", on: "photos", columns: ["latitude"])
        }

        // Faces: detected face rectangles + feature prints, clustered into persons.
        // `photos.facesScanned` marks a photo processed (even with 0 faces) so the
        // manual scan is incremental. Managed by FaceService.
        migrator.registerMigration("v9") { db in
            try db.create(table: "persons") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text)
                t.column("isHidden", .boolean).notNull().defaults(to: false)
                t.column("coverFaceId", .integer)
            }
            try db.create(table: "faces") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("photoURL", .text).notNull()
                t.column("rectX", .double).notNull()
                t.column("rectY", .double).notNull()
                t.column("rectW", .double).notNull()
                t.column("rectH", .double).notNull()
                t.column("featurePrint", .blob)
                t.column("personId", .text)
            }
            try db.create(index: "faces_on_photoURL", on: "faces", columns: ["photoURL"])
            try db.create(index: "faces_on_personId", on: "faces", columns: ["personId"])
            try db.alter(table: "photos") { t in
                t.add(column: "facesScanned", .boolean).notNull().defaults(to: false)
            }
        }

        // OCR: recognized text per photo, for full-text search. `ocrScanned`
        // marks a photo processed (even with no text) so the manual scan is
        // incremental. Managed by OcrService.
        migrator.registerMigration("v10") { db in
            try db.alter(table: "photos") { t in
                t.add(column: "ocrText", .text)
                t.add(column: "ocrScanned", .boolean).notNull().defaults(to: false)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
