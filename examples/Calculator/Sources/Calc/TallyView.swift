import SwiftUI

/// A small screen for the UI tests in Tests/CalcTests/TallyUITests.swift.
struct TallyView: View {
    @State private var count = 0
    @State private var name = ""

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
                Section { BadgeView(count: count) }
            }
            .navigationTitle("Tally")
        }
    }
}
