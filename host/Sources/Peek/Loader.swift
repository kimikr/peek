import Foundation
import UIKit

/// A preview dylib loaded into this process.
final class LoadedBuild {
    private typealias Entry = @convention(c) (Int32) -> UnsafeMutableRawPointer?
    private typealias Bump = @convention(c) () -> Void
    private let entry: Entry?
    private let handle: UnsafeMutableRawPointer

    struct LoadError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// dlopen()s the dylib. iOS validates its code signature here: it must be signed
    /// with a certificate from this app's provisioning profile (same Team ID).
    /// A hot patch has no entry point: loading it is what replaces the functions it patches.
    init(path: String, isPatch: Bool = false) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw LoadError(message: reason)
        }
        self.handle = handle
        if isPatch {
            entry = nil
            return
        }
        guard let symbol = dlsym(handle, "peek_entry") else {
            throw LoadError(message: "peek_entry symbol not found in build")
        }
        entry = unsafeBitCast(symbol, to: Entry.self)
    }

    /// Makes every view of this build evaluate its body again (after a patch was loaded).
    @MainActor
    func bump() {
        guard let symbol = dlsym(handle, "peek_bump") else { return }
        unsafeBitCast(symbol, to: Bump.self)()
    }

    @MainActor
    func makeController(root index: Int) -> UIViewController? {
        guard let raw = entry?(Int32(index)) else { return nil }
        return Unmanaged<UIViewController>.fromOpaque(raw).takeRetainedValue()
    }
}
