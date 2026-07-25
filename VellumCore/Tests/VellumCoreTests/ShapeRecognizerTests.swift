import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Suite("Shape recognizer")
struct ShapeRecognizerTests {
    @Test("Lines at horizontal, diagonal, and near-vertical angles fit two endpoints")
    func recognizesLinesAtSeveralAngles() throws {
        let cases: [(start: CGPoint, end: CGPoint, seed: UInt64)] = [
            (CGPoint(x: 10, y: 20), CGPoint(x: 150, y: 20), 1),
            (
                CGPoint(x: 20, y: 30),
                CGPoint(
                    x: 20 + 140 * cos(CGFloat.pi / 6),
                    y: 30 + 140 * sin(CGFloat.pi / 6)
                ),
                2
            ),
            (CGPoint(x: 80, y: 10), CGPoint(x: 83, y: 170), 3),
        ]

        for lineCase in cases {
            let stroke = jittered(
                sampleChain([lineCase.start, lineCase.end], spacing: 3),
                amplitude: 0.7,
                seed: lineCase.seed
            )
            let vertices = try openPolylineVertices(
                from: ShapeRecognizer.recognize(points: stroke)
            )

            #expect(vertices.count == 2)
            #expect(distance(vertices[0], lineCase.start) < 3)
            #expect(distance(vertices[1], lineCase.end) < 3)
        }
    }

    @Test("A line drawn slightly off an axis is pulled onto it")
    func snapsNearAxisLinesToTheAxis() throws {
        let nearHorizontal = try openPolylineVertices(
            from: ShapeRecognizer.recognize(
                points: jittered(
                    sampleChain(
                        [CGPoint(x: 20, y: 60), CGPoint(x: 180, y: 68)],
                        spacing: 3
                    ),
                    amplitude: 0.5,
                    seed: 40
                )
            )
        )
        #expect(nearHorizontal.count == 2)
        #expect(abs(nearHorizontal[1].y - nearHorizontal[0].y) < 0.001)

        let nearVertical = try openPolylineVertices(
            from: ShapeRecognizer.recognize(
                points: jittered(
                    sampleChain(
                        [CGPoint(x: 60, y: 20), CGPoint(x: 52, y: 180)],
                        spacing: 3
                    ),
                    amplitude: 0.5,
                    seed: 41
                )
            )
        )
        #expect(nearVertical.count == 2)
        #expect(abs(nearVertical[1].x - nearVertical[0].x) < 0.001)
    }

    @Test("A line well off an axis keeps the angle it was drawn at")
    func leavesOffAxisLinesAlone() throws {
        let start = CGPoint(x: 20, y: 30)
        let end = CGPoint(x: 20 + 140 * cos(CGFloat.pi / 6), y: 30 + 140 * sin(CGFloat.pi / 6))
        let vertices = try openPolylineVertices(
            from: ShapeRecognizer.recognize(
                points: jittered(sampleChain([start, end], spacing: 3), amplitude: 0.5, seed: 42)
            )
        )

        #expect(vertices.count == 2)
        let angle = atan2(vertices[1].y - vertices[0].y, vertices[1].x - vertices[0].x)
        #expect(abs(angle - .pi / 6) < 0.05)
    }

    @Test("A square left open at the seam still closes into a square")
    func closesAGappedSquare() throws {
        let truth = [
            CGPoint(x: 40, y: 40),
            CGPoint(x: 240, y: 40),
            CGPoint(x: 240, y: 240),
            CGPoint(x: 40, y: 240),
        ]
        let stroke = jitteredOpenLoop(truth, gap: 20, amplitude: 0.6, seed: 43)
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 4)
        expectRightAngles(vertices, tolerance: 0.001)
        let sides = vertices.indices.map { index in
            distance(vertices[index], vertices[(index + 1) % vertices.count])
        }
        for side in sides {
            #expect(abs(side - sides[0]) < 0.001)
        }
    }

    @Test("A square whose stroke runs past its own start still closes into a square")
    func closesAnOvershotSquare() throws {
        let truth = [
            CGPoint(x: 40, y: 40),
            CGPoint(x: 240, y: 40),
            CGPoint(x: 240, y: 240),
            CGPoint(x: 40, y: 240),
        ]
        // Carrying on 20pt past the start doubles the path back on itself; that reversal used to
        // read as a fifth corner, which is what turned hand-drawn squares into pentagons.
        let stroke = jittered(
            sampleChain(truth + [CGPoint(x: 40, y: 20)], spacing: 3),
            amplitude: 0.6,
            seed: 46
        )
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 4)
        expectRightAngles(vertices, tolerance: 0.001)
    }

    @Test("A gapped rectangle that is not square keeps its proportions")
    func keepsAGappedRectangleRectangular() throws {
        let truth = [
            CGPoint(x: 40, y: 40),
            CGPoint(x: 280, y: 40),
            CGPoint(x: 280, y: 140),
            CGPoint(x: 40, y: 140),
        ]
        let stroke = jitteredOpenLoop(truth, gap: 20, amplitude: 0.6, seed: 44)
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 4)
        expectRightAngles(vertices, tolerance: 0.001)
        let width = distance(vertices[0], vertices[1])
        let height = distance(vertices[1], vertices[2])
        #expect(min(width, height) / max(width, height) < 0.6)
    }

    @Test("A pentagon left open at the seam is still a pentagon")
    func keepsAGappedPentagonFiveSided() throws {
        let truth = regularPolygon(center: CGPoint(x: 140, y: 140), radius: 100, vertexCount: 5)
        let stroke = jitteredOpenLoop(truth, gap: 18, amplitude: 0.5, seed: 45)
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 5)
    }

    @Test("A smooth bowed stroke is not accepted as a line or polyline")
    func rejectsBowedArc() {
        let points = (0...48).map { index in
            let fraction = CGFloat(index) / 48
            return CGPoint(
                x: 140 * fraction,
                y: 24 * sin(.pi * fraction)
            )
        }

        #expect(ShapeRecognizer.recognize(points: points) == nil)
    }

    @Test("An open V straightens to a line between its endpoints by default")
    func straightensOpenV() throws {
        let truth = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 70, y: 80),
            CGPoint(x: 135, y: 12),
        ]
        let stroke = jittered(sampleChain(truth, spacing: 3), amplitude: 0.6, seed: 10)
        let vertices = try openPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 2)
        expectVertices(vertices, near: [truth[0], truth[2]], tolerance: 4)
    }

    @Test("An open W straightens to a line between its endpoints by default")
    func straightensOpenW() throws {
        let truth = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 50, y: 70),
            CGPoint(x: 90, y: 10),
            CGPoint(x: 130, y: 70),
            CGPoint(x: 170, y: 10),
        ]
        let stroke = jittered(sampleChain(truth, spacing: 3), amplitude: 0.5, seed: 11)
        let vertices = try openPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 2)
        expectVertices(vertices, near: [truth[0], truth[4]], tolerance: 4)
    }

    @Test("A closed shape keeps its corners while open strokes straighten")
    func straighteningLeavesClosedShapesAlone() throws {
        let truth = [
            CGPoint(x: 20, y: 20),
            CGPoint(x: 140, y: 30),
            CGPoint(x: 80, y: 130),
        ]
        let stroke = jitteredClosedPolygon(truth, amplitude: 0.6, seed: 12)
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 3)
        expectEachTruthVertexHasMatch(truth, in: vertices, tolerance: 5)
    }

    @Test("An open V emits one corner between its endpoints when straightening is off")
    func recognizesOpenV() throws {
        let truth = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 70, y: 80),
            CGPoint(x: 135, y: 12),
        ]
        let stroke = jittered(sampleChain(truth, spacing: 3), amplitude: 0.6, seed: 10)
        let vertices = try openPolylineVertices(
            from: ShapeRecognizer.recognize(
                points: stroke,
                config: ShapeRecognizerConfig(straightensOpenPolylines: false)
            )
        )

        #expect(vertices.count == 3)
        expectVertices(vertices, near: truth, tolerance: 4)
    }

    @Test("An open W emits three corners between its endpoints when straightening is off")
    func recognizesOpenW() throws {
        let truth = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 50, y: 70),
            CGPoint(x: 90, y: 10),
            CGPoint(x: 130, y: 70),
            CGPoint(x: 170, y: 10),
        ]
        let stroke = jittered(sampleChain(truth, spacing: 3), amplitude: 0.5, seed: 11)
        let vertices = try openPolylineVertices(
            from: ShapeRecognizer.recognize(
                points: stroke,
                config: ShapeRecognizerConfig(straightensOpenPolylines: false)
            )
        )

        #expect(vertices.count == 5)
        expectVertices(vertices, near: truth, tolerance: 4)
    }

    @Test("A closed triangle emits its three drawn corners")
    func recognizesTriangle() throws {
        let truth = [
            CGPoint(x: 25, y: 105),
            CGPoint(x: 85, y: 15),
            CGPoint(x: 150, y: 110),
        ]
        let stroke = jitteredClosedPolygon(truth, amplitude: 0.6, seed: 20)
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 3)
        expectEachTruthVertexHasMatch(truth, in: vertices, tolerance: 4)
    }

    @Test("An axis-aligned rectangle snaps to exact orthogonal axes")
    func recognizesAxisAlignedRectangle() throws {
        let truth = [
            CGPoint(x: 20, y: 30),
            CGPoint(x: 160, y: 30),
            CGPoint(x: 160, y: 110),
            CGPoint(x: 20, y: 110),
        ]
        let stroke = jitteredClosedPolygon(truth, amplitude: 0.6, seed: 21)
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 4)
        expectRightAngles(vertices, tolerance: 0.001)
        for index in vertices.indices {
            let next = vertices[(index + 1) % vertices.count]
            let deltaX = abs(next.x - vertices[index].x)
            let deltaY = abs(next.y - vertices[index].y)
            #expect(min(deltaX, deltaY) < 0.001)
        }
    }

    @Test("A rectangle tilted thirty degrees preserves its tilt")
    func recognizesTiltedRectangle() throws {
        let angle = CGFloat.pi / 6
        let truth = rotated(
            [
                CGPoint(x: -70, y: -35),
                CGPoint(x: 70, y: -35),
                CGPoint(x: 70, y: 35),
                CGPoint(x: -70, y: 35),
            ],
            by: angle,
            around: CGPoint(x: 110, y: 100)
        )
        let stroke = jitteredClosedPolygon(truth, amplitude: 0.5, seed: 22)
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 4)
        expectRightAngles(vertices, tolerance: 0.001)
        let firstEdgeAngle = atan2(
            vertices[1].y - vertices[0].y,
            vertices[1].x - vertices[0].x
        )
        #expect(axisAngleDifference(firstEdgeAngle, angle) < 5 * .pi / 180)
    }

    @Test("A regular pentagon remains a five-corner polygon")
    func recognizesPentagon() throws {
        let center = CGPoint(x: 100, y: 100)
        let truth = regularPolygon(center: center, radius: 75, vertexCount: 5)
        let stroke = jitteredClosedPolygon(truth, amplitude: 0.5, seed: 23)
        let vertices = try closedPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(vertices.count == 5)
        expectEachTruthVertexHasMatch(truth, in: vertices, tolerance: 4)
    }

    @Test("A circle equalizes the fitted radii")
    func recognizesCircle() throws {
        let center = CGPoint(x: 120, y: 90)
        let radius: CGFloat = 62
        let stroke = jitteredClosedCurve(
            ellipseSamples(
                center: center,
                radiusX: radius,
                radiusY: radius,
                rotation: 0
            ),
            amplitude: 0.6,
            seed: 30
        )
        let ellipse = try ellipseValues(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(distance(ellipse.center, center) < 3)
        #expect(ellipse.radiusX == ellipse.radiusY)
        #expect(abs(ellipse.radiusX - radius) / radius < 0.05)
        #expect(ellipse.rotation == 0)
    }

    @Test("An axis-aligned two-to-one ellipse snaps its rotation to zero")
    func recognizesAxisAlignedEllipse() throws {
        let center = CGPoint(x: 120, y: 100)
        let stroke = jitteredClosedCurve(
            ellipseSamples(
                center: center,
                radiusX: 80,
                radiusY: 40,
                rotation: 0
            ),
            amplitude: 0.4,
            seed: 31
        )
        let ellipse = try ellipseValues(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(distance(ellipse.center, center) < 3)
        #expect(ellipse.radiusX > ellipse.radiusY)
        #expect(abs(ellipse.rotation) < 0.0001)
    }

    @Test("A rotated two-to-one ellipse preserves a thirty-degree orientation")
    func recognizesRotatedEllipse() throws {
        let center = CGPoint(x: 120, y: 100)
        let expectedRotation = CGFloat.pi / 6
        let stroke = jitteredClosedCurve(
            ellipseSamples(
                center: center,
                radiusX: 80,
                radiusY: 40,
                rotation: expectedRotation
            ),
            amplitude: 0.4,
            seed: 32
        )
        let ellipse = try ellipseValues(
            from: ShapeRecognizer.recognize(points: stroke)
        )

        #expect(distance(ellipse.center, center) < 3)
        #expect(ellipse.radiusX > ellipse.radiusY)
        #expect(
            ellipseAngleDifference(ellipse.rotation, expectedRotation)
                < 5 * .pi / 180
        )
    }

    @Test("An incoherent deterministic random walk is rejected")
    func rejectsRandomScribble() {
        var generator = LCG(seed: 40)
        var point = CGPoint(x: 100, y: 100)
        var stroke = [point]
        for _ in 0..<180 {
            let angle = generator.nextUnit() * 2 * .pi
            let length = 5 + generator.nextUnit() * 7
            point.x += cos(angle) * length
            point.y += sin(angle) * length
            stroke.append(point)
        }

        #expect(ShapeRecognizer.recognize(points: stroke) == nil)
    }

    @Test("A shape below the minimum diagonal is rejected")
    func rejectsTinyShape() {
        let stroke = ellipseSamples(
            center: CGPoint(x: 20, y: 20),
            radiusX: 5,
            radiusY: 5,
            rotation: 0,
            sampleCount: 40
        )

        #expect(ShapeRecognizer.recognize(points: stroke) == nil)
    }

    @Test("A long trailing dwell cluster is stripped before line fitting")
    func stripsDwellTailFromLine() throws {
        var stroke = sampleChain(
            [CGPoint(x: 10, y: 20), CGPoint(x: 150, y: 20)],
            spacing: 4
        )
        for index in 0..<30 {
            let offset = CGFloat(index % 5) * 0.08
            stroke.append(CGPoint(x: 150 + offset, y: 20 - offset))
        }

        let vertices = try openPolylineVertices(
            from: ShapeRecognizer.recognize(points: stroke)
        )
        #expect(vertices.count == 2)
        #expect(abs(vertices[0].y - 20) < 0.001)
        #expect(abs(vertices[1].y - 20) < 0.001)
    }

    private func openPolylineVertices(from shape: RecognizedShape?) throws -> [CGPoint] {
        guard case .polyline(let vertices, let isClosed) = shape else {
            Issue.record("Expected an open polyline, got \(String(describing: shape)).")
            return []
        }
        #expect(isClosed == false)
        return vertices
    }

    private func closedPolylineVertices(from shape: RecognizedShape?) throws -> [CGPoint] {
        guard case .polyline(let vertices, let isClosed) = shape else {
            Issue.record("Expected a closed polyline, got \(String(describing: shape)).")
            return []
        }
        #expect(isClosed)
        return vertices
    }

    private func ellipseValues(
        from shape: RecognizedShape?
    ) throws -> (center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, rotation: CGFloat) {
        guard case .ellipse(let center, let radiusX, let radiusY, let rotation) = shape else {
            Issue.record("Expected an ellipse, got \(String(describing: shape)).")
            return (.zero, 0, 0, 0)
        }
        return (center, radiusX, radiusY, rotation)
    }

    private func expectVertices(
        _ actual: [CGPoint],
        near expected: [CGPoint],
        tolerance: CGFloat
    ) {
        guard actual.count == expected.count else { return }
        for (actualVertex, expectedVertex) in zip(actual, expected) {
            #expect(distance(actualVertex, expectedVertex) < tolerance)
        }
    }

    private func expectEachTruthVertexHasMatch(
        _ truth: [CGPoint],
        in actual: [CGPoint],
        tolerance: CGFloat
    ) {
        for truthVertex in truth {
            let nearestDistance = actual.map { distance($0, truthVertex) }.min() ?? .infinity
            #expect(nearestDistance < tolerance)
        }
    }

    private func expectRightAngles(_ vertices: [CGPoint], tolerance: CGFloat) {
        guard vertices.count == 4 else { return }
        for index in vertices.indices {
            let previous = vertices[(index - 1 + vertices.count) % vertices.count]
            let current = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            let first = CGPoint(x: previous.x - current.x, y: previous.y - current.y)
            let second = CGPoint(x: next.x - current.x, y: next.y - current.y)
            let cosine = dot(first, second) / (hypot(first.x, first.y) * hypot(second.x, second.y))
            let angle = acos(min(max(cosine, -1), 1))
            #expect(abs(angle - .pi / 2) < tolerance)
        }
    }

    private func sampleChain(_ vertices: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard let first = vertices.first else { return [] }
        var result = [first]
        for (start, end) in zip(vertices, vertices.dropFirst()) {
            let length = distance(start, end)
            let segmentCount = max(1, Int(ceil(length / spacing)))
            for index in 1...segmentCount {
                let fraction = CGFloat(index) / CGFloat(segmentCount)
                result.append(
                    CGPoint(
                        x: start.x + (end.x - start.x) * fraction,
                        y: start.y + (end.y - start.y) * fraction
                    )
                )
            }
        }
        if let endpoint = result.last {
            result.removeLast()
            while let previous = result.last, distance(previous, endpoint) <= 8 {
                result.removeLast()
            }
            result.append(endpoint)
        }
        return result
    }

    /// A closed outline drawn the way a hand draws one: coming back around to `gap` points short
    /// of where it started, rather than meeting the start exactly.
    private func jitteredOpenLoop(
        _ vertices: [CGPoint],
        gap: CGFloat,
        amplitude: CGFloat,
        seed: UInt64
    ) -> [CGPoint] {
        guard let first = vertices.first, let last = vertices.last else { return [] }
        let closingLength = distance(last, first)
        guard closingLength > gap else { return [] }

        let fraction = (closingLength - gap) / closingLength
        let stop = CGPoint(
            x: last.x + (first.x - last.x) * fraction,
            y: last.y + (first.y - last.y) * fraction
        )
        return jittered(
            sampleChain(vertices + [stop], spacing: 3),
            amplitude: amplitude,
            seed: seed
        )
    }

    private func jitteredClosedPolygon(
        _ vertices: [CGPoint],
        amplitude: CGFloat,
        seed: UInt64
    ) -> [CGPoint] {
        guard let first = vertices.first else { return [] }
        return jitteredClosedCurve(
            sampleChain(vertices + [first], spacing: 3),
            amplitude: amplitude,
            seed: seed
        )
    }

    private func jitteredClosedCurve(
        _ points: [CGPoint],
        amplitude: CGFloat,
        seed: UInt64
    ) -> [CGPoint] {
        var result = jittered(points, amplitude: amplitude, seed: seed)
        if let first = result.first, !result.isEmpty {
            result.removeLast()
            while let previous = result.last, distance(previous, first) <= 8 {
                result.removeLast()
            }
            result.append(first)
        }
        return result
    }

    private func jittered(
        _ points: [CGPoint],
        amplitude: CGFloat,
        seed: UInt64
    ) -> [CGPoint] {
        var generator = LCG(seed: seed)
        return points.map { point in
            CGPoint(
                x: point.x + generator.nextSigned() * amplitude,
                y: point.y + generator.nextSigned() * amplitude
            )
        }
    }

    private func ellipseSamples(
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: CGFloat,
        sampleCount: Int = 180
    ) -> [CGPoint] {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return (0...sampleCount).map { index in
            let angle = -CGFloat.pi / 2
                + 2 * CGFloat.pi * CGFloat(index) / CGFloat(sampleCount)
            let localX = radiusX * cos(angle)
            let localY = radiusY * sin(angle)
            return CGPoint(
                x: center.x + localX * cosine - localY * sine,
                y: center.y + localX * sine + localY * cosine
            )
        }
    }

    private func regularPolygon(
        center: CGPoint,
        radius: CGFloat,
        vertexCount: Int
    ) -> [CGPoint] {
        (0..<vertexCount).map { index in
            let angle = -.pi / 2 + 2 * .pi * CGFloat(index) / CGFloat(vertexCount)
            return CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }

    private func rotated(
        _ localPoints: [CGPoint],
        by angle: CGFloat,
        around center: CGPoint
    ) -> [CGPoint] {
        let cosine = cos(angle)
        let sine = sin(angle)
        return localPoints.map { point in
            CGPoint(
                x: center.x + point.x * cosine - point.y * sine,
                y: center.y + point.x * sine + point.y * cosine
            )
        }
    }

    private func axisAngleDifference(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let quarterTurn = CGFloat.pi / 2
        var difference = abs(first - second).truncatingRemainder(dividingBy: quarterTurn)
        difference = min(difference, quarterTurn - difference)
        return difference
    }

    private func ellipseAngleDifference(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        var difference = abs(first - second).truncatingRemainder(dividingBy: .pi)
        difference = min(difference, .pi - difference)
        return difference
    }

    private func dot(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        first.x * second.x + first.y * second.y
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }
}

private struct LCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let fraction = Double(state >> 11) / Double(UInt64(1) << 53)
        return CGFloat(fraction)
    }

    mutating func nextSigned() -> CGFloat {
        nextUnit() * 2 - 1
    }
}
