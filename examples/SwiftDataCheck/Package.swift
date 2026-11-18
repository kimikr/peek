// swift-tools-version: 6.0
import PackageDescription

// The parts of SwiftData that examples/Notes does not use, each checked on the phone:
// `peek dev examples/SwiftDataCheck` lists the results on screen and in peek's output.
let package = Package(
    name: "SwiftDataCheck",
    platforms: [.iOS(.v18)],  // #Unique and #Index
    targets: [.target(name: "SwiftDataCheck")]
)
