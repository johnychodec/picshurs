import SwiftUI

struct HistogramView: View {
    let data: HistogramData
    var mode: HistogramMode = .rgb

    enum HistogramMode: CaseIterable {
        case rgb
        case luminance
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width / 256.0
            let h = size.height
            let maxV = max(data.maxValue, 0.001)

            switch mode {
            case .rgb:
                drawChannel(ctx: &ctx, values: data.red, color: .red, size: size, bucketW: w, bucketH: h, maxV: maxV)
                drawChannel(ctx: &ctx, values: data.green, color: .green, size: size, bucketW: w, bucketH: h, maxV: maxV)
                drawChannel(ctx: &ctx, values: data.blue, color: .blue, size: size, bucketW: w, bucketH: h, maxV: maxV)
            case .luminance:
                var lum = [Float](repeating: 0, count: 256)
                for i in 0..<256 {
                    lum[i] = data.red[i] * 0.299 + data.green[i] * 0.587 + data.blue[i] * 0.114
                }
                drawChannel(ctx: &ctx, values: lum, color: .white, size: size, bucketW: w, bucketH: h, maxV: maxV)
            }
        }
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func drawChannel(ctx: inout GraphicsContext, values: [Float], color: Color, size: CGSize, bucketW: CGFloat, bucketH: CGFloat, maxV: Float) {
        guard values.count == 256 else { return }

        var path = Path()
        var started = false

        for i in 0..<256 {
            let x = CGFloat(i) * bucketW + bucketW / 2
            let y = size.height - CGFloat(values[i] / maxV) * bucketH

            if !started {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()

        ctx.fill(path, with: .color(color.opacity(0.4)))

        var linePath = Path()
        started = false
        for i in 0..<256 {
            let x = CGFloat(i) * bucketW + bucketW / 2
            let y = size.height - CGFloat(values[i] / maxV) * bucketH

            if !started {
                linePath.move(to: CGPoint(x: x, y: y))
                started = true
            } else {
                linePath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.stroke(linePath, with: .color(color.opacity(0.8)), lineWidth: 1)
    }
}
