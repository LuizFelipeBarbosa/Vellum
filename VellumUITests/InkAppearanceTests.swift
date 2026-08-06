import SwiftUI
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class InkAppearanceTests: XCTestCase {
    func testDisplayStyleFollowsEffectivePaper() {
        XCTAssertEqual(
            InkAppearance.style(colorScheme: .light, paperTint: nil),
            .light
        )
        XCTAssertEqual(
            InkAppearance.style(colorScheme: .dark, paperTint: nil),
            .dark
        )
        XCTAssertEqual(
            InkAppearance.style(
                colorScheme: .dark,
                paperTint: CodableColor(hex: "#FFFFFF")
            ),
            .light
        )
        XCTAssertEqual(
            InkAppearance.style(
                colorScheme: .light,
                paperTint: CodableColor(hex: "#23201A")
            ),
            .dark
        )
    }

    func testDarkDisplayConversionRoundTripsToStoredColors() {
        let colors = [
            CodableColor(hex: "#2A2622"),
            CodableColor(hex: "#E53935"),
            CodableColor(red: 0.18, green: 0.47, blue: 0.82, alpha: 0.55),
        ]

        for color in colors {
            let displayed = InkAppearance.displayColor(for: color, style: .dark)
            let roundTripped = InkAppearance.storedColor(for: displayed, style: .dark)
            assertColor(roundTripped, equals: color, accuracy: 0.02)
        }
    }

    func testLightDisplayConversionIsExactIdentity() {
        let color = CodableColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
        let displayed = InkAppearance.displayColor(for: color, style: .light)

        XCTAssertEqual(
            InkAppearance.storedColor(for: displayed, style: .light),
            color
        )
    }

    private func assertColor(
        _ actual: CodableColor,
        equals expected: CodableColor,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.red, expected.red, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: accuracy, file: file, line: line)
    }
}
