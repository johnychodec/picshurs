import CoreGraphics
import CoreImage
import AppKit

struct HistogramData {
    var red: [Float] = Array(repeating: 0, count: 256)
    var green: [Float] = Array(repeating: 0, count: 256)
    var blue: [Float] = Array(repeating: 0, count: 256)
    var maxValue: Float = 1.0
}

enum HistogramService {

    static func compute(from url: URL) -> HistogramData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        if let ciImage = CIImage(contentsOf: url),
           ciImage.extent.width > 0, ciImage.extent.height > 0 {
            return compute(from: ciImage)
        }

        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let ciImage = CIImage(cgImage: cgImage)
        guard ciImage.extent.width > 0, ciImage.extent.height > 0 else { return nil }
        return compute(from: ciImage)
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func compute(from ciImage: CIImage) -> HistogramData? {
        let sampleSize: CGFloat = 512
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scale = min(sampleSize / extent.width, sampleSize / extent.height, 1.0)
        let scaledImage: CIImage
        if scale < 1.0 {
            guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(scale, forKey: kCIInputScaleKey)
            filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
            guard let out = filter.outputImage else { return nil }
            scaledImage = out
        } else {
            scaledImage = ciImage
        }

        guard let cgImage = ciContext.createCGImage(
            scaledImage,
            from: scaledImage.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else { return nil }

        guard let dp = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(dp) else { return nil }

        let w = cgImage.width
        let h = cgImage.height
        let bpr = cgImage.bytesPerRow
        let pixelCount = w * h
        guard pixelCount > 0 else { return nil }

        var rCounts = [Int](repeating: 0, count: 256)
        var gCounts = [Int](repeating: 0, count: 256)
        var bCounts = [Int](repeating: 0, count: 256)

        for row in 0..<h {
            let rowStart = row * bpr
            for col in 0..<w {
                let offset = rowStart + col * 4
                rCounts[Int(ptr[offset])] += 1
                gCounts[Int(ptr[offset + 1])] += 1
                bCounts[Int(ptr[offset + 2])] += 1
            }
        }

        let rMax = Float(rCounts.max() ?? 1)
        let gMax = Float(gCounts.max() ?? 1)
        let bMax = Float(bCounts.max() ?? 1)
        let maxVal = max(rMax, gMax, bMax, 1.0)

        return HistogramData(
            red: rCounts.map { Float($0) / maxVal },
            green: gCounts.map { Float($0) / maxVal },
            blue: bCounts.map { Float($0) / maxVal },
            maxValue: 1.0
        )
    }
}
