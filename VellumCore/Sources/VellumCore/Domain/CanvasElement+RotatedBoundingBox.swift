import CoreGraphics
import Foundation

extension CanvasElement {
    /// Axis-aligned bounding box of `frame` after rotating by `rotation` radians about the frame's center.
    /// `rotation` is in radians (matches how it's already used: SwiftUI
    /// `.rotationEffect(.radians(element.rotation))` and CoreGraphics
    /// `ctx.rotate(by: CGFloat(element.rotation))` elsewhere in this codebase).
    public var rotatedBoundingBox: CGRect {
        let rect = CGRect(
            x: CGFloat(frame.x),
            y: CGFloat(frame.y),
            width: CGFloat(frame.width),
            height: CGFloat(frame.height)
        )
        guard rotation != 0 else { return rect }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let cosine = cos(CGFloat(rotation))
        let sine = sin(CGFloat(rotation))
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ].map { point in
            let translatedX = point.x - center.x
            let translatedY = point.y - center.y
            return CGPoint(
                x: center.x + translatedX * cosine - translatedY * sine,
                y: center.y + translatedX * sine + translatedY * cosine
            )
        }

        let minX = corners.map(\.x).min() ?? rect.minX
        let maxX = corners.map(\.x).max() ?? rect.maxX
        let minY = corners.map(\.y).min() ?? rect.minY
        let maxY = corners.map(\.y).max() ?? rect.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
