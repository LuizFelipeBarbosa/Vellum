@testable import Vellum
import XCTest

final class SqueezeEraserControllerTests: XCTestCase {
    func testBeginSwitchesToEraserAndEndRestores() {
        var controller = SqueezeEraserController()

        XCTAssertEqual(controller.begin(current: .pen), .eraser)
        XCTAssertEqual(controller.end(current: .eraser), .pen)
    }

    func testBeginWhileEraserIsNoOp() {
        var controller = SqueezeEraserController()

        XCTAssertNil(controller.begin(current: .eraser))
        XCTAssertNil(controller.end(current: .eraser))
    }

    func testManualToolChangeMidSqueezeIsNotClobbered() {
        var controller = SqueezeEraserController()

        XCTAssertEqual(controller.begin(current: .pen), .eraser)
        XCTAssertNil(controller.end(current: .highlighter))
    }

    func testEndWithoutBeginReturnsNil() {
        var controller = SqueezeEraserController()

        XCTAssertNil(controller.end(current: .eraser))
    }

    func testDoubleBeginPreservesOriginalTool() {
        var controller = SqueezeEraserController()

        XCTAssertEqual(controller.begin(current: .pen), .eraser)
        XCTAssertEqual(controller.begin(current: .pen), .eraser)
        XCTAssertEqual(controller.end(current: .eraser), .pen)
    }

    func testStateResetsAfterEnd() {
        var controller = SqueezeEraserController()

        XCTAssertEqual(controller.begin(current: .pen), .eraser)
        XCTAssertEqual(controller.end(current: .eraser), .pen)
        XCTAssertNil(controller.end(current: .eraser))
    }

    func testWorksFromSelectAndTextTools() {
        var controller = SqueezeEraserController()

        XCTAssertEqual(controller.begin(current: .select), .eraser)
        XCTAssertEqual(controller.end(current: .eraser), .select)
        XCTAssertEqual(controller.begin(current: .text), .eraser)
        XCTAssertEqual(controller.end(current: .eraser), .text)
    }
}
