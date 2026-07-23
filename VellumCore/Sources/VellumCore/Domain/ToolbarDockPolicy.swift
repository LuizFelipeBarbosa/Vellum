import CoreGraphics

public enum ToolbarDockEdge: String, Codable, CaseIterable, Sendable {
    case top, bottom, left, right
}

public extension ToolbarDockEdge {
    /// Layout axis of a toolbar docked to this edge.
    enum Axis: Sendable, Equatable { case horizontal, vertical }

    var axis: Axis {
        switch self {
        case .top, .bottom: .horizontal
        case .left, .right: .vertical
        }
    }

    /// True when the secondary (colors/mode) section comes FIRST in stack order
    /// so it faces the page center (bottom dock -> above tools, right dock -> left of tools).
    var secondarySectionLeads: Bool { self == .bottom || self == .right }
}

/// Edge + fractional offset (0...1) of the toolbar CENTER along that edge.
/// For .top/.bottom the fraction maps to x across the container width;
/// for .left/.right it maps to y across the container height.
public struct ToolbarDockPlacement: Codable, Equatable, Sendable {
    public var edge: ToolbarDockEdge
    public var fraction: CGFloat

    public init(edge: ToolbarDockEdge, fraction: CGFloat) {
        self.edge = edge
        self.fraction = fraction
    }

    public static let `default` = ToolbarDockPlacement(edge: .bottom, fraction: 0.5)
}

public struct DockInsets: Equatable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(
        top: CGFloat = 0,
        leading: CGFloat = 0,
        bottom: CGFloat = 0,
        trailing: CGFloat = 0
    ) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

public enum ToolbarDockPolicy {
    private static let minimumAxisLength: CGFloat = 0.000_001

    /// Nearest edge by perpendicular distance from releaseCenter to each inset edge,
    /// with the fraction clamped so the toolbar rect stays fully inside insets + edgeMargin.
    public static func nearestPlacement(
        releaseCenter: CGPoint,
        toolbarSize: CGSize,
        container: CGSize,
        insets: DockInsets,
        edgeMargin: CGFloat = 16
    ) -> ToolbarDockPlacement {
        let geometry = Geometry(
            toolbarSize: toolbarSize,
            container: container,
            insets: insets,
            edgeMargin: edgeMargin
        )
        let releaseX = finite(releaseCenter.x, fallback: geometry.width / 2)
        let releaseY = finite(releaseCenter.y, fallback: geometry.height / 2)

        var edge = ToolbarDockEdge.bottom
        var shortestDistance = distance(releaseY, geometry.bottomEdge)

        let candidates: [(ToolbarDockEdge, CGFloat)] = [
            (.top, distance(releaseY, geometry.top)),
            (.left, distance(releaseX, geometry.leading)),
            (.right, distance(releaseX, geometry.trailingEdge)),
        ]
        for candidate in candidates where candidate.1 < shortestDistance {
            edge = candidate.0
            shortestDistance = candidate.1
        }

        let fraction: CGFloat
        switch edge {
        case .top, .bottom:
            fraction = clampedFraction(
                coordinate: releaseX,
                length: geometry.width,
                startInset: geometry.leading,
                endInset: geometry.trailing,
                toolbarLength: geometry.toolbarWidth,
                margin: geometry.margin
            )
        case .left, .right:
            fraction = clampedFraction(
                coordinate: releaseY,
                length: geometry.height,
                startInset: geometry.top,
                endInset: geometry.bottom,
                toolbarLength: geometry.toolbarHeight,
                margin: geometry.margin
            )
        }

        return ToolbarDockPlacement(edge: edge, fraction: fraction)
    }

    /// Concrete center point for a placement in the current container.
    /// Re-clamps on every call so rotation/size-class changes self-heal.
    public static func center(
        of placement: ToolbarDockPlacement,
        toolbarSize: CGSize,
        container: CGSize,
        insets: DockInsets,
        edgeMargin: CGFloat = 16
    ) -> CGPoint {
        let geometry = Geometry(
            toolbarSize: toolbarSize,
            container: container,
            insets: insets,
            edgeMargin: edgeMargin
        )
        let fraction = clampedUnitValue(placement.fraction)

        let horizontalCenter = concreteCoordinate(
            fraction: fraction,
            length: geometry.width,
            startInset: geometry.leading,
            endInset: geometry.trailing,
            toolbarLength: geometry.toolbarWidth,
            margin: geometry.margin
        )
        let verticalCenter = concreteCoordinate(
            fraction: fraction,
            length: geometry.height,
            startInset: geometry.top,
            endInset: geometry.bottom,
            toolbarLength: geometry.toolbarHeight,
            margin: geometry.margin
        )

        switch placement.edge {
        case .top:
            return CGPoint(
                x: horizontalCenter,
                y: dockedCoordinate(
                    atStart: true,
                    length: geometry.height,
                    startInset: geometry.top,
                    endInset: geometry.bottom,
                    toolbarLength: geometry.toolbarHeight,
                    margin: geometry.margin
                )
            )
        case .bottom:
            return CGPoint(
                x: horizontalCenter,
                y: dockedCoordinate(
                    atStart: false,
                    length: geometry.height,
                    startInset: geometry.top,
                    endInset: geometry.bottom,
                    toolbarLength: geometry.toolbarHeight,
                    margin: geometry.margin
                )
            )
        case .left:
            return CGPoint(
                x: dockedCoordinate(
                    atStart: true,
                    length: geometry.width,
                    startInset: geometry.leading,
                    endInset: geometry.trailing,
                    toolbarLength: geometry.toolbarWidth,
                    margin: geometry.margin
                ),
                y: verticalCenter
            )
        case .right:
            return CGPoint(
                x: dockedCoordinate(
                    atStart: false,
                    length: geometry.width,
                    startInset: geometry.leading,
                    endInset: geometry.trailing,
                    toolbarLength: geometry.toolbarWidth,
                    margin: geometry.margin
                ),
                y: verticalCenter
            )
        }
    }

    private static func clampedFraction(
        coordinate: CGFloat,
        length: CGFloat,
        startInset: CGFloat,
        endInset: CGFloat,
        toolbarLength: CGFloat,
        margin: CGFloat
    ) -> CGFloat {
        guard length > minimumAxisLength,
              let bounds = centerBounds(
                  length: length,
                  startInset: startInset,
                  endInset: endInset,
                  toolbarLength: toolbarLength,
                  margin: margin
              ) else {
            return 0.5
        }

        let safeCoordinate = finite(coordinate, fallback: length / 2)
        let clampedCoordinate = min(max(safeCoordinate, bounds.lowerBound), bounds.upperBound)
        let fraction = clampedCoordinate / length
        return fraction.isFinite ? clampedUnitValue(fraction) : 0.5
    }

    private static func concreteCoordinate(
        fraction: CGFloat,
        length: CGFloat,
        startInset: CGFloat,
        endInset: CGFloat,
        toolbarLength: CGFloat,
        margin: CGFloat
    ) -> CGFloat {
        guard length > minimumAxisLength,
              let bounds = centerBounds(
                  length: length,
                  startInset: startInset,
                  endInset: endInset,
                  toolbarLength: toolbarLength,
                  margin: margin
              ) else {
            return length / 2
        }

        let coordinate = clampedUnitValue(fraction) * length
        return min(max(coordinate, bounds.lowerBound), bounds.upperBound)
    }

    private static func dockedCoordinate(
        atStart: Bool,
        length: CGFloat,
        startInset: CGFloat,
        endInset: CGFloat,
        toolbarLength: CGFloat,
        margin: CGFloat
    ) -> CGFloat {
        guard let bounds = centerBounds(
            length: length,
            startInset: startInset,
            endInset: endInset,
            toolbarLength: toolbarLength,
            margin: margin
        ) else {
            return length / 2
        }
        return atStart ? bounds.lowerBound : bounds.upperBound
    }

    private static func centerBounds(
        length: CGFloat,
        startInset: CGFloat,
        endInset: CGFloat,
        toolbarLength: CGFloat,
        margin: CGFloat
    ) -> ClosedRange<CGFloat>? {
        let insetLength = length - startInset - endInset
        let start = startInset + margin + toolbarLength / 2
        let end = length - endInset - margin - toolbarLength / 2
        guard insetLength.isFinite,
              insetLength > minimumAxisLength,
              start.isFinite,
              end.isFinite,
              start <= end else {
            return nil
        }
        return start...end
    }

    private static func clampedUnitValue(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    private static func distance(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let result = abs(first - second)
        return result.isFinite ? result : .greatestFiniteMagnitude
    }

    private static func finite(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite ? value : fallback
    }

    private struct Geometry {
        let toolbarWidth: CGFloat
        let toolbarHeight: CGFloat
        let width: CGFloat
        let height: CGFloat
        let top: CGFloat
        let leading: CGFloat
        let bottom: CGFloat
        let trailing: CGFloat
        let margin: CGFloat

        var bottomEdge: CGFloat {
            height - bottom
        }

        var trailingEdge: CGFloat {
            width - trailing
        }

        init(
            toolbarSize: CGSize,
            container: CGSize,
            insets: DockInsets,
            edgeMargin: CGFloat
        ) {
            toolbarWidth = Self.nonnegativeFinite(toolbarSize.width)
            toolbarHeight = Self.nonnegativeFinite(toolbarSize.height)
            width = Self.nonnegativeFinite(container.width)
            height = Self.nonnegativeFinite(container.height)
            top = Self.nonnegativeFinite(insets.top)
            leading = Self.nonnegativeFinite(insets.leading)
            bottom = Self.nonnegativeFinite(insets.bottom)
            trailing = Self.nonnegativeFinite(insets.trailing)
            margin = Self.nonnegativeFinite(edgeMargin)
        }

        private static func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
            value.isFinite ? max(0, value) : 0
        }
    }
}
