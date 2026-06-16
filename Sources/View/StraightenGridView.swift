import SwiftUI

struct StraightenGridView: View {
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let fitRect = aspectFitRect(image: imageSize, container: container)

            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: fitRect.width, height: fitRect.height)
                    .offset(x: fitRect.minX, y: fitRect.minY)

                Path { path in
                    let x1 = fitRect.minX + fitRect.width / 3
                    let x2 = fitRect.minX + fitRect.width * 2 / 3
                    let y1 = fitRect.minY + fitRect.height / 3
                    let y2 = fitRect.minY + fitRect.height * 2 / 3

                    path.move(to: CGPoint(x: x1, y: fitRect.minY))
                    path.addLine(to: CGPoint(x: x1, y: fitRect.maxY))
                    path.move(to: CGPoint(x: x2, y: fitRect.minY))
                    path.addLine(to: CGPoint(x: x2, y: fitRect.maxY))

                    path.move(to: CGPoint(x: fitRect.minX, y: y1))
                    path.addLine(to: CGPoint(x: fitRect.maxX, y: y1))
                    path.move(to: CGPoint(x: fitRect.minX, y: y2))
                    path.addLine(to: CGPoint(x: fitRect.maxX, y: y2))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)

                Path { path in
                    let cx = fitRect.midX
                    let cy = fitRect.midY
                    let len: CGFloat = 20

                    path.move(to: CGPoint(x: cx - len, y: cy))
                    path.addLine(to: CGPoint(x: cx + len, y: cy))
                    path.move(to: CGPoint(x: cx, y: cy - len))
                    path.addLine(to: CGPoint(x: cx, y: cy + len))
                }
                .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func aspectFitRect(image: CGSize, container: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let imageAspect = image.width / image.height
        let containerAspect = container.width / container.height

        let renderWidth: CGFloat
        let renderHeight: CGFloat

        if imageAspect > containerAspect {
            renderWidth = container.width
            renderHeight = container.width / imageAspect
        } else {
            renderHeight = container.height
            renderWidth = container.height * imageAspect
        }

        return CGRect(
            x: (container.width - renderWidth) / 2,
            y: (container.height - renderHeight) / 2,
            width: renderWidth,
            height: renderHeight
        )
    }
}
