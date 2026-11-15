// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Calculator",
    platforms: [.iOS(.v17)],
    products: [.library(name: "Calc", targets: ["Calc"])],
    targets: [
        .target(name: "Calc"),
        .testTarget(name: "CalcTests", dependencies: ["Calc"]),
    ]
)
