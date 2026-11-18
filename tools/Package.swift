// swift-tools-version: 6.3
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "peek-tools",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"700.0.0"),
        // AssetKit with the fixes of joshuaswarren/AssetKit#1 (per-asset scale masks, exact row
        // stride): xtool-org's 1.0.0 cars only show @2x images and break rows not a multiple of 16.
        .package(url: "https://github.com/joshuaswarren/AssetKit", revision: "9b708e60042560d5a2892c4cd1a99d86a6be341c"),
    ],
    targets: [
        .executableTarget(name: "SwiftDataMacros", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ]),
        .executableTarget(name: "FoundationMacros", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        ], swiftSettings: [.define("FOUNDATION_FRAMEWORK")]),
        // Stands in for Xcode's actool when SwiftPM compiles a dependency's asset catalog.
        .executableTarget(name: "actool", dependencies: ["AssetKit"]),
        .testTarget(name: "SwiftDataMacrosTests", dependencies: [
            "SwiftDataMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
        ]),
    ]
)
