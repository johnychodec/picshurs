import Foundation

// MARK: - Edit Tabs

enum EditTab: Int, CaseIterable {
    case basicFixes, tuning, effectsEssential, effectsCreative, effectsExperimental

    var iconName: String {
        switch self {
        case .basicFixes: "wrench"
        case .tuning: "slider.horizontal.3"
        case .effectsEssential: "paintbrush"
        case .effectsCreative: "paintbrush.fill"
        case .effectsExperimental: "wand.and.rays"
        }
    }

    var label: String {
        switch self {
        case .basicFixes: "Basic Fixes"
        case .tuning: "Tuning"
        case .effectsEssential: "Effects"
        case .effectsCreative: "Creative"
        case .effectsExperimental: "Experimental"
        }
    }
}

// MARK: - Layer Type (superset of tuning + filters)

enum LayerType: String, Codable, CaseIterable, Identifiable {
    // Tuning
    case brightness, contrast, exposure, saturation
    case temperature, tint, shadows, sharpness
    // Composite auto-enhance
    case autoContrast, autoColor, autoLucky
    // Essential filters
    case sepia, bw, warmify, vignette, filmGrain, fade
    case softFocus, glow, sharpenEffect, vibrance, clarity, dehaze
    // Creative filters
    case invert, lomo, hdrish, crossProcess, vintage, noir, chrome, instant
    // Experimental filters
    case comicBook, posterize, pixellate, crystallize, edges, pointillize, kaleidoscope, thermal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .exposure: "Exposure"
        case .saturation: "Saturation"
        case .temperature: "Color Temp"
        case .tint: "Tint"
        case .shadows: "Shadows"
        case .sharpness: "Sharpness"
        case .autoContrast: "Auto Contrast"
        case .autoColor: "Auto Color"
        case .autoLucky: "Auto Lucky"
        case .sepia: "Sepia"
        case .bw: "B&W"
        case .warmify: "Warmify"
        case .vignette: "Vignette"
        case .filmGrain: "Film Grain"
        case .fade: "Fade"
        case .softFocus: "Soft Focus"
        case .glow: "Glow"
        case .sharpenEffect: "Sharpen"
        case .vibrance: "Vibrance"
        case .clarity: "Clarity"
        case .dehaze: "Dehaze"
        case .invert: "Invert"
        case .lomo: "Lomo"
        case .hdrish: "HDR"
        case .crossProcess: "Cross Process"
        case .vintage: "Vintage"
        case .noir: "Noir"
        case .chrome: "Chrome"
        case .instant: "Instant"
        case .comicBook: "Comic Book"
        case .posterize: "Posterize"
        case .pixellate: "Pixellate"
        case .crystallize: "Crystallize"
        case .edges: "Edges"
        case .pointillize: "Pointillize"
        case .kaleidoscope: "Kaleidoscope"
        case .thermal: "Thermal"
        }
    }

    var iconName: String {
        switch self {
        case .brightness: "sun.max"
        case .contrast: "circle.righthalf.filled"
        case .exposure: "plusminus"
        case .saturation: "paintpalette"
        case .temperature: "thermometer.medium"
        case .tint: "drop"
        case .shadows: "moon"
        case .sharpness: "triangle"
        case .autoContrast: "circle.righthalf.filled"
        case .autoColor: "paintpalette"
        case .autoLucky: "wand.and.stars"
        case .sepia: "camera.filters"
        case .bw: "circle.lefthalf.filled"
        case .warmify: "sun.max.fill"
        case .vignette: "circle.dashed"
        case .filmGrain: "film.stack"
        case .fade: "cloud.fill"
        case .softFocus: "aqi.low"
        case .glow: "sparkles"
        case .sharpenEffect: "triangle.fill"
        case .vibrance: "paintpalette.fill"
        case .clarity: "eye"
        case .dehaze: "cloud.sun.fill"
        case .invert: "circle.fill"
        case .lomo: "camera.aperture"
        case .hdrish: "chart.bar.fill"
        case .crossProcess: "arrow.triangle.2.circlepath"
        case .vintage: "clock.fill"
        case .noir: "moon.fill"
        case .chrome: "diamond.fill"
        case .instant: "bolt.fill"
        case .comicBook: "text.bubble.fill"
        case .posterize: "square.grid.2x2.fill"
        case .pixellate: "squareshape.split.2x2"
        case .crystallize: "hexagon.fill"
        case .edges: "square.on.square"
        case .pointillize: "circle.grid.3x3.fill"
        case .kaleidoscope: "star.fill"
        case .thermal: "thermometer"
        }
    }

    var tab: EditTab {
        switch self {
        case .brightness, .contrast, .exposure, .saturation,
             .temperature, .tint, .shadows, .sharpness:
            return .tuning
        case .autoContrast, .autoColor, .autoLucky:
            return .basicFixes
        case .sepia, .bw, .warmify, .vignette, .filmGrain, .fade,
             .softFocus, .glow, .sharpenEffect, .vibrance, .clarity, .dehaze:
            return .effectsEssential
        case .invert, .lomo, .hdrish, .crossProcess, .vintage, .noir, .chrome, .instant:
            return .effectsCreative
        case .comicBook, .posterize, .pixellate, .crystallize, .edges,
             .pointillize, .kaleidoscope, .thermal:
            return .effectsExperimental
        }
    }

    var isTuning: Bool {
        switch self {
        case .brightness, .contrast, .exposure, .saturation,
             .temperature, .tint, .shadows, .sharpness:
            true
        default: false
        }
    }

    var isFilter: Bool {
        !isTuning && !isComposite
    }

    var isComposite: Bool {
        switch self {
        case .autoContrast, .autoColor, .autoLucky: true
        default: false
        }
    }

    var defaultParamKey: String {
        switch self {
        case .temperature: "temp"
        case .tint: "tint"
        default: "value"
        }
    }

    var hasPrimaryParam: Bool {
        switch self {
        case .bw, .invert, .noir, .chrome, .instant, .comicBook, .kaleidoscope, .thermal:
            false
        default: true
        }
    }

    var primaryParamLabel: String {
        switch self {
        case .vignette: "Intensity"
        case .softFocus: "Radius"
        case .posterize: "Levels"
        case .pixellate, .crystallize, .pointillize: "Scale"
        case .edges: "Intensity"
        default: "Amount"
        }
    }

    var hasSecondaryParam: Bool {
        switch self {
        case .vignette, .temperature, .autoContrast, .autoColor, .autoLucky:
            true
        default: false
        }
    }

    var secondaryParamLabel: String {
        switch self {
        case .vignette: "Radius"
        case .temperature: "Tint"
        default: ""
        }
    }

    var hasParameters: Bool { hasPrimaryParam || hasSecondaryParam }

    static var tuningFilters: [LayerType] {
        [.brightness, .contrast, .exposure, .saturation,
         .temperature, .tint, .shadows, .sharpness]
    }

    static var essentialFilters: [LayerType] {
        [.sepia, .bw, .warmify, .vignette, .filmGrain, .fade,
         .softFocus, .glow, .sharpenEffect, .vibrance, .clarity, .dehaze]
    }

    static var creativeFilters: [LayerType] {
        [.invert, .lomo, .hdrish, .crossProcess, .vintage, .noir, .chrome, .instant]
    }

    static var experimentalFilters: [LayerType] {
        [.comicBook, .posterize, .pixellate, .crystallize, .edges, .pointillize, .kaleidoscope, .thermal]
    }
}

// MARK: - Adjustment Layer

struct AdjustmentLayer: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var type: LayerType
    var parameters: [String: Double] = [:]

    func param(_ key: String) -> Double {
        parameters[key] ?? 0
    }

    mutating func setParam(_ key: String, _ value: Double) {
        parameters[key] = value
    }
}


