// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Peek",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Peek", targets: ["Peek"]),
    ],
    targets: [
        .target(
            name: "Peek",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // The linker otherwise records the deployment target as the SDK version, and iOS
            // then runs the app (and every preview in it) with the pre-iOS 26 look and behaviour.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "ios",
                                           "-Xlinker", "17.0", "-Xlinker", "26.0"])]
        ),
    ]
)
