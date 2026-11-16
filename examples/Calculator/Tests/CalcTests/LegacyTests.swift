import XCTest
import SwiftUI
@testable import Calc

/// XCTest works too: existing test suites run unchanged.
final class LegacyCalculatorTests: XCTestCase {
    func testAdd() {
        XCTAssertEqual(Calculator().add(40, 2), 42)
    }

    func testAddPerformance() {
        measure { _ = (1...100_000).reduce(0) { Calculator().add($0, $1) } }
    }

    func testDivideByZero() {
        XCTAssertNil(Calculator().divide(1, 0))
    }

    @MainActor func testBadgeRenders() throws {
        let image = try XCTUnwrap(ImageRenderer(content: BadgeView(count: 3)).uiImage)
        XCTAssertGreaterThan(image.size.width, 0)
    }
}
