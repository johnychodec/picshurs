import Foundation

/// Pure template engine for batch export renaming. Stateless — all functions
/// are static so they can be tested without any app state.
///
/// Supported placeholders:
///   {name}  — original filename without extension
///   {n}     — 1-based sequence counter, zero-padded to padWidth
///   {date}  — yyyy-MM-dd (UTC) capture/modification date of the photo
///   {today} — yyyy-MM-dd (UTC) day the export is run
enum ExportNamer {

    /// Naming inputs for one photo, decoupled from PhotoItem for testability.
    struct Item {
        let originalName: String   // filename without extension
        let date: Date
        let ext: String            // file extension without leading dot
    }

    // MARK: - Default templates

    /// Selection export legacy default: keep original filename.
    static let selectionDefault = "{name}"

    /// Tray export defaults: counter + export day + original name + a suffix
    /// identifying the export type.
    static let trayDefault         = "{n}_{today}_{name}_export"
    static let trayStrippedDefault = "{n}_{today}_{name}_stripped"
    static let trayWebDefault      = "{n}_{today}_{name}_web"

    // MARK: - Pure helpers

    /// Same rule as the existing tray export code: at least 3 digits.
    static func padWidth(for count: Int) -> Int {
        max(3, String(count).count)
    }

    /// Returns `raw` with leading/trailing whitespace stripped; returns
    /// `fallback` if the result is empty.
    static func effectiveTemplate(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Cleans a rendered stem for use as a macOS filename:
    /// - Replaces `/` and `:` with `-` (illegal / Finder-separator)
    /// - Strips ASCII control characters (U+0000–U+001F, U+007F)
    /// - Strips leading dots (would make file hidden)
    /// - Trims whitespace
    /// - Caps at 200 characters (leaves room for " 2" suffix and extension
    ///   within the 255-byte APFS limit)
    /// - Returns `fallback` (original name) if the result would be empty
    static func sanitize(stem: String, fallback: String) -> String {
        var s = stem
        s = s.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: ":", with: "-")
        s = s.unicodeScalars.filter { scalar in
            let v = scalar.value
            return v >= 0x20 && v != 0x7F
        }.reduce("") { $0 + String($1) }
        s = s.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s = String(s.dropFirst()) }
        if s.count > 200 { s = String(s.prefix(200)) }
        return s.isEmpty ? fallback : s
    }

    /// Renders a single stem (no extension). `index` is 1-based. `now` is the
    /// export-run timestamp backing {today}; injectable for tests.
    static func renderStem(
        template: String,
        item: Item,
        index: Int,
        padWidth: Int,
        now: Date = Date()
    ) -> String {
        var stem = template
        stem = stem.replacingOccurrences(of: "{name}", with: item.originalName)
        let padded = String(format: "%0\(padWidth)d", index)
        stem = stem.replacingOccurrences(of: "{n}", with: padded)
        stem = stem.replacingOccurrences(of: "{date}", with: PhotoIndexer.dayKey(for: item.date))
        stem = stem.replacingOccurrences(of: "{today}", with: PhotoIndexer.dayKey(for: now))
        return sanitize(stem: stem, fallback: item.originalName)
    }

    /// Renders the full batch (including extensions). Count == items.count,
    /// order preserved. Guarantees unique output names (case-insensitive)
    /// by appending " 2", " 3", … to the stem on collision.
    static func renderBatch(template: String, items: [Item], now: Date = Date()) -> [String] {
        let pw = padWidth(for: items.count)
        var used = Set<String>()   // lowercased "stem.ext"
        var results: [String] = []
        results.reserveCapacity(items.count)

        for (i, item) in items.enumerated() {
            let stem = renderStem(template: template, item: item, index: i + 1, padWidth: pw, now: now)
            let ext = item.ext.isEmpty ? "" : ".\(item.ext)"

            // Dedupe: try plain stem, then stem+" 2", stem+" 3", …
            var candidate = stem + ext
            var suffix = 2
            while used.contains(candidate.lowercased()) {
                let newStem = stem.count > 195 ? String(stem.prefix(195)) : stem
                candidate = "\(newStem) \(suffix)" + ext
                suffix += 1
            }
            used.insert(candidate.lowercased())
            results.append(candidate)
        }
        return results
    }
}
