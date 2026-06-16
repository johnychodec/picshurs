import SwiftUI

struct CropOverlayView: View {
    let imageSize: CGSize
    @Binding var cropRect: CropRect
    let aspectRatio: CGFloat?

    @State private var dragStartRect: CropRect? = nil

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            if container.width > 0, container.height > 0 {
                let fitRect = aspectFitRect(image: imageSize, container: container)
                let rawFrame = cropScreenFrame(normalized: cropRect, fit: fitRect)
                let cropFrame = rawFrame.intersection(fitRect)

                ZStack(alignment: .topLeading) {
                    dimShroud(cropFrame: cropFrame, container: container)
                    cropGrid(cropFrame: cropFrame)

                    // White border
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: max(1, cropFrame.width), height: max(1, cropFrame.height))
                        .offset(x: cropFrame.minX, y: cropFrame.minY)
                        .allowsHitTesting(false)

                    // Move: interior drag — drawn first so handles take priority
                    // at the edges, but the center (most of the crop rect) moves.
                    let inset: CGFloat = 20
                    let moveW = max(1, cropFrame.width - inset * 2)
                    let moveH = max(1, cropFrame.height - inset * 2)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: moveW, height: moveH)
                        .contentShape(Rectangle())
                        .offset(x: cropFrame.minX + inset, y: cropFrame.minY + inset)
                        .gesture(moveGesture(fitRect: fitRect))
                        .onHover { inside in
                            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                        }

                    // Corner handles (L-brackets, large hit targets)
                    cornerHandle(at: .topLeft, on: cropFrame, fitRect: fitRect)
                    cornerHandle(at: .topRight, on: cropFrame, fitRect: fitRect)
                    cornerHandle(at: .bottomLeft, on: cropFrame, fitRect: fitRect)
                    cornerHandle(at: .bottomRight, on: cropFrame, fitRect: fitRect)

                    // Edge handles (bars along each edge)
                    edgeHandle(at: .top, on: cropFrame, fitRect: fitRect)
                    edgeHandle(at: .bottom, on: cropFrame, fitRect: fitRect)
                    edgeHandle(at: .left, on: cropFrame, fitRect: fitRect)
                    edgeHandle(at: .right, on: cropFrame, fitRect: fitRect)
                }
            }
        }
    }

    // MARK: - Handle types

    private enum HandleCorner { case topLeft, topRight, bottomLeft, bottomRight }
    private enum HandleEdge { case top, bottom, left, right }

    // MARK: - Dim shroud

    private func dimShroud(cropFrame: CGRect, container: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: container))
            path.addRect(cropFrame)
        }
        .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    // MARK: - Grid

    private func cropGrid(cropFrame: CGRect) -> some View {
        Path { path in
            let x1 = cropFrame.minX + cropFrame.width / 3
            let x2 = cropFrame.minX + cropFrame.width * 2 / 3
            let y1 = cropFrame.minY + cropFrame.height / 3
            let y2 = cropFrame.minY + cropFrame.height * 2 / 3

            path.move(to: CGPoint(x: x1, y: cropFrame.minY))
            path.addLine(to: CGPoint(x: x1, y: cropFrame.maxY))
            path.move(to: CGPoint(x: x2, y: cropFrame.minY))
            path.addLine(to: CGPoint(x: x2, y: cropFrame.maxY))

            path.move(to: CGPoint(x: cropFrame.minX, y: y1))
            path.addLine(to: CGPoint(x: cropFrame.maxX, y: y1))
            path.move(to: CGPoint(x: cropFrame.minX, y: y2))
            path.addLine(to: CGPoint(x: cropFrame.maxX, y: y2))
        }
        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    // MARK: - Corner handles (L-bracket visual, 48pt hit target)

    private let cornerVisualLength: CGFloat = 20
    private let cornerVisualThickness: CGFloat = 3
    private let cornerHitSize: CGFloat = 48

    private func cornerHandle(at corner: HandleCorner, on frame: CGRect, fitRect: CGRect) -> some View {
        let pos = cornerPosition(for: corner, in: frame)
        return ZStack {
            cornerBracket(corner: corner)
            Rectangle()
                .fill(Color.clear)
                .frame(width: cornerHitSize, height: cornerHitSize)
                .contentShape(Rectangle())
        }
        .offset(x: pos.x - cornerHitSize / 2, y: pos.y - cornerHitSize / 2)
        .gesture(handleCornerDrag(corner: corner, fitRect: fitRect))
    }

    private func cornerBracket(corner: HandleCorner) -> some View {
        let len = cornerVisualLength
        let t = cornerVisualThickness
        let half = cornerHitSize / 2
        return ZStack {
            // Horizontal arm
            Rectangle()
                .fill(Color.white)
                .frame(width: len, height: t)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .offset(
                    x: corner == .topLeft || corner == .bottomLeft ? -half + len / 2 : half - len / 2,
                    y: corner == .topLeft || corner == .topRight ? -half + t / 2 : half - t / 2
                )
            // Vertical arm
            Rectangle()
                .fill(Color.white)
                .frame(width: t, height: len)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .offset(
                    x: corner == .topLeft || corner == .bottomLeft ? -half + t / 2 : half - t / 2,
                    y: corner == .topLeft || corner == .topRight ? -half + len / 2 : half - len / 2
                )
        }
    }

    private func cornerPosition(for corner: HandleCorner, in frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: frame.minX, y: frame.minY)
        case .topRight:    return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft:  return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    // MARK: - Edge handles (wide bars, 28pt hit depth)

    private let edgeHitDepth: CGFloat = 28

    private func edgeHandle(at edge: HandleEdge, on frame: CGRect, fitRect: CGRect) -> some View {
        let pos = edgePosition(for: edge, in: frame)
        let visual = edgeVisualSize(for: edge)
        let hit = edgeHitTargetSize(for: edge, frame: frame)
        return ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: visual.width, height: visual.height)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            Rectangle()
                .fill(Color.clear)
                .frame(width: hit.width, height: hit.height)
                .contentShape(Rectangle())
        }
        .offset(x: pos.x - hit.width / 2, y: pos.y - hit.height / 2)
        .gesture(handleEdgeDrag(edge: edge, fitRect: fitRect))
    }

    private func edgePosition(for edge: HandleEdge, in frame: CGRect) -> CGPoint {
        switch edge {
        case .top:    return CGPoint(x: frame.midX, y: frame.minY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        case .left:   return CGPoint(x: frame.minX, y: frame.midY)
        case .right:  return CGPoint(x: frame.maxX, y: frame.midY)
        }
    }

    private func edgeVisualSize(for edge: HandleEdge) -> CGSize {
        switch edge {
        case .top, .bottom: return CGSize(width: 48, height: 4)
        case .left, .right: return CGSize(width: 4, height: 48)
        }
    }

    private func edgeHitTargetSize(for edge: HandleEdge, frame: CGRect) -> CGSize {
        switch edge {
        case .top, .bottom: return CGSize(width: max(48, frame.width * 0.5), height: edgeHitDepth)
        case .left, .right: return CGSize(width: edgeHitDepth, height: max(48, frame.height * 0.5))
        }
    }

    // MARK: - Move gesture

    private func moveGesture(fitRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = cropRect
                    NSCursor.closedHand.push()
                }
                guard let start = dragStartRect else { return }

                let startFrame = cropScreenFrame(normalized: start, fit: fitRect)
                var moved = startFrame.offsetBy(dx: value.translation.width, dy: value.translation.height)
                moved = constrain(moved, to: fitRect)
                cropRect = normalizedRect(screen: moved, fit: fitRect).clamped()
            }
            .onEnded { _ in
                dragStartRect = nil
                NSCursor.pop()
            }
    }

    // MARK: - Corner drag

    private func handleCornerDrag(corner: HandleCorner, fitRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil { dragStartRect = cropRect }
                guard let start = dragStartRect else { return }

                let tx = value.translation.width / fitRect.width
                let ty = value.translation.height / fitRect.height

                var rect = start
                switch corner {
                case .topLeft:     rect.x += tx; rect.y += ty; rect.width -= tx; rect.height -= ty
                case .topRight:    rect.y += ty; rect.width += tx; rect.height -= ty
                case .bottomLeft:  rect.x += tx; rect.width -= tx; rect.height += ty
                case .bottomRight: rect.width += tx; rect.height += ty
                }

                if aspectRatio != nil { rect = enforceCornerRatio(rect: rect, corner: corner) }
                cropRect = rect.clamped()
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func enforceCornerRatio(rect: CropRect, corner: HandleCorner) -> CropRect {
        guard let ratio = aspectRatio else { return rect }
        var r = rect
        let anchorX = rect.x + rect.width
        let anchorY = rect.y + rect.height
        r.height = r.width / ratio
        switch corner {
        case .bottomRight:
            break
        case .bottomLeft:
            r.x = anchorX - r.width
        case .topRight:
            r.y = anchorY - r.height
        case .topLeft:
            r.x = anchorX - r.width
            r.y = anchorY - r.height
        }
        return r
    }

    // MARK: - Edge drag

    private func handleEdgeDrag(edge: HandleEdge, fitRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil { dragStartRect = cropRect }
                guard let start = dragStartRect else { return }

                let tx = value.translation.width / fitRect.width
                let ty = value.translation.height / fitRect.height

                var rect = start
                switch edge {
                case .top:    rect.y += ty; rect.height -= ty
                case .bottom: rect.height += ty
                case .left:   rect.x += tx; rect.width -= tx
                case .right:  rect.width += tx
                }

                if aspectRatio != nil { rect = enforceEdgeRatio(rect: rect, edge: edge) }
                cropRect = rect.clamped()
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func enforceEdgeRatio(rect: CropRect, edge: HandleEdge) -> CropRect {
        guard let ratio = aspectRatio else { return rect }
        var r = rect
        let cx = rect.x + rect.width / 2
        let cy = rect.y + rect.height / 2
        let brx = rect.x + rect.width
        let bry = rect.y + rect.height
        switch edge {
        case .bottom:
            r.width = r.height * ratio
            r.x = cx - r.width / 2
        case .top:
            r.width = r.height * ratio
            r.x = cx - r.width / 2
            r.y = bry - r.height
        case .right:
            r.height = r.width / ratio
            r.y = cy - r.height / 2
        case .left:
            r.height = r.width / ratio
            r.y = cy - r.height / 2
            r.x = brx - r.width
        }
        return r
    }

    // MARK: - Coordinate helpers

    private func constrain(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        var f = frame
        f.origin.x = max(bounds.minX, min(f.origin.x, bounds.maxX - max(1, f.width)))
        f.origin.y = max(bounds.minY, min(f.origin.y, bounds.maxY - max(1, f.height)))
        return f
    }

    private func cropScreenFrame(normalized: CropRect, fit: CGRect) -> CGRect {
        CGRect(
            x: fit.origin.x + fit.width * normalized.x,
            y: fit.origin.y + fit.height * normalized.y,
            width: fit.width * normalized.width,
            height: fit.height * normalized.height
        )
    }

    private func normalizedRect(screen: CGRect, fit: CGRect) -> CropRect {
        CropRect(
            x: (screen.origin.x - fit.origin.x) / fit.width,
            y: (screen.origin.y - fit.origin.y) / fit.height,
            width: screen.width / fit.width,
            height: screen.height / fit.height
        )
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
