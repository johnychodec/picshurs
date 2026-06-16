import Foundation

@Observable
final class AppSettings {
    // MARK: — General
    var confirmBeforeTrash: Bool {
        get { _confirmBeforeTrash }
        set { _confirmBeforeTrash = newValue; sync() }
    }
    var showFilenameLabels: Bool {
        get { _showFilenameLabels }
        set { _showFilenameLabels = newValue; sync() }
    }
    var defaultThumbnailSize: Double {
        get { _defaultThumbnailSize }
        set { _defaultThumbnailSize = newValue; sync() }
    }
    var preserveAspectRatio: Bool {
        get { _preserveAspectRatio }
        set { _preserveAspectRatio = newValue; sync() }
    }
    var trayThumbnailSize: Double {
        get { _trayThumbnailSize }
        set { _trayThumbnailSize = newValue; sync() }
    }
    var trayVisibleRows: Int {
        get { _trayVisibleRows }
        set { _trayVisibleRows = newValue; sync() }
    }

    // MARK: — Features
    /// When false, the Map view is hidden from the sidebar.
    var enableMap: Bool {
        get { _enableMap }
        set { _enableMap = newValue; sync() }
    }
    /// When false, the People/Faces feature is hidden from the sidebar.
    var enableFaces: Bool {
        get { _enableFaces }
        set { _enableFaces = newValue; sync() }
    }

    // MARK: — Library
    /// When false, adding a folder indexes only its direct contents —
    /// subfolders are not added automatically.
    var includeSubfolders: Bool {
        get { _includeSubfolders }
        set { _includeSubfolders = newValue; sync() }
    }

    // MARK: — Export Templates
    /// Last-used filename template for selection exports. Empty = legacy default.
    var exportTemplateSelection: String {
        get { _exportTemplateSelection }
        set { _exportTemplateSelection = newValue; sync() }
    }
    /// Last-used filename template for plain tray exports. Empty = default.
    var exportTemplateTray: String {
        get { _exportTemplateTray }
        set { _exportTemplateTray = newValue; sync() }
    }
    /// Last-used filename template for metadata-stripped tray exports. Empty = default.
    var exportTemplateTrayStripped: String {
        get { _exportTemplateTrayStripped }
        set { _exportTemplateTrayStripped = newValue; sync() }
    }
    /// Last-used filename template for web-optimized tray exports. Empty = default.
    var exportTemplateTrayWeb: String {
        get { _exportTemplateTrayWeb }
        set { _exportTemplateTrayWeb = newValue; sync() }
    }

    // MARK: — Web Export
    var webExportMaxDimension: Int {
        get { _webExportMaxDimension }
        set { _webExportMaxDimension = newValue; sync() }
    }
    var webExportQuality: Double {
        get { _webExportQuality }
        set { _webExportQuality = newValue; sync() }
    }

    // Internal storage
    private var _confirmBeforeTrash: Bool
    private var _showFilenameLabels: Bool
    private var _preserveAspectRatio: Bool
    private var _defaultThumbnailSize: Double
    private var _trayThumbnailSize: Double
    private var _trayVisibleRows: Int
    private var _enableMap: Bool
    private var _enableFaces: Bool
    private var _includeSubfolders: Bool
    private var _exportTemplateSelection: String
    private var _exportTemplateTray: String
    private var _exportTemplateTrayStripped: String
    private var _exportTemplateTrayWeb: String
    private var _webExportMaxDimension: Int
    private var _webExportQuality: Double

    private let defaults = UserDefaults.standard
    private let keyPrefix = "PicshursSettings."

    init() {
        _confirmBeforeTrash   = defaults.object(forKey: keyPrefix + "confirmBeforeTrash")   as? Bool   ?? true
        _showFilenameLabels   = defaults.object(forKey: keyPrefix + "showFilenameLabels")   as? Bool   ?? false
        _preserveAspectRatio  = defaults.object(forKey: keyPrefix + "preserveAspectRatio")  as? Bool   ?? false
        _defaultThumbnailSize = defaults.object(forKey: keyPrefix + "defaultThumbnailSize") as? Double ?? 160
        _trayThumbnailSize    = defaults.object(forKey: keyPrefix + "trayThumbnailSize")    as? Double ?? 60
        _trayVisibleRows      = defaults.object(forKey: keyPrefix + "trayVisibleRows")      as? Int    ?? 3
        _enableMap            = defaults.object(forKey: keyPrefix + "enableMap")            as? Bool   ?? true
        _enableFaces          = defaults.object(forKey: keyPrefix + "enableFaces")          as? Bool   ?? false  // experimental — off by default
        _includeSubfolders          = defaults.object(forKey: keyPrefix + "includeSubfolders")          as? Bool   ?? true
        _exportTemplateSelection    = defaults.object(forKey: keyPrefix + "exportTemplateSelection")    as? String ?? ""
        _exportTemplateTray         = defaults.object(forKey: keyPrefix + "exportTemplateTray")         as? String ?? ""
        _exportTemplateTrayStripped = defaults.object(forKey: keyPrefix + "exportTemplateTrayStripped") as? String ?? ""
        _exportTemplateTrayWeb      = defaults.object(forKey: keyPrefix + "exportTemplateTrayWeb")      as? String ?? ""
        _webExportMaxDimension = defaults.object(forKey: keyPrefix + "webExportMaxDimension") as? Int    ?? 2048
        _webExportQuality      = defaults.object(forKey: keyPrefix + "webExportQuality")      as? Double ?? 0.82
    }

    private func sync() {
        defaults.set(_confirmBeforeTrash, forKey: keyPrefix + "confirmBeforeTrash")
        defaults.set(_showFilenameLabels, forKey: keyPrefix + "showFilenameLabels")
        defaults.set(_preserveAspectRatio, forKey: keyPrefix + "preserveAspectRatio")
        defaults.set(_defaultThumbnailSize, forKey: keyPrefix + "defaultThumbnailSize")
        defaults.set(_trayThumbnailSize, forKey: keyPrefix + "trayThumbnailSize")
        defaults.set(_trayVisibleRows, forKey: keyPrefix + "trayVisibleRows")
        defaults.set(_enableMap, forKey: keyPrefix + "enableMap")
        defaults.set(_enableFaces, forKey: keyPrefix + "enableFaces")
        defaults.set(_includeSubfolders, forKey: keyPrefix + "includeSubfolders")
        defaults.set(_exportTemplateSelection, forKey: keyPrefix + "exportTemplateSelection")
        defaults.set(_exportTemplateTray, forKey: keyPrefix + "exportTemplateTray")
        defaults.set(_exportTemplateTrayStripped, forKey: keyPrefix + "exportTemplateTrayStripped")
        defaults.set(_exportTemplateTrayWeb, forKey: keyPrefix + "exportTemplateTrayWeb")
        defaults.set(_webExportMaxDimension, forKey: keyPrefix + "webExportMaxDimension")
        defaults.set(_webExportQuality, forKey: keyPrefix + "webExportQuality")
    }

    func resetToDefaults() {
        _confirmBeforeTrash = true
        _showFilenameLabels = false
        _preserveAspectRatio = false
        _defaultThumbnailSize = 160
        _trayThumbnailSize = 60
        _trayVisibleRows = 3
        _enableMap = true
        _enableFaces = false
        _includeSubfolders = true
        _exportTemplateSelection = ""
        _exportTemplateTray = ""
        _exportTemplateTrayStripped = ""
        _exportTemplateTrayWeb = ""
        _webExportMaxDimension = 2048
        _webExportQuality = 0.82
        sync()
    }
}
