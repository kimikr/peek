import Foundation
import Observation
import UIKit
import os

/// This app's release, and the version of the protocol it speaks with the `peek` script.
/// Both must match the script's VERSION and PROTOCOL (the release script checks).
enum PeekVersion {
    static let app = "0.3.0"
    static let proto = 2
}

/// The dev server answered with HTTP 426: it speaks another protocol version.
struct VersionMismatch: LocalizedError {
    let server: String
    var errorDescription: String? { "The dev server runs peek \(server), which needs a different version of this app." }
}

/// What the dev server reports from `GET /v1/state`.
struct ServerState: Decodable, Equatable {
    var version: Int
    var project: String
    var status: String  // building | ready | error | needs-cert
    var diagnostics: String?
    var roots: [String]?
    var hasCert: Bool
    var team: String?
    var size: Int?
    var seconds: Double?
    var resources: Resources?
    var deps: Resources?  // the package's dependencies, linked once into a library of their own
    var frameworks: Resources?  // dynamic frameworks from .xcframework dependencies, signed
    var shot: Int?  // screenshot requests so far (`peek shot`)
    var peek: String?
    var file: String?  // the name the build must be saved under (patches refer to their base by it)
    var patch: Patch?  // set when this build only replaces functions in the build named baseFile

    struct Patch: Decodable, Equatable {
        var base: Int
        var baseFile: String
    }
    var `protocol`: Int?  // absent from 0.1.0 servers, which speak protocol 1

    struct Resources: Decodable, Equatable {
        var id: String
        var size: Int
    }
}

enum Phase: Equatable {
    case unpaired
    case connecting
    case building
    case needsCertificate
    case showing
    case loadFailed(String)
    case crashedLastTime
    case incompatible(server: String)
}

@MainActor
@Observable
final class Session {
    private(set) var hosts: [String] = []
    private(set) var key: PairingKey?
    private(set) var activeHost: String?
    private(set) var phase: Phase = .unpaired
    private(set) var server: ServerState?
    private(set) var buildError: String?
    private(set) var controller: UIViewController?
    private(set) var loadCount = 0
    private(set) var certificateMessage: String?
    /// Why the newest build could not be loaded while an older one is still on screen.
    private(set) var loadError: String?
    /// Set when iOS is about to run out of memory for Peek: every reload keeps the old build loaded.
    private(set) var memoryLow = false
    private var memoryReported = false
    var rootIndex = 0 { didSet { if rootIndex != oldValue { showRoot() } } }
    var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            displayChanged?()
        }
    }
    var textSize = TextSize(rawValue: UserDefaults.standard.string(forKey: "textSize") ?? "") ?? .system {
        didSet {
            defaults.set(textSize.rawValue, forKey: "textSize")
            displayChanged?()
        }
    }
    /// Applies `appearance` and `textSize` to the preview; set by the view that owns the stage.
    var displayChanged: (() -> Void)?
    /// Renders what is on screen as a PNG; set by the view that owns the stage.
    var snapshot: (() -> Data?)?

    private var build: LoadedBuild?
    /// File name of the full build on screen; hot patches name the one they apply to.
    private var baseFile: String?
    private var patches: [LoadedBuild] = []
    private var loop: Task<Void, Never>?
    private var pendingCertificate: (p12: Data, password: String)?
    private var crashedKey: String?
    private var discovered: [String] = []
    private var lastShot = 0
    private let output = Output()
    /// What the crashed build printed last (a fatalError message, typically).
    var crashOutput: String? { output.lastWords }
    private let discovery = Discovery()
    private let defaults = UserDefaults.standard
    private let http: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    var isPaired: Bool { key != nil }

    init() {
        crashedKey = defaults.string(forKey: "loadingBuild")
        output.start()
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteMemory(warning: true) }
        }
        // Builds from earlier launches; ones loaded in this process must stay on disk.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("builds", isDirectory: true))
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("resources", isDirectory: true))
        if let saved = defaults.stringArray(forKey: "hosts"),
           let hex = defaults.string(forKey: "token"), let key = PairingKey(hex: hex) {
            hosts = saved
            self.key = key
            start()
        }
    }

    // MARK: Pairing

    /// A pairing link from outside the app, waiting for confirmation (any web page can open one).
    private(set) var pendingPairing: (hosts: [String], hex: String)?
    /// When the user last asked a store for the certificate.
    private var certificateRequested: Date?

    func confirmPairing() {
        guard let pending = pendingPairing else { return }
        pendingPairing = nil
        pair(hosts: pending.hosts, hex: pending.hex)
    }

    func cancelPairing() { pendingPairing = nil }

    func expectCertificateCallback() { certificateRequested = Date() }

    private func pair(hosts: [String], hex: String) {
        guard let key = PairingKey(hex: hex) else { return }
        defaults.set(hosts, forKey: "hosts")
        defaults.set(hex, forKey: "token")
        self.hosts = hosts
        self.key = key
        start()
    }

    /// Handles `peek://connect?h=<host:port>&h=...&k=<token>` and the certificate callback.
    /// Links from outside the app (`trusted` false) need the user's confirmation to pair.
    @discardableResult
    func open(_ url: URL, trusted: Bool = false) -> Bool {
        guard url.scheme?.lowercased() == "peek",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let items = components.queryItems ?? []
        switch url.host?.lowercased() {
        case "connect":
            let hosts = items.filter { $0.name == "h" }.compactMap(\.value)
            guard !hosts.isEmpty, let hex = items.first(where: { $0.name == "k" })?.value,
                  let key = PairingKey(hex: hex) else { return false }
            if key == self.key {
                pair(hosts: hosts, hex: hex)  // the same server at new addresses
            } else if trusted {
                pair(hosts: hosts, hex: hex)
            } else {
                pendingPairing = (hosts, hex)
            }
            return true
        case "certificate":
            // Only accepted shortly after the user asked a store for it, so that other apps
            // cannot replace the server's certificate.
            guard let asked = certificateRequested, Date().timeIntervalSince(asked) < 300 else {
                certificateMessage = "Ignored a certificate Peek did not ask for."
                return false
            }
            certificateRequested = nil
            guard let value = items.first(where: { $0.name == "cert" })?.value else { return false }
            let cleaned = value.replacingOccurrences(of: " ", with: "+")
            guard let data = Data(base64Encoded: cleaned)
                    ?? Data(base64Encoded: cleaned.removingPercentEncoding ?? "") else {
                certificateMessage = "The store returned a certificate Peek could not read."
                return false
            }
            let password = items.first(where: { $0.name == "password" })?.value ?? ""
            submitCertificate(p12: data, password: password)
            return true
        default:
            return false
        }
    }

    func disconnect() {
        discovery.stop()
        discovered = []
        loop?.cancel()
        loop = nil
        defaults.removeObject(forKey: "hosts")
        defaults.removeObject(forKey: "token")
        hosts = []
        key = nil
        activeHost = nil
        server = nil
        buildError = nil
        controller = nil
        build = nil
        baseFile = nil
        loadError = nil
        phase = .unpaired
    }

    // MARK: Certificate

    func submitCertificate(p12: Data, password: String) {
        pendingCertificate = (p12, password)
        certificateMessage = "Sending certificate to the dev server…"
        Task { await flushCertificate() }
    }

    private func flushCertificate() async {
        guard let pending = pendingCertificate, let key else { return }
        guard activeHost != nil else {
            certificateMessage = "Waiting for the dev server to send the certificate…"
            return
        }
        let payload = try! JSONSerialization.data(withJSONObject: [
            "p12": pending.p12.base64EncodedString(), "password": pending.password,
        ])
        do {
            let (data, response) = try await request("POST", "/v1/cert", body: key.seal(payload), timeout: 30)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if response.statusCode == 200 {
                pendingCertificate = nil
                let name = object?["name"] as? String ?? "certificate"
                certificateMessage = "Installed on the dev server: \(name)"
            } else {
                pendingCertificate = nil
                certificateMessage = "Server rejected the certificate: \(object?["error"] as? String ?? "HTTP \(response.statusCode)")"
            }
        } catch {
            certificateMessage = "Could not reach the dev server: \(error.localizedDescription)"
            log("certificate upload failed: \(error.localizedDescription)", level: "error")
        }
    }

    // MARK: Connection loop

    /// Addresses to try: ones the server advertises on this Wi-Fi first, then the saved ones.
    private func candidateHosts() -> [String] {
        var seen = Set<String>()
        return (discovered + hosts).filter { seen.insert($0).inserted }
    }

    /// Keeps an address learned through Bonjour so it is tried directly next time.
    private func remember(_ host: String) {
        guard !hosts.contains(host) else { return }
        hosts = Array(([host] + hosts).prefix(6))
        defaults.set(hosts, forKey: "hosts")
    }

    private func start() {
        if let key {
            discovery.start(serverID: key.serverID) { [weak self] found in
                self?.discovered = found
            }
        }
        loop?.cancel()
        activeHost = nil
        server = nil
        buildError = nil
        phase = .connecting
        loop = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        var version = -1
        while !Task.isCancelled {
            if activeHost == nil {
                if let server = incompatibleServer {
                    phase = .incompatible(server: server)
                }
                if let (host, state) = await probe(candidateHosts()) {
                    activeHost = host
                    remember(host)
                    log("connected (\(UIDevice.current.systemName) \(UIDevice.current.systemVersion))",
                        extra: ["diagnostics": Diagnostics.collect()])
                    output.flush(to: self)
                    await flushCertificate()
                    version = state.version
                    lastShot = state.shot ?? 0  // requests made before this phone connected are not ours
                    await apply(state)
                }
                if Task.isCancelled { return }
                if activeHost == nil {
                    if controller == nil { phase = .connecting }
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
            }
            guard let host = activeHost else { continue }
            do {
                let state = try await fetchState(host: host, after: version, wait: 25, timeout: 40)
                if let shot = state.shot, shot > lastShot {
                    lastShot = shot
                    await sendSnapshot(shot)
                }
                if state.version != version {
                    version = state.version
                    await apply(state)
                } else {
                    server = state
                }
            } catch {
                if Task.isCancelled { return }
                activeHost = nil
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Set while the server refuses this app's protocol version.
    private var incompatibleServer: String?

    /// Tries every address at once and returns the first that answers.
    private func probe(_ hosts: [String]) async -> (String, ServerState)? {
        await withTaskGroup(of: (String, ServerState)?.self) { group in
            for host in hosts {
                group.addTask { [weak self] in
                    do {
                        guard let state = try await self?.fetchState(host: host, after: -1, wait: 0, timeout: 4) else { return nil }
                        await self?.setIncompatible(nil)
                        return (host, state)
                    } catch let mismatch as VersionMismatch {
                        await self?.setIncompatible(mismatch.server)
                        return nil
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private func setIncompatible(_ server: String?) {
        incompatibleServer = server
        if let server { phase = .incompatible(server: server) }
    }

    /// Notes how much memory is left after a load; past a threshold, suggests restarting Peek.
    private func noteMemory(warning: Bool = false) {
        let left = os_proc_available_memory() / (1 << 20)
        guard warning || (left > 0 && left < 250) else { return }
        memoryLow = true
        guard !memoryReported else { return }
        memoryReported = true
        log("memory is running low (\(left) MB left after \(loadCount) reloads): restart Peek to free old builds",
            level: "warn")
    }

    /// Quits Peek so that iOS frees every loaded build; opening it again loads the newest one.
    func restart() {
        exit(0)
    }

    private func sendSnapshot(_ number: Int) async {
        guard let key, let png = snapshot?() else {
            log("screenshot requested, but nothing is on screen", level: "warn")
            return
        }
        _ = try? await request("POST", "/v1/shot?n=\(number)", body: key.seal(png), timeout: 60)
    }

    private func apply(_ state: ServerState) async {
        server = state
        switch state.status {
        case "ready":
            buildError = nil
            await load(state)
        case "error":
            buildError = state.diagnostics ?? "Build failed."
            if controller == nil { phase = .building }
        case "needs-cert":
            buildError = nil
            if controller == nil { phase = .needsCertificate }
        default:
            if controller == nil { phase = .building }
        }
    }

    private func load(_ state: ServerState) async {
        guard let host = activeHost else { return }
        let buildKey = "\(host)#\(state.version)#\(state.size ?? 0)"
        if buildKey == crashedKey {
            phase = .crashedLastTime
            log("skipping build \(state.version): the app quit while loading it last time", level: "warn")
            return
        }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("builds", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let frameworks = state.frameworks {
                // Builds find them through the rpath @loader_path/Frameworks.
                let folder = directory.appendingPathComponent("Frameworks", isDirectory: true)
                let marker = folder.appendingPathComponent(".peek-\(frameworks.id)")
                if !FileManager.default.fileExists(atPath: marker.path) {
                    let (data, response) = try await request("GET", "/v1/frameworks/\(frameworks.id)", timeout: 120)
                    guard response.statusCode == 200 else { return }
                    try ResourceArchive.unpack(data, into: folder)
                    FileManager.default.createFile(atPath: marker.path, contents: nil)
                }
            }
            if let deps = state.deps {
                // The build refers to it as @loader_path/PeekDeps-<id>.dylib, so it goes next to it.
                let file = directory.appendingPathComponent("PeekDeps-\(deps.id).dylib")
                if !FileManager.default.fileExists(atPath: file.path) {
                    let (data, response) = try await request("GET", "/v1/deps/\(deps.id)", timeout: 120)
                    guard response.statusCode == 200 else { return }
                    try data.write(to: file)
                }
            }
            if let patch = state.patch, patch.baseFile != baseFile || build == nil {
                // Not the build this patch applies to: the server sends a whole build when it sees that.
                log("waiting for a whole build (have \(baseFile ?? "none"), patch is for \(patch.baseFile))", level: "warn")
                return
            }
            let (data, response) = try await request("GET", "/v1/dylib/\(state.version)", timeout: 60)
            guard response.statusCode == 200 else { return }  // superseded; the next poll brings the new one
            let name = state.file ?? "peek_\(state.version)_\(UUID().uuidString.prefix(8)).dylib"
            let file = directory.appendingPathComponent(name)
            try data.write(to: file)
            try await prepareResources(state.resources)

            defaults.set(buildKey, forKey: "loadingBuild")
            if state.patch != nil, let build {
                do {
                    patches.append(try LoadedBuild(path: file.path, isPatch: true))
                } catch {
                    defaults.removeObject(forKey: "loadingBuild")
                    log("hot patch \(state.version) failed to load: \(error.localizedDescription)", level: "patch-failed")
                    return
                }
                build.bump()
                loadError = nil
                log("hot-patched build \(state.version) (\(data.count / 1024) KB)")
                clearLoading(buildKey)
                return
            }
            let loaded = try LoadedBuild(path: file.path)
            build = loaded
            baseFile = state.file
            patches = []
            loadError = nil
            noteMemory()
            if rootIndex >= (state.roots?.count ?? 1) { rootIndex = 0 }
            showRoot()
            log("loaded build \(state.version) (\(data.count / 1024) KB)")
            clearLoading(buildKey)
        } catch {
            defaults.removeObject(forKey: "loadingBuild")
            if controller == nil {
                phase = .loadFailed(error.localizedDescription)
            } else {
                // Keep showing the last build that worked.
                loadError = "Build \(state.version) could not be loaded:\n\n\(error.localizedDescription)"
            }
            log("load failed for build \(state.version): \(error.localizedDescription)", level: "error",
                extra: ["diagnostics": Diagnostics.collect()])
        }
    }

    /// Forgets the "loading" marker once the build has survived a few seconds on screen.
    private func clearLoading(_ buildKey: String) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            if defaults.string(forKey: "loadingBuild") == buildKey {
                defaults.removeObject(forKey: "loadingBuild")
            }
        }
    }

    /// Downloads and unpacks the build's resource bundles, then points `Bundle.module` at them.
    private func prepareResources(_ resources: ServerState.Resources?) async throws {
        guard let resources else {
            unsetenv("PACKAGE_RESOURCE_BUNDLE_PATH")
            return
        }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("resources/\(resources.id)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            let (data, response) = try await request("GET", "/v1/resources/\(resources.id)", timeout: 120)
            guard response.statusCode == 200 else { throw URLError(.resourceUnavailable) }
            let staging = folder.deletingLastPathComponent()
                .appendingPathComponent("incoming-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try ResourceArchive.unpack(data, into: staging)
            try FileManager.default.moveItem(at: staging, to: folder)
            ResourceArchive.registerFonts(in: folder)
        }
        setenv("PACKAGE_RESOURCE_BUNDLE_PATH", folder.path, 1)
    }

    private func showRoot() {
        guard let build else { return }
        guard let made = build.makeController(root: rootIndex) else {
            phase = .loadFailed("The build has no preview at index \(rootIndex).")
            return
        }
        controller = made
        loadCount += 1
        phase = .showing
    }

    /// Loads the build that was skipped because the app quit while loading it.
    func retryCrashedBuild() {
        crashedKey = nil
        defaults.removeObject(forKey: "loadingBuild")
        if let server, server.status == "ready" {
            Task { await load(server) }
        }
    }

    // MARK: HTTP

    private func fetchState(host: String, after: Int, wait: Int, timeout: TimeInterval) async throws -> ServerState {
        let (data, response) = try await request("GET", "/v1/state?after=\(after)&wait=\(wait)", host: host, timeout: timeout)
        if response.statusCode == 426 {
            let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw VersionMismatch(server: reply?["peek"] as? String ?? "?")
        }
        guard response.statusCode == 200 else {
            throw URLError(response.statusCode == 401 ? .userAuthenticationRequired : .badServerResponse)
        }
        let state = try JSONDecoder().decode(ServerState.self, from: data)
        if (state.protocol ?? 1) != PeekVersion.proto {
            throw VersionMismatch(server: state.peek ?? "?")
        }
        return state
    }

    private func request(_ method: String, _ path: String, host: String? = nil, body: Data = Data(),
                         timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        guard let key, let host = host ?? activeHost, let url = URL(string: "http://\(host)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        let device = UIDevice.current.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "iPhone"
        // Builds have to be signed under the identifier of the app that loads them.
        let bundle = Diagnostics.hostBundleIdentifier
        request.setValue(key.authHeader(method: method, path: path, body: body, bundle: bundle, device: device),
                         forHTTPHeaderField: "X-Peek-Auth")
        request.setValue(device, forHTTPHeaderField: "X-Peek-Device")
        request.setValue(PeekVersion.app, forHTTPHeaderField: "X-Peek-App")
        request.setValue(String(PeekVersion.proto), forHTTPHeaderField: "X-Peek-Protocol")
        request.setValue(baseFile ?? "", forHTTPHeaderField: "X-Peek-Base")
        request.setValue(bundle, forHTTPHeaderField: "X-Peek-Bundle")
        if method == "POST" { request.httpBody = body }
        let (data, response) = try await http.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.value(forHTTPHeaderField: "Content-Type") == "application/x-peek-sealed" {
            return (try key.open(data), response)
        }
        // Successful replies from the dev server are always sealed.
        guard response.statusCode != 200 else { throw PairingKey.Unreadable() }
        return (data, response)
    }

    /// Sends what the previewed code printed to the dev server's terminal; false when not connected.
    func sendOutput(_ text: String, level: String = "print") -> Bool {
        guard activeHost != nil else { return false }
        let body = try! JSONSerialization.data(withJSONObject: ["level": level, "output": text])
        Task { _ = try? await request("POST", "/v1/log", body: body, timeout: 10) }
        return true
    }

    /// Mirrors a message to the dev server's terminal.
    func log(_ message: String, level: String = "info", extra: [String: Any] = [:]) {
        guard activeHost != nil else { return }
        var entry: [String: Any] = ["level": level, "message": message]
        entry.merge(extra) { _, new in new }
        let body = try! JSONSerialization.data(withJSONObject: entry)
        Task { _ = try? await request("POST", "/v1/log", body: body, timeout: 10) }
    }
}

enum Appearance: String, CaseIterable {
    case system, light, dark

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

enum TextSize: String, CaseIterable {
    case system, xSmall, large, xxxLarge, accessibility3, accessibility5

    var category: UIContentSizeCategory? {
        switch self {
        case .system: nil
        case .xSmall: .extraSmall
        case .large: .large
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .xSmall: "Extra small"
        case .large: "Large (default)"
        case .xxxLarge: "Extra extra extra large"
        case .accessibility3: "Accessibility 3"
        case .accessibility5: "Accessibility 5"
        }
    }
}
