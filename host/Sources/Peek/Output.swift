import Foundation

/// Forwards stdout and stderr of the previewed code to the dev server's terminal.
///
/// Both streams go to a file, not a pipe, so output written just before a crash
/// (e.g. a `fatalError` message) survives and is sent on the next launch.
@MainActor
final class Output {
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("output.log")
    private var sent: UInt64 = 0
    private var pending = ""
    private var leftover: String?
    /// The end of what the last run printed before Peek quit, to show on the crash screen.
    private(set) var lastWords: String?
    private weak var session: Session?
    private var timer: Timer?

    func start() {
        let path = file.path
        // Whatever the previous run wrote but did not get to send.
        let offset = UInt64(UserDefaults.standard.integer(forKey: "outputSent"))
        if let handle = FileHandle(forReadingAtPath: path) {
            try? handle.seek(toOffset: offset)
            if let data = try? handle.readToEnd(), !data.isEmpty {
                leftover = String(decoding: data, as: UTF8.self)
                lastWords = String(leftover!.suffix(4000)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            try? handle.close()
        }
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        fflush(stdout)
        fflush(stderr)
        dup2(fd, STDOUT_FILENO)
        dup2(fd, STDERR_FILENO)
        close(fd)
        setvbuf(stdout, nil, _IOLBF, 0)  // stdout to a file is otherwise fully buffered
        sent = 0
        UserDefaults.standard.set(0, forKey: "outputSent")
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// Called once connected: sends what was printed before the connection and before the last quit.
    func flush(to session: Session) {
        self.session = session
        if let leftover, session.sendOutput("(printed before Peek last quit)\n" + leftover, level: "crash") {
            self.leftover = nil
        }
        poll()
    }

    private func poll() {
        guard let handle = FileHandle(forReadingAtPath: file.path) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: sent)
        if let data = try? handle.readToEnd(), !data.isEmpty {
            sent += UInt64(data.count)
            if sent > 8 << 20 {  // a preview printing in a loop must not fill the disk
                truncate(file.path, 0)
                sent = 0
            }
            pending += String(decoding: data, as: UTF8.self)
            if pending.count > 64_000 { pending = String(pending.suffix(64_000)) }
        }
        guard !pending.isEmpty, let session, session.sendOutput(pending) else { return }
        pending = ""
        UserDefaults.standard.set(Int(sent), forKey: "outputSent")
    }
}
