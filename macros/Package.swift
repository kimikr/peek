// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "sdmacros",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"700.0.0")],
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
        .testTarget(name: "SwiftDataMacrosTests", dependencies: [
            "SwiftDataMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
        ]),
    ]
)
