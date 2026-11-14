// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Forecast",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Forecast", targets: ["Forecast"]),
    ],
    targets: [
        .target(name: "Forecast"),
    ]
)
