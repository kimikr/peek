import Foundation
import UIKit

/// A preview dylib loaded into this process.
final class LoadedBuild {
    private typealias Entry = @convention(c) (Int32) -> UnsafeMutableRawPointer?
    private let entry: Entry

    struct LoadError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// dlopen()s the dylib. iOS validates its code signature here: it must be signed
    /// with a certificate from this app's provisioning profile (same Team ID).
    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw LoadError(message: reason)
        }
        guard let symbol = dlsym(handle, "peek_entry") else {
            throw LoadError(message: "peek_entry symbol not found in build")
        }
        entry = unsafeBitCast(symbol, to: Entry.self)
    }

    @MainActor
    func makeController(root index: Int) -> UIViewController? {
        guard let raw = entry(Int32(index)) else { return nil }
        return Unmanaged<UIViewController>.fromOpaque(raw).takeRetainedValue()
    }
}
