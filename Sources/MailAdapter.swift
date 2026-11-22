// Contexta Horizon — the optional local Mac Mail adapter.
// Only on an explicit click (and a confirmation), it asks the Mail app that is ALREADY RUNNING for the subject and
// date of the most recent Inbox and Sent messages: metadata only, no bodies, no addresses, no account credentials.
// It never starts Mail: if Mail is not running it says so and stops. macOS decides whether Horizon may ask Mail
// (System Settings › Privacy & Security › Automation); a refusal is reported as it is. What comes back is saved as a
// new import file like any other import, so nothing collected before (a Gmail feed, an earlier import) is touched.
// This is the only place the app runs an AppleScript, and the script is fixed text.

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
        return "set sep to character id 31\nset out to \"\"\nwith timeout of 90 seconds\n    tell application id \"\(bundleId)\"\n"
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

    // The Mac's side, used only from the window's "Collect from Mail…" action.

    static func liveIsRunning() -> Bool { NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).contains { !$0.isTerminated } }

    /// Asks macOS whether Horizon may send Mail this question; macOS shows its own prompt the first time.
    static func livePermission() -> Int {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        return Int(AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true))
    }

    static func liveRun(_ source: String) -> (reply: String?, error: Int) {
        guard let script = NSAppleScript(source: source) else { return (nil, 0) }
        var info: NSDictionary?
        let result = script.executeAndReturnError(&info)
        if let info = info { return (nil, (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0) }
        return (result.stringValue ?? "", 0)
    }
}
