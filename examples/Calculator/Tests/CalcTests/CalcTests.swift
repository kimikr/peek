import Testing
import SwiftUI
import UIKit
@testable import Calc

@Suite struct CalculatorTests {
    let calc = Calculator()

    @Test func adds() { #expect(calc.add(2, 3) == 5) }

    @Test(arguments: [(6, 3, 2), (9, 3, 3), (1, 0, nil)] as [(Int, Int, Int?)])
    func divides(a: Int, b: Int, expected: Int?) { #expect(calc.divide(a, b) == expected) }
}

@MainActor @Suite struct ViewTests {
    @Test func badgeRendersOnDevice() throws {
        let renderer = ImageRenderer(content: BadgeView(count: 120))
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        #expect(image.size.width > 20)
        #expect(UIDevice.current.userInterfaceIdiom == .phone)
    }

    @Test func badgeCapsLargeCounts() {
        #expect(BadgeView(count: 120).label == "99+")
        #expect(BadgeView(count: 7).label == "7")
    }
}
