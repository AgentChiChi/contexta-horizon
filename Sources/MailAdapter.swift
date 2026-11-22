// Contexta Horizon — the optional local Mac Mail adapter.
// Only on an explicit press of "Read Sources" (and a yes on its sheet), it asks the Mail app that is ALREADY RUNNING for the subject and
// date of the most recent Inbox and Sent messages: metadata only, no bodies, no addresses, no account credentials.
// It never starts Mail: if Mail is not running it says so and stops. macOS decides whether Horizon may ask Mail
// (System Settings › Privacy & Security › Automation); a refusal is reported as it is. What comes back is saved as a
// new import file like any other import, so nothing collected before (a Gmail feed, an earlier import) is touched.
// This is the only place the app runs an AppleScript, and the script is fixed text. It is not run inside the app:
// the system's own script runner (/usr/bin/osascript) runs it as a separate process, started off the main thread and
// stopped after a fixed time, so a slow or silent Mail can never freeze a window.

import AppKit

enum MailAdapter {
    static let bundleId = "com.apple.mail"
    /// At most this many messages are asked for from each of Inbox and Sent.
    static let cap = 200
    private static let sep = "\u{1F}"

    enum Outcome: Equatable {
        case notRunning
        case denied
        case unavailable(String)
        case collected(inbox: Int, sent: Int, inboxTotal: Int, sentTotal: Int, skipped: Int)

        /// What the person is told, truthfully.
        var message: String {
            switch self {
            case .notRunning: return "Mail is not running — Horizon never opens Mail by itself. Open Mail yourself, then press this again."
            case .denied: return "Permission denied — macOS did not allow Horizon to ask Mail (System Settings › Privacy & Security › Automation)."
            case .unavailable(let why): return "Could not collect from Mail — " + why
            case .collected(let inbox, let sent, let inboxTotal, let sentTotal, let skipped):
                let capped = inboxTotal > MailAdapter.cap || sentTotal > MailAdapter.cap
                return "Read from Mail: Inbox \(inbox) (of \(inboxTotal)), Sent \(sent) (of \(sentTotal))"
                    + (capped ? " — only the newest \(MailAdapter.cap) of each; older mail is not included" : "") + (skipped > 0 ? " · \(plural(skipped, "line")) could not be read" : "")
            }
        }
    }

    /// The fixed, read-only script. Nothing from data is ever put into it; only the cap (a number) is.
    static func script(cap: Int) -> String {
        let n = max(1, min(cap, 1000))
        func block(_ letter: String, _ box: String, _ dateField: String) -> String {
            return """
                set total to count of messages of \(box)
                set n to total
                if n > \(n) then set n to \(n)
                set out to out & "N" & sep & "\(letter)" & sep & total & linefeed
                repeat with i from 1 to n
                    try
                        set m to message i of \(box)
                        set out to out & "\(letter)" & sep & (message id of m) & sep & ((\(dateField) of m) as «class isot» as string) & sep & (subject of m) & linefeed
                    end try
                end repeat

            """
        }
        // The first line makes the script itself stop when Mail is not running (asking "is running" starts nothing), so
        // even if Mail quits between Horizon's own check and this moment, the script cannot be what opens it.
        return "if application id \"\(bundleId)\" is not running then error number -600\nset sep to character id 31\nset out to \"\"\nwith timeout of 90 seconds\n    tell application id \"\(bundleId)\"\n"
            + block("I", "inbox", "date received") + block("S", "sent mailbox", "date sent")
            + "    end tell\nend timeout\nreturn out\n"
    }

    /// Turns the script's answer into import rows: subject and date only; the Message-ID is kept as a hash.
    static func parse(_ reply: String) -> (rows: [[String: Any]], outcome: Outcome) {
        var rows: [[String: Any]] = [], totals: [String: Int] = [:], counts: [String: Int] = [:], skipped = 0
        for line in reply.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let f = line.components(separatedBy: sep)
            if f.count == 3, f[0] == "N" { totals[f[1]] = Int(f[2]) ?? 0; continue }
            guard f.count == 4, f[0] == "I" || f[0] == "S", counts[f[0], default: 0] < cap, let title = Clean.text(f[3], max: Clean.maxTitle), let date = Dates.parse(String(f[2].prefix(19)))?.date else { skipped += 1; continue }
            counts[f[0], default: 0] += 1
            let key = Hash.hex(f[1].isEmpty ? title + "\n" + f[2] : f[1])
            rows.append(Importer.row(id: "macmail:" + key, title: title, date: date, source: f[0] == "I" ? "Mac Mail Inbox" : "Mac Mail Sent", locator: "", kind: .mail, via: "macmail"))
        }
        return (rows, .collected(inbox: counts["I"] ?? 0, sent: counts["S"] ?? 0, inboxTotal: totals["I"] ?? 0, sentTotal: totals["S"] ?? 0, skipped: skipped))
    }

    static func classify(error code: Int) -> Outcome {
        switch code {
        case -1743, -1744: return .denied
        case -600, -609: return .notRunning
        case -1712: return .unavailable("Mail did not answer in time (timed out)")
        case refusedOnMainThread: return .unavailable("not asked (the request would have blocked the window)")
        default: return .unavailable("Mail could not answer (\(code))")
        }
    }

    /// The whole decision, with the Mac's side passed in (so it can be tested without Mail): Mail must already be
    /// running, macOS must allow the question, and only then is the script run. Nothing here opens an app.
    static func collect(isRunning: () -> Bool, permission: () -> Int, run: (String) -> (reply: String?, error: Int)) -> (rows: [[String: Any]], outcome: Outcome) {
        guard isRunning() else { return ([], .notRunning) }
        let allowed = permission()
        guard allowed == 0 else { return ([], classify(error: allowed)) }
        guard isRunning() else { return ([], .notRunning) }             // it may have quit while macOS was asking
        let answer = run(script(cap: cap))
        guard let reply = answer.reply else { return ([], classify(error: answer.error)) }
        return parse(reply)
    }

    // What "Read Sources" does about Mail — decided before anything of Mail is touched.

    enum Step: Equatable {
        case ask                    // put the question to the person (a sheet); nothing has been asked of Mail yet
        case skip(String)           // read the local sources only, and say why Mail is not part of it
    }
    /// Mail can be part of a read only while Imports, AI chats and Mail are all on (what is collected is saved as an
    /// import, and imports are read only then), while no other collection is under way, and while Mail is already
    /// running. The switches are looked at first: with one of them off, not even "is Mail running?" is asked.
    static func step(enabled: Set<SourceKind>, underway: Bool, isRunning: () -> Bool) -> Step {
        guard Snapshot.readsImports(enabled) else { return .skip("Imports, AI chats and Mail are not all switched on") }
        if underway { return .skip("a Mail collection is already under way") }
        guard isRunning() else { return .skip("Mail is not running, and Horizon never opens it") }
        return .ask
    }
    /// Asked again at the moment of saving: what was collected is kept only if the switches still allow it.
    static func mayKeep(_ enabled: Set<SourceKind>) -> Bool { Snapshot.readsImports(enabled) }

    /// The Mac's side of a collection, passed in so that tests can replace it (Mail itself is never asked there).
    struct Side {
        var isRunning: () -> Bool
        var permission: () -> Int
        var run: (String) -> (reply: String?, error: Int)
        static let live = Side(isRunning: MailAdapter.liveIsRunning, permission: MailAdapter.livePermission, run: MailAdapter.liveRun)
    }

    // The Mac's side, used only from the "Read Sources" action after its sheet was answered with yes.

    static func liveIsRunning() -> Bool { NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).contains { !$0.isTerminated } }

    /// Asks macOS whether Horizon may send Mail this question; macOS shows its own prompt the first time.
    static func livePermission() -> Int {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        return Int(AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true))
    }

    /// The system's script runner, at its fixed place. The script reaches it on standard input: nothing of it is on a
    /// command line, and nothing a person typed or a record contains is ever part of it (see `script`).
    static let helper = "/usr/bin/osascript"
    static let helperTimeout: TimeInterval = 100                      // the script itself gives Mail 90 seconds
    static let refusedOnMainThread = -9001

    static func liveRun(_ source: String) -> (reply: String?, error: Int) { osascript(source, timeout: helperTimeout) }

    /// Runs a script in the helper process and waits for it — never on the main thread (it would freeze the windows;
    /// asked there, it refuses). The process is stopped when the time is up.
    static func osascript(_ source: String, timeout: TimeInterval) -> (reply: String?, error: Int) {
        guard !Thread.isMainThread else { return (nil, refusedOnMainThread) }
        let p = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        p.executableURL = URL(fileURLWithPath: helper)
        p.arguments = ["-"]
        p.environment = ["PATH": "/usr/bin:/bin"]
        p.standardInput = input; p.standardOutput = output; p.standardError = errors
        guard (try? p.run()) != nil else { return (nil, 0) }
        let timedOut = TimedOut()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { if p.isRunning { timedOut.set(); p.terminate() } }
        try? input.fileHandleForWriting.write(contentsOf: Data(source.utf8))
        try? input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return helperResult(status: p.terminationStatus, timedOut: timedOut.value, output: out, errors: err)
    }
    private final class TimedOut { private var flag = false; private let lock = NSLock(); func set() { lock.lock(); flag = true; lock.unlock() }; var value: Bool { lock.lock(); defer { lock.unlock() }; return flag } }

    /// What the helper's end means: its text when it ended well; otherwise the AppleScript error number it printed
    /// (the last "(-1743)" in its error text), a timeout when it had to be stopped, or 0 when nothing can be told.
    static func helperResult(status: Int32, timedOut: Bool, output: Data, errors: Data) -> (reply: String?, error: Int) {
        if timedOut { return (nil, -1712) }
        if status == 0 {
            var text = String(decoding: output, as: UTF8.self)
            if text.hasSuffix("\n") { text.removeLast() }                // the runner adds one line end after the result
            return (text, 0)
        }
        let said = String(decoding: errors, as: UTF8.self)
        guard let r = said.range(of: #"\((-?\d+)\)\s*$"#, options: .regularExpression), let n = Int(said[r].filter { $0 == "-" || $0.isNumber }) else { return (nil, 0) }
        return (nil, n)
    }
}
