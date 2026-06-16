import CoreGraphics
import CoreImage
import AppKit

/// Applies `EditPayload` adjustments to a photo using Core Image.
enum ImageProcessor {
    private static let context: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ])
    }()

    /// Renders the edited image at a specific display size (for live preview).
    static func renderPreview(
        from photoURL: URL,
        payload: EditPayload,
        displaySize: CGSize,
        skipCrop: Bool = false
    ) -> NSImage? {
        guard let ciImage = loadCIImage(from: photoURL) else {
            guard let nsImage = NSImage(contentsOf: photoURL) else { return nil }
            return nsImage
        }
        
        var processed = apply(payload, to: ciImage, skipCrop: skipCrop)
        let scale = computeDisplayScale(ciImage: processed, displaySize: displaySize)

        guard processed.extent.width > 0, processed.extent.height > 0 else { return nil }

        // Downsample in CI before rendering — rendering the full extent of a
        // 24MP image to CGImage (and reading it back from the GPU) is what the
        // preview path must never do. 2x for Retina, capped at native size.
        let renderScale = min(1.0, scale * 2.0)
        if renderScale < 1.0 {
            processed = processed
                .transformed(by: CGAffineTransform(scaleX: renderScale, y: renderScale))
        }

        guard let cgImage = context.createCGImage(processed, from: processed.extent) else {
            if let originalCGImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let nsImage = NSImage(cgImage: originalCGImage, size: NSSize(
                    width: CGFloat(ciImage.extent.width) * scale,
                    height: CGFloat(ciImage.extent.height) * scale
                ))
                return nsImage
            }
            return nil
        }

        // Same on-screen point size as before: original extent × scale,
        // where original extent = rendered extent / renderScale
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(
            width: processed.extent.width / renderScale * scale,
            height: processed.extent.height / renderScale * scale
        ))
        return nsImage
    }

    /// Renders the edited image at the original resolution (for Save / Export).
    static func renderFullResolution(
        from photoURL: URL,
        payload: EditPayload
    ) -> CGImage? {
        guard let ciImage = loadCIImage(from: photoURL) else {
            guard let nsImage = NSImage(contentsOf: photoURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return cgImage
        }
        
        let processed = apply(payload, to: ciImage)
        
        guard processed.extent.width > 0, processed.extent.height > 0 else {
            return context.createCGImage(ciImage, from: ciImage.extent)
        }
        
        if let cgImage = context.createCGImage(
            processed,
            from: processed.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) {
            return cgImage
        } else {
            return context.createCGImage(ciImage, from: ciImage.extent)
        }
    }

    // MARK: - Pipeline

    /// Applies layers in user-order and geometry last.
    /// Pipeline: layers (user order) → rotation → straighten → crop
    private static func apply(_ payload: EditPayload, to input: CIImage, skipCrop: Bool = false) -> CIImage {
        var image = input

        // Process all layers in user-specified order
        for layer in payload.layers {
            image = applyLayer(layer, to: image)
        }

        // Geometry transforms applied last, in fixed order

        // 1. Rotation
        if payload.rotation != 0 {
            let radians = -CGFloat(payload.rotation) * .pi / 180
            let extent = image.extent
            let center = CGPoint(x: extent.midX, y: extent.midY)
            var t = CGAffineTransform(translationX: center.x, y: center.y)
            t = t.rotated(by: radians)
            t = t.translatedBy(x: -center.x, y: -center.y)
            image = image.transformed(by: t)
        }

        // 2. Straighten (fine rotation around center) + auto-zoom to fill
        if payload.straightenAngle != 0.0 {
            let radians = CGFloat(payload.straightenAngle) * .pi / 180
            let preExtent = image.extent
            let center = CGPoint(x: preExtent.midX, y: preExtent.midY)
            let origW = preExtent.width
            let origH = preExtent.height

            let alpha = abs(radians)
            let sinA = sin(alpha)
            let cosA = cos(alpha)

            // Zoom factor: scale up so rotated image fills the original bounds
            let zoom: CGFloat
            if origW > 0 && origH > 0 && alpha > 0.001 {
                zoom = max(
                    (origW * cosA + origH * sinA) / origW,
                    (origH * cosA + origW * sinA) / origH
                )
            } else {
                zoom = 1.0
            }

            var t = CGAffineTransform(translationX: center.x, y: center.y)
            t = t.rotated(by: radians)
            t = t.scaledBy(x: zoom, y: zoom)
            t = t.translatedBy(x: -center.x, y: -center.y)
            image = image.transformed(by: t)

            // Crop back to original dimensions centered on the result
            let postExtent = image.extent
            let cropRect = CGRect(
                x: postExtent.midX - origW / 2,
                y: postExtent.midY - origH / 2,
                width: origW,
                height: origH
            )
            image = image.cropped(to: cropRect)
        }

        // 3. Crop (normalized rectangle — flip Y from SwiftUI top-down to CIImage bottom-up)
        if !skipCrop, let crop = payload.cropRect {
            let extent = image.extent
            let flippedY = 1.0 - crop.y - crop.height
            let cropRect = CGRect(
                x: extent.origin.x + extent.width * CGFloat(crop.x),
                y: extent.origin.y + extent.height * CGFloat(flippedY),
                width: extent.width * CGFloat(crop.width),
                height: extent.height * CGFloat(crop.height)
            )
            image = image.cropped(to: cropRect)
        }

        return image
    }

    // MARK: - Per-layer processing

    private static func applyLayer(_ layer: AdjustmentLayer, to input: CIImage) -> CIImage {
        let params = layer.parameters

        switch layer.type {

        // Tuning layers
        case .brightness:
            let v = params["value"] ?? 0
            if v == 0 { return input }
            return input.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: v])

        case .contrast:
            let v = params["value"] ?? 1
            if v == 1 { return input }
            return input.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: v])

        case .exposure:
            let v = params["value"] ?? 0
            if v == 0 { return input }
            return input.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: v])

        case .saturation:
            let v = params["value"] ?? 1
            if v == 1 { return input }
            return input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: v])

        case .temperature:
            let temp = params["temp"] ?? 6500
            let tint = params["tint"] ?? 0
            if temp == 6500 && tint == 0 { return input }
            let sourceVector = CIVector(x: CGFloat(temp), y: CGFloat(tint))
            let targetVector = CIVector(x: 6500, y: 0)
            if let filter = CIFilter(name: "CITemperatureAndTint", parameters: [
                kCIInputImageKey: input,
                "inputNeutral": sourceVector,
                "inputTargetNeutral": targetVector
            ]), let output = filter.outputImage {
                return output
            }
            return input

        case .shadows:
            let v = params["value"] ?? 0
            if v == 0 { return input }
            return input.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": v])

        case .sharpness:
            let v = params["value"] ?? 0
            if v == 0 { return input }
            return input.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: v])

        // Composite auto-enhance layers — combine multiple adjustments into single output
        case .autoContrast:
            let b = params["brightness"] ?? 0
            let c = params["contrast"] ?? 1
            let e = params["exposure"] ?? 0
            var img = input
            if b != 0 || c != 1 {
                img = img.applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: b,
                    kCIInputContrastKey: c
                ])
            }
            if e != 0 {
                img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: e])
            }
            return img

        case .autoColor:
            let s = params["saturation"] ?? 1
            let temp = params["temp"] ?? 6500
            let tint = params["tint"] ?? 0
            var img = input
            if s != 1 {
                img = img.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: s])
            }
            if temp != 6500 || tint != 0 {
                let sv = CIVector(x: CGFloat(temp), y: CGFloat(tint))
                let tv = CIVector(x: 6500, y: 0)
                if let filter = CIFilter(name: "CITemperatureAndTint", parameters: [
                    kCIInputImageKey: img,
                    "inputNeutral": sv,
                    "inputTargetNeutral": tv
                ]), let output = filter.outputImage {
                    img = output
                }
            }
            return img

        case .autoLucky:
            let b = params["brightness"] ?? 0
            let c = params["contrast"] ?? 1
            let e = params["exposure"] ?? 0
            let s = params["saturation"] ?? 1
            let temp = params["temp"] ?? 6500
            let tint = params["tint"] ?? 0
            var img = input
            if b != 0 || c != 1 || s != 1 {
                img = img.applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: b,
                    kCIInputContrastKey: c,
                    kCIInputSaturationKey: s
                ])
            }
            if e != 0 {
                img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: e])
            }
            if temp != 6500 || tint != 0 {
                let sv = CIVector(x: CGFloat(temp), y: CGFloat(tint))
                let tv = CIVector(x: 6500, y: 0)
                if let filter = CIFilter(name: "CITemperatureAndTint", parameters: [
                    kCIInputImageKey: img,
                    "inputNeutral": sv,
                    "inputTargetNeutral": tv
                ]), let output = filter.outputImage {
                    img = output
                }
            }
            return img

        // Filter layers
        case .sepia:
            let t = params["value"] ?? 0.7
            return input.applyingFilter("CISepiaTone", parameters: ["inputIntensity": t])

        case .bw:
            return input.applyingFilter("CIPhotoEffectMono", parameters: [:])

        case .warmify:
            let t = params["value"] ?? 0.7
            let warmTemp = 6500 - (t * 2500)
            let source = CIVector(x: CGFloat(warmTemp), y: 0)
            let target = CIVector(x: 6500, y: 0)
            return input.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": source,
                "inputTargetNeutral": target
            ])

        case .vignette:
            let t = params["value"] ?? 0.7
            let s = params["secondary"] ?? 0.5
            let intensity = t * 2.0
            let radius = 0.5 + s * 1.5
            return input.applyingFilter("CIVignette", parameters: [
                "inputIntensity": intensity,
                "inputRadius": radius
            ])

        case .filmGrain:
            let t = params["value"] ?? 0.7
            guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return input }
            let croppedNoise = noise.cropped(to: input.extent)
            let scaledNoise = croppedNoise.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputBrightnessKey: 0.0,
                kCIInputContrastKey: t * 3.0
            ])
            return scaledNoise.applyingFilter("CISoftLightBlendMode", parameters: [
                kCIInputBackgroundImageKey: input
            ])

        case .fade:
            let t = params["value"] ?? 0.7
            let contrast = 1.0 - t * 0.35
            let brightness = t * 0.08
            return input.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: contrast,
                kCIInputBrightnessKey: brightness,
                kCIInputSaturationKey: 1.0 - t * 0.2
            ])

        case .softFocus:
            let t = params["value"] ?? 0.7
            let radius = t * 12.0
            let blurred = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: input.extent)
            return blurred.applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: input.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.0
                ])
            ])

        case .glow:
            let t = params["value"] ?? 0.7
            return input.applyingFilter("CIBloom", parameters: [
                kCIInputIntensityKey: t,
                kCIInputRadiusKey: 10.0
            ])

        case .sharpenEffect:
            let t = params["value"] ?? 0.7
            return input.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: t * 2.0
            ])

        case .vibrance:
            let t = params["value"] ?? 0.7
            return input.applyingFilter("CIVibrance", parameters: [
                "inputAmount": t * 2.0 - 1.0
            ])

        case .clarity:
            let t = params["value"] ?? 0.7
            return input.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 20.0,
                kCIInputIntensityKey: t * 1.5
            ])

        case .dehaze:
            let t = params["value"] ?? 0.7
            let gamma = 1.0 - t * 0.4
            let gammaed = input.applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma])
            return gammaed.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.0 + t * 0.4,
                kCIInputSaturationKey: 1.0 + t * 0.2
            ])

        case .invert:
            return input.applyingFilter("CIColorInvert", parameters: [:])

        case .noir:
            return input.applyingFilter("CIPhotoEffectNoir", parameters: [:])

        case .chrome:
            return input.applyingFilter("CIPhotoEffectChrome", parameters: [:])

        case .instant:
            return input.applyingFilter("CIPhotoEffectInstant", parameters: [:])

        case .lomo:
            let t = params["value"] ?? 0.7
            var img = input
            if t != 0 {
                img = img.applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.4,
                    kCIInputSaturationKey: 1.3
                ])
                img = img.applyingFilter("CIVignette", parameters: [
                    "inputIntensity": 1.5,
                    "inputRadius": 1.2
                ])
            }
            return img

        case .hdrish:
            var img = input.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 0.3,
                "inputShadowAmount": 1.0
            ])
            img = img.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.2,
                kCIInputSaturationKey: 1.4
            ])
            return img

        case .crossProcess:
            var img = input.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.3,
                kCIInputSaturationKey: 1.5
            ])
            img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.3])
            return img

        case .vintage:
            var img = input.applyingFilter("CISepiaTone", parameters: ["inputIntensity": 0.3])
            img = img.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 0.85,
                kCIInputBrightnessKey: 0.05
            ])
            img = img.applyingFilter("CIVignette", parameters: [
                "inputIntensity": 1.0,
                "inputRadius": 1.5
            ])
            return img

        case .comicBook:
            return input.applyingFilter("CIComicEffect", parameters: [:])

        case .posterize:
            let t = params["value"] ?? 0.7
            let levels = 2.0 + t * 8.0
            return input.applyingFilter("CIColorPosterize", parameters: ["inputLevels": levels])

        case .pixellate:
            let t = params["value"] ?? 0.7
            let scale = 2.0 + t * 40.0
            return input.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: scale])

        case .crystallize:
            let t = params["value"] ?? 0.7
            let radius = 2.0 + t * 40.0
            return input.applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: radius])

        case .edges:
            let t = params["value"] ?? 0.7
            return input.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: t * 10.0])

        case .pointillize:
            let t = params["value"] ?? 0.7
            let radius = 2.0 + t * 28.0
            return input.applyingFilter("CIPointillize", parameters: [kCIInputRadiusKey: radius])

        case .kaleidoscope:
            let center = CIVector(x: input.extent.midX, y: input.extent.midY)
            return input.applyingFilter("CIKaleidoscope", parameters: [
                "inputCount": 6,
                kCIInputCenterKey: center,
                "inputAngle": 0.0
            ])

        case .thermal:
            let blue = CIColor(red: 0.0, green: 0.0, blue: 1.0)
            let red  = CIColor(red: 1.0, green: 0.2, blue: 0.0)
            return input.applyingFilter("CIFalseColor", parameters: [
                "inputColor0": blue,
                "inputColor1": red
            ])

        case .tint:
            return input
        }
    }

    // MARK: - Auto Enhance Analysis

    struct AutoAdjustmentValues {
        var brightness: Double = 0.0
        var contrast: Double = 1.0
        var exposure: Double = 0.0
        var saturation: Double = 1.0
        var colorTemperature: Double = 6500
        var colorTint: Double = 0
    }

    enum AutoAdjustMode { case full, contrast, color }

    static func suggestAutoAdjustments(
        from photoURL: URL,
        payload: EditPayload,
        mode: AutoAdjustMode
    ) -> AutoAdjustmentValues? {
        guard let ciImage = loadCIImage(from: photoURL) else { return nil }

        var neutralPayload = EditPayload()
        neutralPayload.rotation = payload.rotation
        neutralPayload.straightenAngle = payload.straightenAngle
        neutralPayload.cropRect = payload.cropRect

        let base = apply(neutralPayload, to: ciImage)

        let filters = base.autoAdjustmentFilters(options: [
            CIImageAutoAdjustmentOption.enhance: true
        ])

        var values = AutoAdjustmentValues()
        var hasContrastFilter = false
        var hasExposureFilter = false
        var hasSaturationFilter = false
        var hasTempTintFilter = false

        for filter in filters {
            let name = filter.name

            switch name {
            case let n where n.hasSuffix("ColorControls"):
                if mode == .full || mode == .contrast {
                    values.brightness = (filter.value(forKey: "inputBrightness") as? NSNumber)?.doubleValue ?? 0.0
                    values.contrast = (filter.value(forKey: "inputContrast") as? NSNumber)?.doubleValue ?? 1.0
                    hasContrastFilter = true
                }
                if mode == .full || mode == .color {
                    values.saturation = (filter.value(forKey: "inputSaturation") as? NSNumber)?.doubleValue ?? 1.0
                    hasSaturationFilter = true
                }
            case let n where n.hasSuffix("ExposureAdjust"):
                if mode == .full || mode == .contrast {
                    values.exposure = (filter.value(forKey: "inputEV") as? NSNumber)?.doubleValue ?? 0.0
                    hasExposureFilter = true
                }
            case let n where n.hasSuffix("TemperatureAndTint"):
                if mode == .full || mode == .color {
                    if let source = filter.value(forKey: "inputNeutral") as? CIVector {
                        values.colorTemperature = Double(source.x)
                        values.colorTint = Double(source.y)
                        hasTempTintFilter = true
                    }
                }
            default:
                break
            }
        }

        let needsContrast = mode == .full || mode == .contrast
        let needsColor = mode == .full || mode == .color

        if needsContrast {
            if !hasContrastFilter || abs(values.contrast - 1.0) < 0.04 {
                values.contrast = max(values.contrast, 1.12)
                values.brightness = min(values.brightness, -0.03)
            }
            if !hasExposureFilter || abs(values.exposure) < 0.03 {
                values.exposure = max(values.exposure, 0.05)
            }
        }

        if needsColor {
            if !hasSaturationFilter || abs(values.saturation - 1.0) < 0.06 {
                values.saturation = max(values.saturation, 1.15)
            }
            if !hasTempTintFilter || (abs(values.colorTemperature - 6500) < 200 && abs(values.colorTint) < 3) {
                values.colorTemperature = 6500
                values.colorTint = 0
            }
        }

        return values
    }

    // MARK: - Loading

    private static func loadCIImage(from url: URL) -> CIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        // Apply EXIF orientation so the pixel buffer is always upright.
        // Without this option CIImage ignores the orientation tag and callers
        // would need to rotate manually — breaking the edit pipeline for any
        // photo taken in portrait or upside-down orientation.
        let options: [CIImageOption: Any] = [.applyOrientationProperty: true]

        if let image = CIImage(contentsOf: url, options: options) {
            if image.extent.width > 0 && image.extent.height > 0 {
                return image
            }
            return nil
        }
        
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        if ciImage.extent.width > 0 && ciImage.extent.height > 0 {
            return ciImage
        }
        return nil
    }

    private static func computeDisplayScale(ciImage: CIImage, displaySize: CGSize) -> CGFloat {
        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        guard imageWidth > 0, imageHeight > 0 else { return 1 }
        let scaleX = displaySize.width / CGFloat(imageWidth)
        let scaleY = displaySize.height / CGFloat(imageHeight)
        return min(scaleX, scaleY, 1.0)
    }
}
