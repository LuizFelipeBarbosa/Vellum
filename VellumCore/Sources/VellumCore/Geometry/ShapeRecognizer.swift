import CoreGraphics
import Foundation

public enum RecognizedShape: Equatable, Sendable {
    case polyline(vertices: [CGPoint], isClosed: Bool)
    case ellipse(
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: CGFloat
    )
}

public struct ShapeRecognizerConfig: Sendable {
    public var dwellTailTolerance: CGFloat
    public var resampleSpacing: CGFloat
    public var rdpEpsilonFraction: CGFloat
    public var cornerAngleThresholdDegrees: CGFloat
    public var lineDeviationTolerance: CGFloat
    public var ellipseResidualTolerance: CGFloat
    public var circleAxisRatio: CGFloat
    public var axisAlignSnapDegrees: CGFloat
    public var rightAngleSnapDegrees: CGFloat
    public var maxCorners: Int
    public var minPoints: Int
    public var minDiagonal: CGFloat
    /// Side ratio at or above which a fitted rectangle is squared off, mirroring how
    /// `circleAxisRatio` rounds a near-circular ellipse.
    public var squareAxisRatio: CGFloat
    /// Collapse an open stroke to a straight line between its endpoints instead of keeping its
    /// corners. Only a stroke that was already near-straight qualifies: a mid-word pause can read
    /// as a dwell, and flattening a cursive fragment to a chord is unrecoverable, so anything that
    /// strays off that chord is rejected and keeps its ink. A deliberately drawn L or V strays far
    /// enough to be rejected too, which is the price of never guessing wrong on handwriting.
    public var straightensOpenPolylines: Bool
    /// Corner ceiling for the straightening path only, deliberately far tighter than `maxCorners`
    /// because straightening throws away everything between the endpoints. It catches the dense,
    /// low-amplitude scribble that hugs its chord closely enough to satisfy
    /// `straightenedDeviationFraction`. Ignored when straightening is off.
    public var maxStraightenedCorners: Int
    /// How far a stroke may stray from the line straightening would replace it with, as a fraction
    /// of that line's length, with `lineDeviationTolerance` as the absolute floor. Looser than the
    /// fraction `fitLine` demands of a corner-free stroke, because a stroke on this path has a real
    /// corner to accommodate, yet far tighter than the humps of round handwriting. Ignored when
    /// straightening is off.
    public var straightenedDeviationFraction: CGFloat

    public static let `default` = ShapeRecognizerConfig()

    public init(
        dwellTailTolerance: CGFloat = 6,
        resampleSpacing: CGFloat = 3,
        rdpEpsilonFraction: CGFloat = 0.02,
        cornerAngleThresholdDegrees: CGFloat = 30,
        lineDeviationTolerance: CGFloat = 5,
        ellipseResidualTolerance: CGFloat = 0.12,
        circleAxisRatio: CGFloat = 0.82,
        axisAlignSnapDegrees: CGFloat = 8,
        rightAngleSnapDegrees: CGFloat = 12,
        maxCorners: Int = 12,
        minPoints: Int = 8,
        minDiagonal: CGFloat = 16,
        squareAxisRatio: CGFloat = 0.85,
        straightensOpenPolylines: Bool = true,
        maxStraightenedCorners: Int = 4,
        straightenedDeviationFraction: CGFloat = 0.12
    ) {
        self.dwellTailTolerance = dwellTailTolerance
        self.resampleSpacing = resampleSpacing
        self.rdpEpsilonFraction = rdpEpsilonFraction
        self.cornerAngleThresholdDegrees = cornerAngleThresholdDegrees
        self.lineDeviationTolerance = lineDeviationTolerance
        self.ellipseResidualTolerance = ellipseResidualTolerance
        self.circleAxisRatio = circleAxisRatio
        self.axisAlignSnapDegrees = axisAlignSnapDegrees
        self.rightAngleSnapDegrees = rightAngleSnapDegrees
        self.maxCorners = maxCorners
        self.minPoints = minPoints
        self.minDiagonal = minDiagonal
        self.squareAxisRatio = squareAxisRatio
        self.straightensOpenPolylines = straightensOpenPolylines
        self.maxStraightenedCorners = maxStraightenedCorners
        self.straightenedDeviationFraction = straightenedDeviationFraction
    }
}

public enum ShapeRecognizer {
    private static let numericEpsilon: CGFloat = 0.000_000_001

    /// Raw stroke points in content space, in stroke order. Returns nil when ink should be kept.
    public static func recognize(
        points: [CGPoint],
        config: ShapeRecognizerConfig = .default
    ) -> RecognizedShape? {
        let finiteInput = finitePoints(points)
        let stroke = stripTrailingDwellCluster(
            points: finiteInput,
            tolerance: config.dwellTailTolerance
        )
        guard let bounds = bounds(of: stroke),
              bounds.diagonal.isFinite,
              bounds.diagonal >= max(0, config.minDiagonal),
              hasAtLeastTwoDistinctPoints(stroke) else {
            return nil
        }

        let resampled = resample(points: stroke, spacing: config.resampleSpacing)
        guard resampled.count >= max(2, config.minPoints) else { return nil }

        let pathLength = polylineLength(resampled)
        // Closure uses the post-dwell-strip endpoints so a held tail cannot change the decision.
        let isClosed = isClosedStroke(
            points: stroke,
            pathLength: pathLength,
            boundingBoxDiagonal: bounds.diagonal
        )
        // A hand-drawn outline usually carries on a little past where it started. That tail runs
        // back along the path, and the reversal where it turns reads as an extra corner — which
        // is what turned drawn squares into pentagons.
        let outline = isClosed ? trimmedOvershoot(resampled) : resampled

        let epsilon = max(2.5, max(0, config.rdpEpsilonFraction) * bounds.diagonal)
        var simplified = rdpSimplify(points: outline, epsilon: epsilon)
        if isClosed,
           simplified.count > 1,
           let first = simplified.first,
           let last = simplified.last,
           distance(first, last) <= epsilon {
            simplified.removeLast()
        }

        let cornerCandidates = cornerVertices(
            points: simplified,
            isClosed: isClosed,
            thresholdDegrees: config.cornerAngleThresholdDegrees
        )
        let corners = mergedNeighbouringCorners(
            supportedCornerVertices(
                cornerCandidates,
                resampledPoints: outline,
                isClosed: isClosed,
                supportDistance: epsilon,
                thresholdDegrees: config.cornerAngleThresholdDegrees
            ),
            isClosed: isClosed,
            radius: epsilon * 2
        )
        let maximumCorners = max(0, config.maxCorners)

        if !isClosed {
            if corners.isEmpty {
                return fitLine(points: outline, config: config)
            }
            // Straightening answers to its own tighter ceiling and to a straightness gate of its
            // own: collapsing a word to a chord is unrecoverable, so nothing that wanders off that
            // chord is straightened, however few corners it turns out to carry. A stroke that
            // fails either test is rejected outright rather than falling back to the polyline it
            // was drawn as, because the reason it failed is that it does not look like a shape at
            // all.
            let openStrokeCeiling = config.straightensOpenPolylines
                ? max(0, config.maxStraightenedCorners)
                : maximumCorners
            guard corners.count <= openStrokeCeiling,
                  let first = simplified.first,
                  let last = simplified.last else {
                return nil
            }
            if config.straightensOpenPolylines {
                guard isStraightEnoughToCollapse(outline, config: config) else { return nil }
                return .polyline(vertices: [first, last], isClosed: false)
            }
            return .polyline(
                vertices: [first] + corners + [last],
                isClosed: false
            )
        }

        guard corners.count <= maximumCorners else { return nil }
        if corners.count == 4,
           hasRightAngles(corners, toleranceDegrees: config.rightAngleSnapDegrees),
           let rectangle = fitRectangle(corners: corners, config: config) {
            return .polyline(vertices: rectangle, isClosed: true)
        }
        if corners.count >= 3 {
            return .polyline(vertices: corners, isClosed: true)
        }
        return fitEllipse(points: outline, config: config)
    }

    static func finitePoints(_ points: [CGPoint]) -> [CGPoint] {
        points.filter { $0.x.isFinite && $0.y.isFinite }
    }

    static func stripTrailingDwellCluster(
        points: [CGPoint],
        tolerance: CGFloat
    ) -> [CGPoint] {
        guard points.count > 1, let last = points.last else { return points }

        let safeTolerance = max(0, tolerance)
        var clusterStart = points.count - 1
        while clusterStart > 0,
              distance(points[clusterStart - 1], last) <= safeTolerance {
            clusterStart -= 1
        }
        guard clusterStart < points.count - 1 else { return points }
        return Array(points[...clusterStart])
    }

    static func resample(points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        let points = removingConsecutiveDuplicates(points)
        guard points.count > 1 else { return points }
        guard spacing.isFinite, spacing > numericEpsilon else { return points }

        var result = [points[0]]
        var segmentStart = points[0]
        var carriedDistance: CGFloat = 0

        for segmentEnd in points.dropFirst() {
            var segmentLength = distance(segmentStart, segmentEnd)
            while carriedDistance + segmentLength >= spacing,
                  segmentLength > numericEpsilon {
                let remaining = spacing - carriedDistance
                let fraction = remaining / segmentLength
                let sample = interpolate(from: segmentStart, to: segmentEnd, fraction: fraction)
                result.append(sample)
                segmentStart = sample
                segmentLength = distance(segmentStart, segmentEnd)
                carriedDistance = 0
            }
            carriedDistance += segmentLength
            segmentStart = segmentEnd
        }

        if let last = points.last,
           let resultLast = result.last,
           distance(resultLast, last) > numericEpsilon {
            result.append(last)
        }
        return result
    }

    /// How far apart a stroke's endpoints may be and still describe a closed outline.
    static func closureTolerance(
        pathLength: CGFloat,
        boundingBoxDiagonal: CGFloat
    ) -> CGFloat {
        let absoluteClosureDistance: CGFloat = 12
        let pathLengthFraction: CGFloat = 0.15
        let diagonalFraction: CGFloat = 0.3
        let relativeThreshold = min(
            pathLengthFraction * pathLength,
            diagonalFraction * boundingBoxDiagonal
        )
        return max(absoluteClosureDistance, relativeThreshold)
    }

    static func isClosedStroke(
        points: [CGPoint],
        pathLength: CGFloat,
        boundingBoxDiagonal: CGFloat
    ) -> Bool {
        guard let first = points.first, let last = points.last else { return false }

        return distance(first, last) <= closureTolerance(
            pathLength: pathLength,
            boundingBoxDiagonal: boundingBoxDiagonal
        )
    }

    /// Cuts a closed outline at its closest approach to where it started, dropping any tail that
    /// ran on past that point. Searches only the last `maximumTailFraction` of the path, so a
    /// stroke that simply stops short of its start — the other way to close a shape by hand —
    /// keeps every point it was drawn with.
    static func trimmedOvershoot(
        _ points: [CGPoint],
        maximumTailFraction: CGFloat = 0.2
    ) -> [CGPoint] {
        guard points.count > 3, let start = points.first else { return points }

        let maximumTail = polylineLength(points) * max(0, maximumTailFraction)
        guard maximumTail > 0 else { return points }

        var closestIndex = points.count - 1
        var closestDistance = distance(points[closestIndex], start)
        var tail: CGFloat = 0
        var index = points.count - 1
        while index > 1, tail <= maximumTail {
            tail += distance(points[index], points[index - 1])
            index -= 1
            let candidate = distance(points[index], start)
            if candidate < closestDistance {
                closestDistance = candidate
                closestIndex = index
            }
        }

        guard closestIndex < points.count - 1 else { return points }
        return Array(points[...closestIndex])
    }

    /// Collapses corners that sit within `radius` of one another into their midpoint, so a seam
    /// landing just beside a real corner cannot inflate the corner count.
    static func mergedNeighbouringCorners(
        _ corners: [CGPoint],
        isClosed: Bool,
        radius: CGFloat
    ) -> [CGPoint] {
        let safeRadius = max(0, radius)
        guard corners.count > 1, safeRadius > 0 else { return corners }

        var merged: [CGPoint] = []
        for corner in corners {
            if let previous = merged.last, distance(previous, corner) <= safeRadius {
                merged[merged.count - 1] = CGPoint(
                    x: (previous.x + corner.x) / 2,
                    y: (previous.y + corner.y) / 2
                )
                continue
            }
            merged.append(corner)
        }

        if isClosed,
           merged.count > 2,
           let first = merged.first,
           let last = merged.last,
           distance(first, last) <= safeRadius {
            merged.removeLast()
            merged[0] = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        }
        return merged
    }

    static func rdpSimplify(points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let safeEpsilon = max(0, epsilon)
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var ranges = [(start: 0, end: points.count - 1)]

        while let range = ranges.popLast() {
            guard range.end - range.start > 1 else { continue }

            var farthestIndex: Int?
            var farthestDistance: CGFloat = -1
            for index in (range.start + 1)..<range.end {
                let candidateDistance = distanceToSegment(
                    points[index],
                    start: points[range.start],
                    end: points[range.end]
                )
                if candidateDistance > farthestDistance {
                    farthestDistance = candidateDistance
                    farthestIndex = index
                }
            }

            if farthestDistance > safeEpsilon, let farthestIndex {
                keep[farthestIndex] = true
                ranges.append((range.start, farthestIndex))
                ranges.append((farthestIndex, range.end))
            }
        }

        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    static func cornerVertices(
        points: [CGPoint],
        isClosed: Bool,
        thresholdDegrees: CGFloat
    ) -> [CGPoint] {
        let safeThreshold = max(0, thresholdDegrees)
        guard points.count >= (isClosed ? 3 : 2) else { return [] }

        if isClosed {
            return points.indices.compactMap { index in
                let previous = points[(index - 1 + points.count) % points.count]
                let current = points[index]
                let next = points[(index + 1) % points.count]
                guard let angle = turningAngleDegrees(previous, current, next),
                      angle > safeThreshold else {
                    return nil
                }
                return current
            }
        }

        guard points.count > 2 else { return [] }
        return (1..<(points.count - 1)).compactMap { index in
            guard let angle = turningAngleDegrees(
                points[index - 1],
                points[index],
                points[index + 1]
            ), angle > safeThreshold else {
                return nil
            }
            return points[index]
        }
    }

    static func fitLine(
        points: [CGPoint],
        config: ShapeRecognizerConfig
    ) -> RecognizedShape? {
        guard let first = points.first, let last = points.last else { return nil }

        let chordLength = distance(first, last)
        guard chordLength > numericEpsilon else { return nil }

        let center: CGPoint
        let direction: CGPoint
        if let axes = principalAxes(points), axes.majorVariance > numericEpsilon {
            center = axes.center
            direction = CGPoint(x: cos(axes.angle), y: sin(axes.angle))
        } else {
            center = first
            direction = CGPoint(
                x: (last.x - first.x) / chordLength,
                y: (last.y - first.y) / chordLength
            )
        }

        let maximumDeviation = points.reduce(CGFloat.zero) { currentMaximum, point in
            let offsetX = point.x - center.x
            let offsetY = point.y - center.y
            let deviation = abs(offsetX * direction.y - offsetY * direction.x)
            return max(currentMaximum, deviation)
        }
        let chordToleranceFraction: CGFloat = 0.04
        let tolerance = max(
            max(0, config.lineDeviationTolerance),
            chordToleranceFraction * chordLength
        )
        guard maximumDeviation <= tolerance else { return nil }

        // Straightness is judged against the drawn direction; the drawn direction is then pulled
        // onto an axis so a line meant to be horizontal or vertical actually is one.
        let snappedAngle = snappedAxisAngle(
            atan2(direction.y, direction.x),
            toleranceDegrees: config.axisAlignSnapDegrees
        )
        let snappedDirection = CGPoint(x: cos(snappedAngle), y: sin(snappedAngle))
        let projectedFirst = project(first, ontoLineThrough: center, direction: snappedDirection)
        let projectedLast = project(last, ontoLineThrough: center, direction: snappedDirection)
        return .polyline(vertices: [projectedFirst, projectedLast], isClosed: false)
    }

    /// Whether a stroke sits close enough to the chord between its endpoints for that chord to
    /// stand in for it, the judgement `fitLine` makes applied to the path that would otherwise
    /// discard every corner. Read the uniformly sampled stroke rather than the simplified one:
    /// simplification has already thrown away the detour this is here to notice.
    private static func isStraightEnoughToCollapse(
        _ points: [CGPoint],
        config: ShapeRecognizerConfig
    ) -> Bool {
        guard let first = points.first, let last = points.last else { return false }

        let chordLength = distance(first, last)
        guard chordLength > numericEpsilon else { return false }

        let direction = CGPoint(
            x: (last.x - first.x) / chordLength,
            y: (last.y - first.y) / chordLength
        )
        let maximumDeviation = points.reduce(CGFloat.zero) { currentMaximum, point in
            let offsetX = point.x - first.x
            let offsetY = point.y - first.y
            let deviation = abs(offsetX * direction.y - offsetY * direction.x)
            return max(currentMaximum, deviation)
        }
        let tolerance = max(
            max(0, config.lineDeviationTolerance),
            max(0, config.straightenedDeviationFraction) * chordLength
        )
        return maximumDeviation <= tolerance
    }

    /// RDP can make smooth high-curvature arcs look sharp. A corner must also be sharp at the
    /// simplification scale in the uniformly sampled stroke.
    private static func supportedCornerVertices(
        _ candidates: [CGPoint],
        resampledPoints: [CGPoint],
        isClosed: Bool,
        supportDistance: CGFloat,
        thresholdDegrees: CGFloat
    ) -> [CGPoint] {
        var samples = resampledPoints
        if isClosed,
           samples.count > 1,
           let first = samples.first,
           let last = samples.last,
           distance(first, last) <= max(supportDistance, numericEpsilon) {
            samples.removeLast()
        }
        guard samples.count >= 3 else { return [] }

        return candidates.filter { candidate in
            let nearestIndex = samples.indices.min {
                distance(samples[$0], candidate) < distance(samples[$1], candidate)
            }
            guard let nearestIndex,
                  let previousIndex = supportedSampleIndex(
                      from: nearestIndex,
                      direction: -1,
                      in: samples,
                      isClosed: isClosed,
                      distance: supportDistance
                  ),
                  let nextIndex = supportedSampleIndex(
                      from: nearestIndex,
                      direction: 1,
                      in: samples,
                      isClosed: isClosed,
                      distance: supportDistance
                  ),
                  let angle = turningAngleDegrees(
                      samples[previousIndex],
                      samples[nearestIndex],
                      samples[nextIndex]
                  ) else {
                return false
            }
            return angle > max(0, thresholdDegrees)
        }
    }

    private static func supportedSampleIndex(
        from startIndex: Int,
        direction: Int,
        in points: [CGPoint],
        isClosed: Bool,
        distance targetDistance: CGFloat
    ) -> Int? {
        let targetDistance = max(targetDistance, numericEpsilon)
        var index = startIndex
        var traveled: CGFloat = 0

        for _ in 1..<points.count {
            let nextIndex = index + direction
            let resolvedIndex: Int
            if isClosed {
                resolvedIndex = (nextIndex + points.count) % points.count
            } else {
                guard points.indices.contains(nextIndex) else { return nil }
                resolvedIndex = nextIndex
            }
            traveled += distance(points[index], points[resolvedIndex])
            index = resolvedIndex
            if traveled >= targetDistance {
                return index
            }
        }
        return nil
    }

    static func fitRectangle(
        corners: [CGPoint],
        config: ShapeRecognizerConfig
    ) -> [CGPoint]? {
        guard corners.count == 4 else { return nil }

        var longestEdgeIndex = 0
        var longestEdgeLength: CGFloat = -1
        for index in corners.indices {
            let edgeLength = distance(corners[index], corners[(index + 1) % corners.count])
            if edgeLength > longestEdgeLength {
                longestEdgeLength = edgeLength
                longestEdgeIndex = index
            }
        }
        guard longestEdgeLength > numericEpsilon else { return nil }

        // The longest drawn edge defines orientation; snapping only changes the fitted axes.
        let edgeStart = corners[longestEdgeIndex]
        let edgeEnd = corners[(longestEdgeIndex + 1) % corners.count]
        let rawAngle = atan2(edgeEnd.y - edgeStart.y, edgeEnd.x - edgeStart.x)
        let angle = snappedAxisAngle(
            rawAngle,
            toleranceDegrees: config.axisAlignSnapDegrees
        )
        let primaryAxis = CGPoint(x: cos(angle), y: sin(angle))
        let secondaryAxis = CGPoint(x: -sin(angle), y: cos(angle))
        let center = centroid(corners)

        var halfPrimary: CGFloat = 0
        var halfSecondary: CGFloat = 0
        for corner in corners {
            let offset = CGPoint(x: corner.x - center.x, y: corner.y - center.y)
            halfPrimary = max(halfPrimary, abs(dot(offset, primaryAxis)))
            halfSecondary = max(halfSecondary, abs(dot(offset, secondaryAxis)))
        }
        guard halfPrimary > numericEpsilon, halfSecondary > numericEpsilon else { return nil }

        // A rectangle drawn close enough to square becomes one, the same courtesy
        // `circleAxisRatio` extends to a near-circular ellipse.
        let sideRatio = min(halfPrimary, halfSecondary) / max(halfPrimary, halfSecondary)
        if sideRatio >= max(0, min(1, config.squareAxisRatio)) {
            let half = (halfPrimary + halfSecondary) / 2
            halfPrimary = half
            halfSecondary = half
        }

        return corners.map { corner in
            let offset = CGPoint(x: corner.x - center.x, y: corner.y - center.y)
            let primarySign: CGFloat = dot(offset, primaryAxis) < 0 ? -1 : 1
            let secondarySign: CGFloat = dot(offset, secondaryAxis) < 0 ? -1 : 1
            return CGPoint(
                x: center.x
                    + primarySign * halfPrimary * primaryAxis.x
                    + secondarySign * halfSecondary * secondaryAxis.x,
                y: center.y
                    + primarySign * halfPrimary * primaryAxis.y
                    + secondarySign * halfSecondary * secondaryAxis.y
            )
        }
    }

    static func fitEllipse(
        points: [CGPoint],
        config: ShapeRecognizerConfig
    ) -> RecognizedShape? {
        guard let axes = principalAxes(points) else { return nil }

        var radiusX = sqrt(max(0, 2 * axes.majorVariance))
        var radiusY = sqrt(max(0, 2 * axes.minorVariance))
        guard radiusX > numericEpsilon, radiusY > numericEpsilon else { return nil }

        let meanRadius = (radiusX + radiusY) / 2
        var residualSum: CGFloat = 0
        let cosine = cos(axes.angle)
        let sine = sin(axes.angle)
        for point in points {
            let offsetX = point.x - axes.center.x
            let offsetY = point.y - axes.center.y
            let localX = offsetX * cosine + offsetY * sine
            let localY = -offsetX * sine + offsetY * cosine
            let normalizedRadius = sqrt(
                (localX / radiusX) * (localX / radiusX)
                    + (localY / radiusY) * (localY / radiusY)
            )
            residualSum += abs(normalizedRadius - 1) * meanRadius
        }
        let meanResidual = residualSum / CGFloat(points.count)
        guard meanResidual <= max(0, config.ellipseResidualTolerance) * meanRadius else {
            return nil
        }

        let axisRatio = radiusY / radiusX
        if axisRatio >= max(0, config.circleAxisRatio) {
            let radius = meanRadius
            radiusX = radius
            radiusY = radius
            return .ellipse(
                center: axes.center,
                radiusX: radiusX,
                radiusY: radiusY,
                rotation: 0
            )
        }

        // radiusX is always the major radius; its axis is canonicalized to (-pi/2, pi/2].
        let rotation = snappedAxisAngle(
            canonicalEllipseAngle(axes.angle),
            toleranceDegrees: config.axisAlignSnapDegrees
        )
        return .ellipse(
            center: axes.center,
            radiusX: radiusX,
            radiusY: radiusY,
            rotation: canonicalEllipseAngle(rotation)
        )
    }

    private static func hasRightAngles(
        _ corners: [CGPoint],
        toleranceDegrees: CGFloat
    ) -> Bool {
        guard corners.count == 4 else { return false }
        let safeTolerance = max(0, toleranceDegrees)
        return corners.indices.allSatisfy { index in
            let previous = corners[(index - 1 + corners.count) % corners.count]
            let current = corners[index]
            let next = corners[(index + 1) % corners.count]
            guard let angle = interiorAngleDegrees(previous, current, next) else {
                return false
            }
            return abs(angle - 90) <= safeTolerance
        }
    }

    private static func principalAxes(_ points: [CGPoint]) -> PrincipalAxes? {
        guard points.count >= 2 else { return nil }

        let center = centroid(points)
        var xx: CGFloat = 0
        var xy: CGFloat = 0
        var yy: CGFloat = 0
        for point in points {
            let x = point.x - center.x
            let y = point.y - center.y
            xx += x * x
            xy += x * y
            yy += y * y
        }

        let divisor = CGFloat(points.count)
        xx /= divisor
        xy /= divisor
        yy /= divisor
        let discriminant = sqrt(max(0, (xx - yy) * (xx - yy) + 4 * xy * xy))
        let majorVariance = (xx + yy + discriminant) / 2
        let minorVariance = (xx + yy - discriminant) / 2
        guard majorVariance.isFinite, minorVariance.isFinite else { return nil }

        return PrincipalAxes(
            center: center,
            angle: 0.5 * atan2(2 * xy, xx - yy),
            majorVariance: max(0, majorVariance),
            minorVariance: max(0, minorVariance)
        )
    }

    private static func turningAngleDegrees(
        _ previous: CGPoint,
        _ current: CGPoint,
        _ next: CGPoint
    ) -> CGFloat? {
        angleDegrees(
            first: CGPoint(x: current.x - previous.x, y: current.y - previous.y),
            second: CGPoint(x: next.x - current.x, y: next.y - current.y)
        )
    }

    private static func interiorAngleDegrees(
        _ previous: CGPoint,
        _ current: CGPoint,
        _ next: CGPoint
    ) -> CGFloat? {
        angleDegrees(
            first: CGPoint(x: previous.x - current.x, y: previous.y - current.y),
            second: CGPoint(x: next.x - current.x, y: next.y - current.y)
        )
    }

    private static func angleDegrees(first: CGPoint, second: CGPoint) -> CGFloat? {
        let firstLength = hypot(first.x, first.y)
        let secondLength = hypot(second.x, second.y)
        guard firstLength > numericEpsilon, secondLength > numericEpsilon else { return nil }

        let cosine = min(max(dot(first, second) / (firstLength * secondLength), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func snappedAxisAngle(
        _ angle: CGFloat,
        toleranceDegrees: CGFloat
    ) -> CGFloat {
        let quarterTurn = CGFloat.pi / 2
        let snapped = (angle / quarterTurn).rounded() * quarterTurn
        let tolerance = max(0, toleranceDegrees) * .pi / 180
        return abs(angle - snapped) <= tolerance ? snapped : angle
    }

    private static func canonicalEllipseAngle(_ angle: CGFloat) -> CGFloat {
        var result = angle
        while result <= -.pi / 2 {
            result += .pi
        }
        while result > .pi / 2 {
            result -= .pi
        }
        return result
    }

    private static func hasAtLeastTwoDistinctPoints(_ points: [CGPoint]) -> Bool {
        guard let first = points.first else { return false }
        return points.dropFirst().contains { distance(first, $0) > numericEpsilon }
    }

    private static func removingConsecutiveDuplicates(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, distance(last, point) <= numericEpsilon {
                continue
            }
            result.append(point)
        }
        return result
    }

    private static func bounds(of points: [CGPoint]) -> PointBounds? {
        guard let first = points.first else { return nil }

        var minimumX = first.x
        var maximumX = first.x
        var minimumY = first.y
        var maximumY = first.y
        for point in points.dropFirst() {
            minimumX = min(minimumX, point.x)
            maximumX = max(maximumX, point.x)
            minimumY = min(minimumY, point.y)
            maximumY = max(maximumY, point.y)
        }
        return PointBounds(
            minimumX: minimumX,
            maximumX: maximumX,
            minimumY: minimumY,
            maximumY: maximumY
        )
    }

    private static func polylineLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(CGFloat.zero) {
            $0 + distance($1.0, $1.1)
        }
    }

    private static func distanceToSegment(
        _ point: CGPoint,
        start: CGPoint,
        end: CGPoint
    ) -> CGFloat {
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let squaredLength = dot(delta, delta)
        guard squaredLength > numericEpsilon else { return distance(point, start) }

        let offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
        let fraction = min(max(dot(offset, delta) / squaredLength, 0), 1)
        let projection = CGPoint(
            x: start.x + fraction * delta.x,
            y: start.y + fraction * delta.y
        )
        return distance(point, projection)
    }

    private static func project(
        _ point: CGPoint,
        ontoLineThrough center: CGPoint,
        direction: CGPoint
    ) -> CGPoint {
        let offset = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let scalar = dot(offset, direction)
        return CGPoint(
            x: center.x + scalar * direction.x,
            y: center.y + scalar * direction.y
        )
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let total = points.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        let divisor = CGFloat(points.count)
        return CGPoint(x: total.x / divisor, y: total.y / divisor)
    }

    private static func interpolate(
        from start: CGPoint,
        to end: CGPoint,
        fraction: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }

    private static func dot(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        first.x * second.x + first.y * second.y
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }

    private struct PrincipalAxes {
        let center: CGPoint
        let angle: CGFloat
        let majorVariance: CGFloat
        let minorVariance: CGFloat
    }

    private struct PointBounds {
        let minimumX: CGFloat
        let maximumX: CGFloat
        let minimumY: CGFloat
        let maximumY: CGFloat

        var diagonal: CGFloat {
            hypot(maximumX - minimumX, maximumY - minimumY)
        }
    }
}
