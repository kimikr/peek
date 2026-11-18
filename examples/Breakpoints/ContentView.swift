// `peek dev examples/Breakpoints`: tap the button to stop at the breakpoint; the values show on
// the phone and in the peek output, and Continue goes on. peek:log lines only print.
import SwiftUI

struct Item { var name: String; var tags: [String] }

struct ContentView: View {
    @State private var count = 0
    let item = Item(name: "peek, the tool", tags: ["a", "b"])

    var body: some View {
        // peek:log count
        VStack(spacing: 20) {
            Text("Count \(count)")
            Button("Tap") {
                count += 1
                let message = "// peek:break this is in a string"
                // peek:break count, item, message.count, [1, 2].map { $0 * 2 }
                print(message)
            }
        }
        .task {
            // peek:log "task started", count
        }
    }
}

#Preview { ContentView() }
