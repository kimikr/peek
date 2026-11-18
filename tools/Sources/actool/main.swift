// Xcode's actool for SwiftPM builds on Linux: the same arguments, Assets.car written by AssetKit.
// Only what SwiftPM asks for is handled: --version, and --compile with the options it passes.
import AssetKit
import Foundation

func plist(_ object: Any) -> String {
    let data = try! PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    return String(decoding: data, as: UTF8.self)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("actool: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--version") {
    print(plist(["com.apple.actool.version": ["bundle-version": "24506", "short-bundle-version": "26.3"]]))
    exit(0)
}

// `--name value` pairs, flags, and the catalogs (the arguments ending in .xcassets).
var options: [String: String] = [:]
var catalogs: [URL] = []
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    if argument.hasSuffix(".xcassets") {
        catalogs.append(URL(fileURLWithPath: argument))
        index += 1
    } else if argument.hasPrefix("--"), index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--"),
              !arguments[index + 1].hasSuffix(".xcassets") {
        options[argument] = arguments[index + 1]
        index += 2
    } else {
        index += 1
    }
}
guard let output = options["--compile"].map({ URL(fileURLWithPath: $0) }) else { fail("--compile is missing") }
// shortcut: one catalog per target (SwiftPM's usual case); merging several needs AssetKit changes.
guard catalogs.count == 1, let catalog = catalogs.first else {
    fail("expected one .xcassets, got \(catalogs.map(\.lastPathComponent))")
}

// GenerateAssetSymbols: the ColorResource and ImageResource constants Xcode generates
// (`Color(.brand)`, `Image(.logo)`); this run compiles nothing.
if let swiftPath = options["--generate-swift-asset-symbols"] {
    func assets(_ suffix: String) -> [String] {
        let all = FileManager.default.enumerator(atPath: catalog.path)?.compactMap { $0 as? String } ?? []
        return all.filter { $0.hasSuffix(suffix) }
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }.sorted()
    }
    // shortcut: folder namespaces ("provides-namespace") are ignored; names are the asset's own.
    func symbol(_ name: String, dropping suffix: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var result = words.enumerated().map { i, word in
            i == 0 ? word.prefix(1).lowercased() + word.dropFirst() : word.prefix(1).uppercased() + word.dropFirst()
        }.joined()
        if result.count > suffix.count, result.hasSuffix(suffix) { result.removeLast(suffix.count) }
        if let first = result.first, first.isNumber { result = "_" + result }
        return "`\(result)`"
    }
    func constants(_ type: String, _ names: [String], dropping suffix: String) -> String {
        guard !names.isEmpty else { return "" }
        let lines = names.map {
            "    static let \(symbol($0, dropping: suffix)) = DeveloperToolsSupport.\(type)(name: \"\($0)\", bundle: resourceBundle)"
        }
        return "@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)\nextension DeveloperToolsSupport.\(type) {\n"
            + lines.joined(separator: "\n") + "\n}\n\n"
    }
    let source = """
        import Foundation
        #if canImport(DeveloperToolsSupport)
        import DeveloperToolsSupport

        #if SWIFT_PACKAGE
        private let resourceBundle = Foundation.Bundle.module
        #else
        private class ResourceBundleClass {}
        private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
        #endif

        \(constants("ColorResource", assets(".colorset"), dropping: "Color"))\
        \(constants("ImageResource", assets(".imageset"), dropping: "Image"))\
        #endif

        """
    try Data(source.utf8).write(to: URL(fileURLWithPath: swiftPath))
    if let path = options["--generate-objc-asset-symbols"] {
        try Data("#import <Foundation/Foundation.h>\n".utf8).write(to: URL(fileURLWithPath: path))
    }
    if let path = options["--generate-asset-symbol-index"] {
        try Data(plist([String: Any]()).utf8).write(to: URL(fileURLWithPath: path))
    }
    print(plist(["com.apple.actool.compilation-results": ["output-files": [swiftPath]]]))
    exit(0)
}

/// The catalog AssetKit compiles. actool reads a bitmap with no "scale" (Xcode's Single Scale) as
/// 1x; AssetKit keys it as scale 0, which UIImage never finds, so such catalogs get a copy with the
/// scale filled in.
func catalogForAssetKit(_ catalog: URL) throws -> URL {
    let files = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }.filter { $0.lastPathComponent == "Contents.json"
            && $0.deletingLastPathComponent().pathExtension == "imageset" } ?? []
    func fixed(_ url: URL) -> Data? {
        guard var json = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any],
              var images = json["images"] as? [[String: Any]] else { return nil }
        var changed = false
        for i in images.indices where images[i]["scale"] == nil {
            let name = (images[i]["filename"] as? String ?? "").lowercased()
            if [".png", ".jpg", ".jpeg"].contains(where: name.hasSuffix) {
                images[i]["scale"] = "1x"
                changed = true
            }
        }
        json["images"] = images
        return changed ? try? JSONSerialization.data(withJSONObject: json) : nil
    }
    let patches = files.compactMap { url in fixed(url).map { (url, $0) } }
    guard !patches.isEmpty else { return catalog }
    let copy = FileManager.default.temporaryDirectory
        .appendingPathComponent("peek-actool-\(getpid())").appendingPathComponent(catalog.lastPathComponent)
    try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
    try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: catalog, to: copy)
    for (url, data) in patches {
        try data.write(to: copy.appendingPathComponent(String(url.path.dropFirst(catalog.path.count + 1))))
    }
    return copy
}

let compiler = XCAssetCompiler(deploymentTarget: options["--minimum-deployment-target"] ?? "17.0")
let result: CompileResult
do {
    let source = try catalogForAssetKit(catalog)
    defer { if source != catalog { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) } }
    result = try await compiler.compile(catalog: source)
} catch {
    fail("\(catalog.lastPathComponent): \(error)")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var written = [output.appendingPathComponent("Assets.car")]
try result.carData.write(to: written[0])
var partial: [String: Any] = [:]
if let icon = result.appIconBundle, options["--app-icon"] == icon.primaryIconName {
    for file in icon.looseFiles {
        let url = output.appendingPathComponent(file.name)
        try file.data.write(to: url)
        written.append(url)
    }
    partial.merge(icon.infoPlistAdditions.mapValues { $0 as Any }) { $1 }
}
if let accent = options["--accent-color"] { partial["NSAccentColorName"] = accent }
if let path = options["--output-partial-info-plist"] {
    try Data(plist(partial).utf8).write(to: URL(fileURLWithPath: path))
}
if let path = options["--export-dependency-info"] {
    // ld's dependency-info format: a version record, then every input and output file.
    var info = Data([0x00]) + Data("actool\0".utf8)
    let inputs = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL } ?? []
    for url in [catalog] + inputs { info += Data([0x10]) + Data((url.path + "\0").utf8) }
    for url in written { info += Data([0x40]) + Data((url.path + "\0").utf8) }
    try info.write(to: URL(fileURLWithPath: path))
}
print(plist(["com.apple.actool.compilation-results": ["output-files": written.map(\.path)]]))
