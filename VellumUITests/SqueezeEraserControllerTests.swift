@testable import Vellum
import XCTest

final class SqueezeEraserControllerTests: XCTestCase {
    func testSqueezeRestoresTheToolItStartedFromAndThenResets() {
        for tool in [ToolID.pen, .select, .text] {
            var controller = SqueezeEraserController()

            XCTAssertEqual(controller.begin(current: tool), .eraser)
            XCTAssertEqual(controller.end(current: .eraser), tool)
            // The saved tool is cleared on end, so a stray second end restores nothing.
            XCTAssertNil(controller.end(current: .eraser))
        }
    }

    func testBeginWhileAlreadyErasingIsANoOpAndSavesNoTool() {
        var controller = SqueezeEraserController()

        XCTAssertNil(controller.begin(current: .eraser))
        XCTAssertNil(controller.end(current: .eraser))
    }

    func testManualToolChangeMidSqueezeIsNotClobbered() {
        var controller = SqueezeEraserController()

        XCTAssertEqual(controller.begin(current: .pen), .eraser)
        XCTAssertNil(controller.end(current: .highlighter))
    }

    func testDoubleBeginPreservesOriginalTool() {
        var controller = SqueezeEraserController()

        XCTAssertEqual(controller.begin(current: .pen), .eraser)
        XCTAssertEqual(controller.begin(current: .pen), .eraser)
        XCTAssertEqual(controller.end(current: .eraser), .pen)
    }
}
