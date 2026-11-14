import Foundation
import Network

/// Finds the paired dev server on the local network through Bonjour (`_peek._tcp`).
///
/// The server's TXT record carries its addresses and an id derived from the pairing key,
/// so only the server this phone is paired with is picked up.
@MainActor
final class Discovery {
    private var browser: NWBrowser?

    func start(serverID: String, onChange: @escaping @MainActor ([String]) -> Void) {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_peek._tcp", domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { results, _ in
            var hosts: [String] = []
            for result in results {
                guard case .bonjour(let record) = result.metadata, record["id"] == serverID,
                      let list = record["hosts"] else { continue }
                hosts += list.split(separator: ",").map(String.init)
            }
            Task { @MainActor in onChange(hosts) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
