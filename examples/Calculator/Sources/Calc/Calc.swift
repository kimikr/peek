import SwiftUI

struct Calculator {
    func add(_ a: Int, _ b: Int) -> Int { a + b }
    func divide(_ a: Int, _ b: Int) -> Int? { b == 0 ? nil : a / b }
}

struct BadgeView: View {
    let count: Int
    var label: String { count > 99 ? "99+" : "\(count)" }
    var body: some View {
        Text(label)
            .padding(8)
            .background(Capsule().fill(.red))
            .foregroundStyle(.white)
    }
}

#Preview("Tally") { TallyView() }
#Preview("Badge") { BadgeView(count: 7) }
