import SwiftUI

@main
struct PeekApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onOpenURL { session.open($0) }
        }
    }
}
