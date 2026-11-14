import CryptoKit
import Foundation
import MachO

/// What this process is signed with, so the dev server can tell why a build was refused:
/// iOS only loads a build signed by a certificate listed in the provisioning profile of
/// the running app (which is the host's when Peek runs inside LiveContainer).
enum Diagnostics {
    /// Bundle identifier of the process's real main executable. It differs from `Bundle.main`
    /// when a host such as LiveContainer runs Peek as a guest.
    static let hostBundleIdentifier: String = {
        if let name = _dyld_get_image_name(0) {
            let plist = URL(fileURLWithPath: String(cString: name)).deletingLastPathComponent()
                .appendingPathComponent("Info.plist")
            if let identifier = NSDictionary(contentsOf: plist)?["CFBundleIdentifier"] as? String { return identifier }
        }
        return Bundle.main.bundleIdentifier ?? ""
    }()

    static func collect() -> [String: Any] {
        var report: [String: Any] = [:]
        // The real main executable; Bundle.main may be redirected by a host such as LiveContainer.
        let executable = _dyld_get_image_name(0).map { String(cString: $0) } ?? Bundle.main.executablePath ?? ""
        report["executable"] = executable.split(separator: "/").suffix(2).joined(separator: "/")
        report["team"] = teamIdentifier() ?? "unknown"
        report["bundle"] = hostBundleIdentifier
        report["time"] = ISO8601DateFormatter().string(from: Date())

        var profiles: [[String: Any]] = []
        var folder = URL(fileURLWithPath: executable).deletingLastPathComponent()
        for _ in 0..<3 {
            if let profile = readProfile(folder.appendingPathComponent("embedded.mobileprovision")) {
                profiles.append(profile)
            }
            folder = folder.deletingLastPathComponent()
        }
        report["profiles"] = profiles

        return report
    }

    private static func readProfile(_ url: URL) -> [String: Any]? {
        // The profile is a CMS envelope around an XML property list.
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any] else { return nil }
        let certificates = (plist["DeveloperCertificates"] as? [Data] ?? []).map {
            SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        }
        return [
            "name": plist["Name"] as? String ?? "",
            "team": (plist["TeamIdentifier"] as? [String])?.first ?? "",
            "expires": (plist["ExpirationDate"] as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "certificates": certificates,
        ]
    }

    /// Team ID of the running process from the kernel (csops CS_OPS_TEAMID).
    private static func teamIdentifier() -> String? {
        typealias Csops = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops") else { return nil }
        let csops = unsafeBitCast(symbol, to: Csops.self)
        var buffer = [UInt8](repeating: 0, count: 64)
        guard csops(getpid(), 14, &buffer, buffer.count) == 0 else { return nil }
        // 8-byte blob header, then a NUL-terminated string.
        let text = buffer.dropFirst(8).prefix { $0 != 0 }
        return text.isEmpty ? nil : String(decoding: text, as: UTF8.self)
    }
}
