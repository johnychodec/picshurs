import Foundation

struct CropRect: Codable, Equatable {
    var x: Double = 0.0
    var y: Double = 0.0
    var width: Double = 1.0
    var height: Double = 1.0

    static let full = CropRect(x: 0, y: 0, width: 1, height: 1)

    var isFull: Bool { x == 0 && y == 0 && width == 1 && height == 1 }

    func clamped() -> CropRect {
        var r = self
        r.x = min(max(0, r.x), 1)
        r.y = min(max(0, r.y), 1)
        r.width = min(max(0.01, r.width), 1 - r.x)
        r.height = min(max(0.01, r.height), 1 - r.y)
        return r
    }
}

struct EditPayload: Codable, Equatable {

    // MARK: - Solo-only (applied after all layers)

    var rotation: Int = 0
    var straightenAngle: Double = 0.0
    var cropRect: CropRect? = nil

    // MARK: - Stackable layers (user-ordered, composited sequentially)

    var layers: [AdjustmentLayer] = []

    init() {}

    // MARK: - Layer access

    func layerIndex(ofType type: LayerType) -> Int? {
        layers.firstIndex { $0.type == type }
    }

    func layer(id: String) -> AdjustmentLayer? {
        layers.first { $0.id == id }
    }

    func hasLayer(ofType type: LayerType) -> Bool {
        layers.contains { $0.type == type }
    }

    func tuningValue(for type: LayerType) -> Double? {
        guard let layer = layers.first(where: { $0.type == type }) else { return nil }
        return layer.param(layer.type.defaultParamKey)
    }

    mutating func setTuningValue(_ value: Double, for type: LayerType) {
        let key = type.defaultParamKey
        if let index = layers.firstIndex(where: { $0.type == type }) {
            layers[index].setParam(key, value)
        } else {
            var layer = AdjustmentLayer(type: type)
            layer.setParam(key, value)
            layers.append(layer)
        }
    }

    mutating func addLayer(_ layer: AdjustmentLayer) {
        layers.append(layer)
    }

    mutating func removeLayer(id: String) {
        layers.removeAll { $0.id == id }
    }

    mutating func removeLayer(ofType type: LayerType) {
        layers.removeAll { $0.type == type }
    }

    mutating func moveLayers(from source: IndexSet, to destination: Int) {
        layers.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Computed properties for legacy convenience

    var hasAdjustments: Bool {
        assert(cropRect == nil || !cropRect!.isFull, "A .full CropRect should be stored as nil")
        return rotation != 0 || straightenAngle != 0.0
            || !layers.isEmpty
            || (cropRect != nil && !cropRect!.isFull)
    }

    mutating func reset() {
        rotation = 0
        straightenAngle = 0.0
        cropRect = nil
        layers.removeAll()
    }

    mutating func rotateLeft() {
        rotation = (rotation - 90 + 360) % 360
        cropRect = nil
    }

    mutating func rotateRight() {
        rotation = (rotation + 90) % 360
        cropRect = nil
    }


}
