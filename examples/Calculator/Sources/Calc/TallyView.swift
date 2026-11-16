import SwiftUI

/// A small screen for the UI tests in Tests/CalcTests/TallyUITests.swift.
struct TallyView: View {
    @State private var count = 0
    @State private var name = ""
    @State private var notify = false
    @State private var level = 0.5

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
                Section { BadgeView(count: count) }
                Section("Rows") {
                    ForEach(1...30, id: \.self) { Text("Row \($0)") }
                }
            }
            .navigationTitle("Tally")
        }
    }
}
