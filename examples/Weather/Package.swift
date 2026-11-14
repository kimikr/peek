// swift-tools-version: 6.0

import PackageDescription

// An xtool-style app package with a (local) package dependency and resources.
let package = Package(
    name: "Weather",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Weather", targets: ["Weather"]),
    ],
    dependencies: [
        .package(path: "Packages/Forecast"),
    ],
    targets: [
        .target(
            name: "Weather",
            dependencies: [.product(name: "Forecast", package: "Forecast")],
            resources: [.process("Resources")]
        ),
    ]
)
