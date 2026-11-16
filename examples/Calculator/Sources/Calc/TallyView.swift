import SwiftUI

/// A small screen for the UI tests in Tests/CalcTests/TallyUITests.swift.
struct TallyView: View {
    @State private var count = Int(ProcessInfo.processInfo.environment["START_COUNT"] ?? "") ?? 0
    @State private var name = ""
    @State private var notify = false
    @State private var level = 0.5
    @State private var side = "none"
    @State private var zoom = 1.0
    @State private var angle = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Count: \(count)").accessibilityIdentifier("count")
                    Button("Add") { count += 1 }
                    Button("Reset", role: .destructive) { count = 0 }
                }
                Section {
                    TextField("Your name", text: $name).accessibilityIdentifier("name")
                    Text(name.isEmpty ? "Hello!" : "Hello, \(name)!").accessibilityIdentifier("greeting")
                }
                Section {
                    Toggle("Notifications", isOn: $notify).accessibilityIdentifier("notify")
                    Slider(value: $level).accessibilityIdentifier("level")
                    Text("Level \(Int(level * 100))").accessibilityIdentifier("levelText")
                }
                Section {
                    Text(ProcessInfo.processInfo.arguments.contains("-uiTesting") ? "Mode: UI testing" : "Mode: normal")
                        .accessibilityIdentifier("mode")
                    Button("Call support") { UIApplication.shared.open(URL(string: "tel:0123456789")!) }
                }
                Section { BadgeView(count: count) }
                Section {
                    // Coordinate taps, pinch and two-finger rotation (TallyUITests.testPad*).
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 12).fill(.tint.opacity(0.3))
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { side = $0.location.x < geo.size.width / 2 ? "left" : "right" })
                    }
                        .frame(height: 120)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("pad")
                        .simultaneousGesture(MagnifyGesture().onChanged { zoom = max(zoom, $0.magnification) })  // furthest it went
                        .simultaneousGesture(RotateGesture().onChanged { if abs($0.rotation.degrees) > abs(angle) { angle = $0.rotation.degrees } })
                    Text("Tap: \(side)").accessibilityIdentifier("side")
                    Text(String(format: "Zoom: %.1f, angle: %.0f", zoom, angle)).accessibilityIdentifier("zoom")
                }
                Section("Rows") {
                    ForEach(1...30, id: \.self) { Text("Row \($0)") }
                }
            }
            .navigationTitle("Tally")
        }
    }
}
