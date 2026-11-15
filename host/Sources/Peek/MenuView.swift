import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MenuView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            Form {
                if let roots = session.server?.roots, roots.count > 1, session.controller != nil {
                    Section("Preview") {
                        Picker("Preview", selection: $session.rootIndex) {
                            ForEach(Array(roots.enumerated()), id: \.offset) { index, name in
                                Text(name).tag(index)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                Section("Display") {
                    Picker("Appearance", selection: $session.appearance) {
                        Text("System").tag(Appearance.system)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                    Picker("Text size", selection: $session.textSize) {
                        ForEach(TextSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                }
                if session.memoryLow {
                    Section {
                        Button("Quit Peek", role: .destructive) { session.restart() }
                    } header: {
                        Text("Memory")
                    } footer: {
                        Text("Every reload keeps the previous build in memory, and iOS is close to closing Peek. Quit and open it again to start fresh; the newest build loads right away.")
                    }
                }
                Section("Dev server") {
                    LabeledContent("Project", value: session.server?.project ?? "—")
                    LabeledContent("Address", value: session.activeHost ?? "not connected")
                    LabeledContent("Build", value: buildSummary)
                    LabeledContent("Signing team", value: session.server?.team ?? "no certificate")
                    LabeledContent("Versions", value: "app \(PeekVersion.app) · server \(session.server?.peek ?? "—")")
                }
                Section {
                    CertificateButtons()
                    if let message = session.certificateMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Certificate")
                } footer: {
                    Text("Needed once, and again whenever the store issues a new certificate (preview builds then stop loading).")
                }
                Section {
                    Button("Disconnect", role: .destructive) {
                        session.disconnect()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Peek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var buildSummary: String {
        guard let server = session.server else { return "—" }
        let time = server.seconds.map { String(format: " · %.1fs", $0) } ?? ""
        return "#\(server.version) \(server.status)\(time)"
    }
}

/// Ways to hand the signing certificate to the dev server.
struct CertificateButtons: View {
    @Environment(Session.self) private var session
    @State private var picker = FilePicker()
    @State private var pickedFile: Data?
    @State private var pickedName = ""
    @State private var password = ""
    @State private var failure: String?

    var body: some View {
        Group {
            if let pickedFile {
                // Inline rather than an alert: an alert presented while the file picker
                // is still dismissing is silently dropped.
                Text(pickedName).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle)
                SecureField("Certificate password (may be empty)", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Send to dev server") {
                    session.submitCertificate(p12: pickedFile, password: password)
                    self.pickedFile = nil
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel", role: .cancel) { self.pickedFile = nil }
            } else {
                Button("Import a .p12 file…") {
                    picker.present(types: [.pkcs12, .data]) { url in
                        if let url { pick(url) }
                    }
                }
                Button("Import from SideStore") { request(scheme: "sidestore") }
                Button("Import from AltStore") { request(scheme: "altstore-classic") }
            }
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func pick(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try Self.certificateFile(at: url)
            let data = try Data(contentsOf: file)
            password = ""
            pickedName = file.lastPathComponent
            pickedFile = data
            failure = nil
            session.log("picked certificate file \(file.lastPathComponent) (\(data.count) bytes)")
        } catch {
            failure = "Could not read that file: \(error.localizedDescription)"
            session.log("could not read picked certificate: \(error.localizedDescription)", level: "error")
        }
    }

    struct NoCertificate: LocalizedError {
        var errorDescription: String? { "That folder has no .p12 file." }
    }

    /// The picked file, or the newest .p12 inside a picked folder. Some hosts (LiveContainer)
    /// turn the picker into one where "Open" returns the folder being browsed.
    private static func certificateFile(at url: URL) throws -> URL {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { return url }
        let files = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension.lowercased() == "p12" }
        func modified(_ file: URL) -> Date {
            (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        guard let newest = files.max(by: { modified($0) < modified($1) }) else { throw NoCertificate() }
        return newest
    }

    /// Asks the store to call back with `peek://certificate?cert=<base64 p12>&password=<password>`.
    /// This needs Peek installed as its own app; inside LiveContainer the callback cannot arrive.
    private func request(scheme: String) {
        let callback = "peek%3A%2F%2Fcertificate%3Fcert%3D%24%28BASE64_CERT%29%26password%3D%24%28PASSWORD%29"
        guard let url = URL(string: "\(scheme)://certificate?callback_template=\(callback)") else { return }
        failure = nil
        session.expectCertificateCallback()
        UIApplication.shared.open(url) { opened in
            if !opened {
                failure = "Could not open \(scheme == "sidestore" ? "SideStore" : "AltStore"). Export the certificate as a .p12 file there and import the file instead."
            }
        }
    }
}
