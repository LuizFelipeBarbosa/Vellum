import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Suite("Selection resize math")
struct SelectionResizeMathTests {
    private let bounds = CGRect(x: 20, y: 30, width: 100, height: 60)
    private let mathAccuracy: CGFloat = 1e-9
    private let rotationAccuracy: CGFloat = 1e-6

    @Test("Opposite unit points mirror every resize handle")
    func oppositeUnitPointsMirrorResizeHandles() {
        let cases: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)),
            (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
            (CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)),
            (CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5)),
            (CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0)),
            (CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)),
            (CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0)),
            (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
            (SelectionResizeMath.centerUnit, SelectionResizeMath.centerUnit),
        ]

        for (unit, expected) in cases {
            expectPoint(
                SelectionResizeMath.oppositeUnit(of: unit),
                equal: expected,
                accuracy: mathAccuracy
            )
        }
    }

    @Test("Pure anchored scaling pins every resize anchor before and after committed rotation")
    func pureAnchoredScalingPinsEveryResizeAnchor() {
        let anchors = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.5, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 0.5),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0.5, y: 1),
            CGPoint(x: 0, y: 1),
            CGPoint(x: 0, y: 0.5),
        ]

        for anchorUnit in anchors {
            for committedRotation in [0.0, 0.4] {
                let anchor = SelectionResizeMath.point(
                    atUnit: anchorUnit,
                    in: bounds,
                    rotation: committedRotation
                )
                let transform = SelectionResizeMath.transform(
                    bounds: bounds,
                    anchorUnit: anchorUnit,
                    scale: CGSize(width: 1.7, height: 0.65),
                    rotationDelta: 0,
                    committedRotation: committedRotation
                )

                expectPoint(
                    anchor.applying(transform),
                    equal: anchor,
                    accuracy: rotationAccuracy
                )
            }
        }
    }

    @Test("Center uniform transform matches the existing center composite")
    func centerUniformTransformMatchesExistingComposite() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scale = CGSize(width: 1.4, height: 1.4)
        let rotationDelta = 0.27
        let actual = SelectionResizeMath.transform(
            bounds: bounds,
            anchorUnit: SelectionResizeMath.centerUnit,
            scale: scale,
            rotationDelta: rotationDelta,
            committedRotation: 0.4
        )
        let expected = CGAffineTransform(
            translationX: -center.x,
            y: -center.y
        )
        .concatenating(
            CGAffineTransform(scaleX: scale.width, y: scale.height)
        )
        .concatenating(
            CGAffineTransform(rotationAngle: CGFloat(rotationDelta))
        )
        .concatenating(
            CGAffineTransform(translationX: center.x, y: center.y)
        )

        expectTransform(actual, equal: expected, accuracy: rotationAccuracy)
    }

    @Test("Center non-uniform scale stays aligned to committed chrome axes")
    func centerNonUniformScaleStaysAlignedToCommittedAxes() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scale = CGSize(width: 1.8, height: 0.7)
        let committedRotation = 0.4
        let actual = SelectionResizeMath.transform(
            bounds: bounds,
            anchorUnit: SelectionResizeMath.centerUnit,
            scale: scale,
            rotationDelta: 0,
            committedRotation: committedRotation
        )
        let expected = CGAffineTransform(
            translationX: -center.x,
            y: -center.y
        )
        .concatenating(
            CGAffineTransform(rotationAngle: -CGFloat(committedRotation))
        )
        .concatenating(
            CGAffineTransform(scaleX: scale.width, y: scale.height)
        )
        .concatenating(
            CGAffineTransform(rotationAngle: CGFloat(committedRotation))
        )
        .concatenating(
            CGAffineTransform(translationX: center.x, y: center.y)
        )

        expectTransform(actual, equal: expected, accuracy: rotationAccuracy)
    }

    @Test("Chrome transform is derived from committed rotation and interaction transform")
    func chromeTransformUsesInteractionTransform() {
        let anchorUnit = CGPoint(x: 0, y: 1)
        let scale = CGSize(width: 1.6, height: 0.75)
        let rotationDelta = -0.2
        let committedRotation = 0.4
        let interactionTransform = SelectionResizeMath.transform(
            bounds: bounds,
            anchorUnit: anchorUnit,
            scale: scale,
            rotationDelta: rotationDelta,
            committedRotation: committedRotation
        )
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let expected = rotation(
            CGFloat(committedRotation),
            about: center
        )
        .concatenating(interactionTransform)
        let actual = SelectionResizeMath.chromeTransform(
            bounds: bounds,
            anchorUnit: anchorUnit,
            scale: scale,
            rotationDelta: rotationDelta,
            committedRotation: committedRotation
        )

        expectTransform(actual, equal: expected, accuracy: mathAccuracy)
    }

    @Test("Corner factor uses a signed projection in canvas space")
    func cornerFactorUsesSignedProjection() {
        let anchorUnit = CGPoint(x: 0, y: 0)
        let handleUnit = CGPoint(x: 1, y: 1)
        let anchor = SelectionResizeMath.point(
            atUnit: anchorUnit,
            in: bounds,
            rotation: 0
        )
        let handle = SelectionResizeMath.point(
            atUnit: handleUnit,
            in: bounds,
            rotation: 0
        )
        let diagonal = CGPoint(x: handle.x - anchor.x, y: handle.y - anchor.y)
        let doubled = CGPoint(
            x: anchor.x + 2 * diagonal.x,
            y: anchor.y + 2 * diagonal.y
        )
        let perpendicular = CGPoint(
            x: handle.x - diagonal.y * 0.5,
            y: handle.y + diagonal.x * 0.5
        )
        let pastAnchor = CGPoint(
            x: anchor.x - diagonal.x * 0.25,
            y: anchor.y - diagonal.y * 0.25
        )

        expectScalar(
            SelectionResizeMath.cornerFactor(
                handleUnit: handleUnit,
                anchorUnit: anchorUnit,
                bounds: bounds,
                rotation: 0,
                current: doubled
            ),
            equal: 2,
            accuracy: mathAccuracy
        )
        expectScalar(
            SelectionResizeMath.cornerFactor(
                handleUnit: handleUnit,
                anchorUnit: anchorUnit,
                bounds: bounds,
                rotation: 0,
                current: perpendicular
            ),
            equal: 1,
            accuracy: mathAccuracy
        )
        #expect(
            SelectionResizeMath.cornerFactor(
                handleUnit: handleUnit,
                anchorUnit: anchorUnit,
                bounds: bounds,
                rotation: 0,
                current: pastAnchor
            ) < 0
        )

        let rotatedAnchor = SelectionResizeMath.point(
            atUnit: anchorUnit,
            in: bounds,
            rotation: .pi / 2
        )
        let rotatedHandle = SelectionResizeMath.point(
            atUnit: handleUnit,
            in: bounds,
            rotation: .pi / 2
        )
        let rotatedDoubled = CGPoint(
            x: rotatedAnchor.x + 2 * (rotatedHandle.x - rotatedAnchor.x),
            y: rotatedAnchor.y + 2 * (rotatedHandle.y - rotatedAnchor.y)
        )
        expectScalar(
            SelectionResizeMath.cornerFactor(
                handleUnit: handleUnit,
                anchorUnit: anchorUnit,
                bounds: bounds,
                rotation: .pi / 2,
                current: rotatedDoubled
            ),
            equal: 2,
            accuracy: rotationAccuracy
        )
    }

    @Test("Edge factor preserves direction for both edges and rotated axes")
    func edgeFactorPreservesDirection() {
        let leftUnit = CGPoint(x: 0, y: 0.5)
        let rightUnit = CGPoint(x: 1, y: 0.5)
        let left = SelectionResizeMath.point(
            atUnit: leftUnit,
            in: bounds,
            rotation: 0
        )
        let right = SelectionResizeMath.point(
            atUnit: rightUnit,
            in: bounds,
            rotation: 0
        )

        #expect(
            SelectionResizeMath.edgeFactor(
                handleUnit: rightUnit,
                anchorUnit: leftUnit,
                bounds: bounds,
                rotation: 0,
                current: CGPoint(x: right.x + 25, y: right.y),
                axisIsX: true
            ) > 1
        )
        #expect(
            SelectionResizeMath.edgeFactor(
                handleUnit: leftUnit,
                anchorUnit: rightUnit,
                bounds: bounds,
                rotation: 0,
                current: CGPoint(x: left.x - 25, y: left.y),
                axisIsX: true
            ) > 1
        )
        #expect(
            SelectionResizeMath.edgeFactor(
                handleUnit: rightUnit,
                anchorUnit: leftUnit,
                bounds: bounds,
                rotation: 0,
                current: CGPoint(x: left.x - 10, y: left.y),
                axisIsX: true
            ) < 0
        )

        let rotation = Double.pi / 2
        let rotatedRight = SelectionResizeMath.point(
            atUnit: rightUnit,
            in: bounds,
            rotation: rotation
        )
        expectScalar(
            SelectionResizeMath.edgeFactor(
                handleUnit: rightUnit,
                anchorUnit: leftUnit,
                bounds: bounds,
                rotation: rotation,
                current: CGPoint(x: rotatedRight.x, y: rotatedRight.y + 25),
                axisIsX: true
            ),
            equal: 1.25,
            accuracy: rotationAccuracy
        )
    }

    @Test("Degenerate factor denominators keep the existing scale")
    func degenerateFactorDenominatorsReturnOne() {
        expectScalar(
            SelectionResizeMath.cornerFactor(
                handleUnit: CGPoint(x: 1, y: 1),
                anchorUnit: CGPoint(x: 0, y: 0),
                bounds: CGRect(x: 20, y: 30, width: 0, height: 0),
                rotation: 0.4,
                current: CGPoint(x: 100, y: 100)
            ),
            equal: 1,
            accuracy: mathAccuracy
        )
        expectScalar(
            SelectionResizeMath.edgeFactor(
                handleUnit: CGPoint(x: 1, y: 0.5),
                anchorUnit: CGPoint(x: 0, y: 0.5),
                bounds: CGRect(x: 20, y: 30, width: 0, height: 60),
                rotation: 0,
                current: CGPoint(x: 100, y: 100),
                axisIsX: true
            ),
            equal: 1,
            accuracy: mathAccuracy
        )
        expectScalar(
            SelectionResizeMath.edgeFactor(
                handleUnit: CGPoint(x: 0.5, y: 1),
                anchorUnit: CGPoint(x: 0.5, y: 0),
                bounds: bounds,
                rotation: 0,
                current: CGPoint(x: 100, y: 100),
                axisIsX: true
            ),
            equal: 1,
            accuracy: mathAccuracy
        )
    }

    @Test("Clamped scale enforces per-axis and uniform minimum extents")
    func clampedScaleEnforcesMinimumExtents() {
        let nonSquareBounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        let clamped = SelectionResizeMath.clampedScale(
            CGSize(width: 0.01, height: -0.5),
            in: nonSquareBounds,
            uniform: false
        )

        expectScalar(
            clamped.width * nonSquareBounds.width,
            equal: SelectionResizeMath.minimumExtent,
            accuracy: mathAccuracy
        )
        expectScalar(
            clamped.height * nonSquareBounds.height,
            equal: SelectionResizeMath.minimumExtent,
            accuracy: mathAccuracy
        )

        let uniform = SelectionResizeMath.clampedScale(
            CGSize(width: 0.01, height: 0.01),
            in: nonSquareBounds,
            uniform: true
        )
        expectScalar(uniform.width, equal: 0.3, accuracy: mathAccuracy)
        expectScalar(uniform.height, equal: 0.3, accuracy: mathAccuracy)

        let aboveMinimum = CGSize(width: 0.8, height: 0.9)
        let unchanged = SelectionResizeMath.clampedScale(
            aboveMinimum,
            in: nonSquareBounds,
            uniform: false
        )
        expectScalar(
            unchanged.width,
            equal: aboveMinimum.width,
            accuracy: mathAccuracy
        )
        expectScalar(
            unchanged.height,
            equal: aboveMinimum.height,
            accuracy: mathAccuracy
        )
    }

    private func expectScalar(
        _ actual: CGFloat,
        equal expected: CGFloat,
        accuracy: CGFloat
    ) {
        #expect(abs(actual - expected) <= accuracy)
    }

    private func expectPoint(
        _ actual: CGPoint,
        equal expected: CGPoint,
        accuracy: CGFloat
    ) {
        expectScalar(actual.x, equal: expected.x, accuracy: accuracy)
        expectScalar(actual.y, equal: expected.y, accuracy: accuracy)
    }

    private func expectTransform(
        _ actual: CGAffineTransform,
        equal expected: CGAffineTransform,
        accuracy: CGFloat
    ) {
        expectScalar(actual.a, equal: expected.a, accuracy: accuracy)
        expectScalar(actual.b, equal: expected.b, accuracy: accuracy)
        expectScalar(actual.c, equal: expected.c, accuracy: accuracy)
        expectScalar(actual.d, equal: expected.d, accuracy: accuracy)
        expectScalar(actual.tx, equal: expected.tx, accuracy: accuracy)
        expectScalar(actual.ty, equal: expected.ty, accuracy: accuracy)
    }

    private func rotation(
        _ angle: CGFloat,
        about center: CGPoint
    ) -> CGAffineTransform {
        CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(
                CGAffineTransform(translationX: center.x, y: center.y)
            )
    }
}
