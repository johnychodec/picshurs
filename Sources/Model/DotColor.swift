import SwiftUI

struct DotColorInfo: Identifiable {
    let rawValue: Int
    let name: String
    let color: Color

    var id: Int { rawValue }
}

enum DotColor {
    static let all: [DotColorInfo] = [
        DotColorInfo(rawValue: 1, name: "Red", color: Color(red: 0.96, green: 0.31, blue: 0.31)),
        DotColorInfo(rawValue: 2, name: "Orange", color: Color(red: 0.98, green: 0.58, blue: 0.15)),
        DotColorInfo(rawValue: 3, name: "Yellow", color: Color(red: 0.98, green: 0.82, blue: 0.15)),
        DotColorInfo(rawValue: 4, name: "Green", color: Color(red: 0.36, green: 0.85, blue: 0.36)),
        DotColorInfo(rawValue: 5, name: "Blue", color: Color(red: 0.26, green: 0.58, blue: 0.95)),
        DotColorInfo(rawValue: 6, name: "Purple", color: Color(red: 0.70, green: 0.43, blue: 0.89)),
        DotColorInfo(rawValue: 7, name: "Gray", color: Color(red: 0.60, green: 0.60, blue: 0.60)),
        DotColorInfo(rawValue: 8, name: "White", color: Color(red: 0.88, green: 0.88, blue: 0.86)),
    ]

    static func info(for rawValue: Int) -> DotColorInfo? {
        all.first { $0.rawValue == rawValue }
    }

    static func color(for rawValue: Int) -> Color? {
        info(for: rawValue)?.color
    }

    static func name(for rawValue: Int) -> String? {
        info(for: rawValue)?.name
    }

    static func bitMask(for rawValue: Int) -> Int {
        1 << (rawValue - 1)
    }

    static func activeColors(from bitmask: Int) -> [DotColorInfo] {
        all.filter { bitmask & Self.bitMask(for: $0.rawValue) != 0 }
    }
}
