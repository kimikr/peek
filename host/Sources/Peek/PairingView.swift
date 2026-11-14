import SwiftUI
import UIKit

struct PairingView: View {
    @Environment(Session.self) private var session
    @State private var link = ""
    @State private var invalid = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "eye")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("Peek").font(.largeTitle.bold())
            Text("Run `peek dev` on your computer, then scan the QR code with the Camera app or paste the pairing link here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            TextField("peek://connect?…", text: $link, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Paste") {
                    link = UIPasteboard.general.string ?? ""
                    connect()
                }
                .buttonStyle(.bordered)
                Button("Connect", action: connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(link.isEmpty)
            }
            if invalid {
                Text("That is not a peek:// pairing link.").font(.footnote).foregroundStyle(.red)
            }
            Spacer()
            Spacer()
        }
        .padding(28)
    }

    private func connect() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), session.open(url, trusted: true) else {
            invalid = !trimmed.isEmpty
            return
        }
        invalid = false
    }
}
