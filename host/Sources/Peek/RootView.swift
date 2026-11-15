import SwiftUI
import UIKit

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var showMenu = false
    @State private var dismissedError: String?
    @State private var stage = Stage()

    private var healthy: Bool { session.activeHost != nil && session.buildError == nil && !session.memoryLow }

    var body: some View {
        // A loaded preview is shown by `stage` in a window above this one.
        ZStack {
            if session.isPaired {
                StatusView(showMenu: $showMenu)
            } else {
                PairingView()
            }

            if let error = session.buildError, error != dismissedError, session.isPaired, session.controller == nil {
                BuildErrorView(text: error) { dismissedError = error }
            }
        }
        .sheet(isPresented: $showMenu) { MenuView() }
        .alert("Pair with this dev server?", isPresented: Binding(
            get: { session.pendingPairing != nil }, set: { if !$0 { session.cancelPairing() } }
        )) {
            Button("Pair") { session.confirmPairing() }
            Button("Cancel", role: .cancel) { session.cancelPairing() }
        } message: {
            Text((session.pendingPairing?.hosts ?? []).joined(separator: "\n")
                 + "\n\nOnly pair with a server you started with `peek dev`.")
        }
        .onChange(of: session.loadCount, initial: true) { stage.show(session.controller, session: session) }
        .onChange(of: session.controller == nil) { stage.show(session.controller, session: session) }
        .onChange(of: healthy, initial: true) { stage.setHealthy(healthy) }
        .onChange(of: session.buildError) { stage.showError(session.buildError) }
        .onChange(of: session.loadError) {
            if session.buildError == nil { stage.showError(session.loadError, title: "Could not load the build") }
        }
        .onAppear {
            session.snapshot = { [stage] in stage.snapshot() }
            session.displayChanged = { [stage, weak session] in
                if let session { stage.applyDisplay(session, report: true) }
            }
        }
    }
}

private struct StatusView: View {
    @Environment(Session.self) private var session
    @Binding var showMenu: Bool

    var body: some View {
        VStack(spacing: 16) {
            switch session.phase {
            case .needsCertificate:
                Image(systemName: "signature").font(.largeTitle).foregroundStyle(.tint)
                Text("One-time setup").font(.title3.bold())
                Text("iOS only loads code signed with your developer certificate. Import it from the store you installed Peek with; it is sent encrypted to your dev server and used to sign preview builds.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                CertificateButtons()
            case .loadFailed(let reason):
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                Text("Could not load the build").font(.title3.bold())
                ScrollView {
                    Text(reason)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
                Text("If this mentions a code signature, the certificate on the dev server is not the one this copy of Peek was signed with (or it was renewed). Import it again.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                CertificateButtons()
            case .incompatible(let server):
                Image(systemName: "arrow.triangle.2.circlepath").font(.largeTitle).foregroundStyle(.orange)
                Text("Versions don't match").font(.title3.bold())
                Text("The dev server runs peek \(server), and this is Peek \(PeekVersion.app). Use the app and the peek script from the same release.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Link("Releases", destination: URL(string: "https://github.com/kimikr/peek/releases")!)
                    .buttonStyle(.bordered)
            case .crashedLastTime:
                Image(systemName: "bolt.trianglebadge.exclamationmark").font(.largeTitle).foregroundStyle(.orange)
                Text("The last build quit the app").font(.title3.bold())
                Text("Peek closed while loading this build, so it was not loaded again. Save a change to send a new build, or try this one again.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Load it anyway") { session.retryCrashedBuild() }
                    .buttonStyle(.bordered)
            case .building:
                ProgressView()
                Text(session.buildError == nil ? "Waiting for a build…" : "Waiting for a build that compiles…")
                    .foregroundStyle(.secondary)
            default:
                ProgressView()
                Text("Looking for the dev server…").foregroundStyle(.secondary)
                Text(session.hosts.joined(separator: "\n"))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.tertiary)
                Text("Run `peek dev` on your computer. The phone must be on the same Wi-Fi or the same Tailscale network.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if let message = session.certificateMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Menu") { showMenu = true }
                .font(.footnote)
                .padding(.top, 8)
        }
        .padding(28)
    }
}
