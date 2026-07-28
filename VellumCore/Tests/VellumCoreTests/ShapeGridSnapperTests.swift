import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Shape grid snapper")
struct ShapeGridSnapperTests {
    private let pageRect = CGRect(x: 0, y: 0, width: 768, height: 1086)

    @Test("A blank page offers nothing to align to")
    func blankPageHasNoGrid() {
        #expect(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .blank),
                pageRect: pageRect
            ) == nil
        )
    }

    @Test("Ruled paper aligns vertically only; grid and dots align on both axes")
    func gridAxesFollowTheBackgroundKind() throws {
        let ruled = try #require(
            ShapeGridSnapper.grid(for: PageBackgroundStyle(kind: .ruled), pageRect: pageRect)
        )
        #expect(!ruled.snapsX)
        #expect(ruled.snapsY)

        for kind in [PageBackgroundStyle.Kind.grid, .dots] {
            let grid = try #require(
                ShapeGridSnapper.grid(for: PageBackgroundStyle(kind: kind), pageRect: pageRect)
            )
            #expect(grid.snapsX)
            #expect(grid.snapsY)
        }
    }

    @Test("The lattice is measured from the page the shape sits on, not the canvas")
    func latticeUsesPageOrigin() throws {
        let secondPage = PageGeometry.a4.pageRect(index: 1)
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .grid, spacing: 24),
                pageRect: secondPage
            )
        )

        let snapped = ShapeGridSnapper.snappedPoint(
            CGPoint(x: 47, y: secondPage.minY + 71),
            to: grid
        )
        #expect(abs(snapped.x - 48) < 0.001)
        #expect(abs(snapped.y - (secondPage.minY + 72)) < 0.001)
    }

    @Test("A horizontal line lands on a rule and stays horizontal")
    func horizontalLineSnapsToARule() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .ruled, spacing: 24),
                pageRect: pageRect
            )
        )
        let snapped = ShapeGridSnapper.snapped(
            .polyline(
                vertices: [CGPoint(x: 30, y: 118), CGPoint(x: 300, y: 118)],
                isClosed: false
            ),
            to: grid
        )

        guard case .polyline(let vertices, _) = snapped else {
            Issue.record("expected a polyline")
            return
        }
        #expect(abs(vertices[0].y - 120) < 0.001)
        #expect(abs(vertices[1].y - 120) < 0.001)
        // Ruled paper has no columns, so the ends keep the length they were drawn with.
        #expect(abs(vertices[0].x - 30) < 0.001)
        #expect(abs(vertices[1].x - 300) < 0.001)
    }

    @Test("A coordinate further away than the tolerance is left alone")
    func farCoordinatesAreLeftAlone() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .grid, spacing: 24),
                pageRect: pageRect
            )
        )
        // Tolerance is 30% of 24pt, so 7.2pt: a point 10pt off the lattice stays put.
        let snapped = ShapeGridSnapper.snappedPoint(CGPoint(x: 58, y: 58), to: grid)
        #expect(abs(snapped.x - 58) < 0.001)
        #expect(abs(snapped.y - 58) < 0.001)
    }

    @Test("A tilted line is never distorted by the lattice")
    func tiltedLinesAreUntouched() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .dots, spacing: 24),
                pageRect: pageRect
            )
        )
        let original = RecognizedShape.polyline(
            vertices: [CGPoint(x: 25, y: 25), CGPoint(x: 190, y: 121)],
            isClosed: false
        )

        #expect(ShapeGridSnapper.snapped(original, to: grid) == original)
    }

    @Test("An axis-aligned rectangle moves onto the lattice without changing size")
    func rectangleTranslatesOntoTheLattice() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .grid, spacing: 24),
                pageRect: pageRect
            )
        )
        let snapped = ShapeGridSnapper.snapped(
            .polyline(
                vertices: [
                    CGPoint(x: 26, y: 50),
                    CGPoint(x: 194, y: 50),
                    CGPoint(x: 194, y: 145),
                    CGPoint(x: 26, y: 145),
                ],
                isClosed: true
            ),
            to: grid
        )

        guard case .polyline(let vertices, let isClosed) = snapped else {
            Issue.record("expected a polyline")
            return
        }
        #expect(isClosed)
        #expect(vertices.count == 4)
        // The minimum corner lands on the lattice and the whole shape follows it, so the
        // rectangle keeps the width and height the recognizer gave it.
        #expect(abs(vertices[0].x - 24) < 0.001)
        #expect(abs(vertices[0].y - 48) < 0.001)
        #expect(abs((vertices[1].x - vertices[0].x) - 168) < 0.001)
        #expect(abs((vertices[2].y - vertices[1].y) - 95) < 0.001)
        #expect(abs(vertices[0].y - vertices[1].y) < 0.001)
        #expect(abs(vertices[1].x - vertices[2].x) < 0.001)
    }

    @Test("A rotated rectangle is left alone")
    func rotatedRectangleIsUntouched() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .grid, spacing: 24),
                pageRect: pageRect
            )
        )
        let original = RecognizedShape.polyline(
            vertices: [
                CGPoint(x: 100, y: 50),
                CGPoint(x: 170, y: 96),
                CGPoint(x: 124, y: 166),
                CGPoint(x: 54, y: 120),
            ],
            isClosed: true
        )

        #expect(ShapeGridSnapper.snapped(original, to: grid) == original)
    }

    @Test("A snapped square stays square")
    func squareStaysSquare() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .grid, spacing: 24),
                pageRect: pageRect
            )
        )
        let side: CGFloat = 137
        let snapped = ShapeGridSnapper.snapped(
            .polyline(
                vertices: [
                    CGPoint(x: 26, y: 50),
                    CGPoint(x: 26 + side, y: 50),
                    CGPoint(x: 26 + side, y: 50 + side),
                    CGPoint(x: 26, y: 50 + side),
                ],
                isClosed: true
            ),
            to: grid
        )

        guard case .polyline(let vertices, _) = snapped else {
            Issue.record("expected a polyline")
            return
        }
        let width = vertices[1].x - vertices[0].x
        let height = vertices[2].y - vertices[1].y
        #expect(abs(width - height) < 0.001)
        #expect(abs(width - side) < 0.001)
    }

    @Test("An upright ellipse aligns its bounding box")
    func uprightEllipseSnapsItsBox() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .dots, spacing: 24),
                pageRect: pageRect
            )
        )
        // Box spans 50…142 by 50…118; its minimum corner is 2pt off the dot at (48, 48), so the
        // whole ellipse shifts by that much and keeps both radii.
        let snapped = ShapeGridSnapper.snapped(
            .ellipse(
                center: CGPoint(x: 96, y: 84),
                radiusX: 46,
                radiusY: 34,
                rotation: 0
            ),
            to: grid
        )

        guard case .ellipse(let center, let radiusX, let radiusY, _) = snapped else {
            Issue.record("expected an ellipse")
            return
        }
        #expect(abs(center.x - 94) < 0.001)
        #expect(abs(center.y - 82) < 0.001)
        #expect(abs(radiusX - 46) < 0.001)
        #expect(abs(radiusY - 34) < 0.001)
    }

    @Test("A tilted ellipse is left alone")
    func tiltedEllipseIsUntouched() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .dots, spacing: 24),
                pageRect: pageRect
            )
        )
        let original = RecognizedShape.ellipse(
            center: CGPoint(x: 108, y: 84),
            radiusX: 47,
            radiusY: 35,
            rotation: .pi / 6
        )

        #expect(ShapeGridSnapper.snapped(original, to: grid) == original)
    }

    @Test("A small ellipse is moved onto the lattice, never shrunk onto it")
    func tinyEllipseKeepsItsRadii() throws {
        let grid = try #require(
            ShapeGridSnapper.grid(
                for: PageBackgroundStyle(kind: .dots, spacing: 24),
                pageRect: pageRect
            )
        )
        // Box spans 43…53, so the corner pulls to the dot at 48 and the circle slides 5pt.
        guard case .ellipse(let center, let radiusX, let radiusY, _) = ShapeGridSnapper.snapped(
            .ellipse(center: CGPoint(x: 48, y: 48), radiusX: 5, radiusY: 5, rotation: 0),
            to: grid
        ) else {
            Issue.record("expected an ellipse")
            return
        }
        #expect(abs(radiusX - 5) < 0.001)
        #expect(abs(radiusY - 5) < 0.001)
        #expect(abs(center.x - 53) < 0.001)
        #expect(abs(center.y - 53) < 0.001)
    }
}
