import SwiftUI

struct ContentView: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Hello from Linux")
                .font(.title2.weight(.semibold))
            Text("\(count)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            HStack(spacing: 12) {
                Button("−") { withAnimation { count -= 1 } }
                    .buttonStyle(.bordered)
                Button("+") { withAnimation { count += 1 } }
                    .buttonStyle(.borderedProminent)
            }
            .font(.title)
        }
        .padding()
    }
}

private struct Row: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View { Toggle(title, isOn: $isOn) }
}

#Preview("Counter") {
    ContentView()
}

#Preview("List") {
    @Previewable @State var wifi = true
    @Previewable @State var bluetooth = false
    // fileprivate types and @Previewable state work too
    NavigationStack {
        Form {
            Row(title: "Wi-Fi", isOn: $wifi)
            Row(title: "Bluetooth", isOn: $bluetooth)
            Section("Status") {
                LabeledContent("Wi-Fi", value: wifi ? "On" : "Off")
            }
        }
        .navigationTitle("Settings")
    }
}
