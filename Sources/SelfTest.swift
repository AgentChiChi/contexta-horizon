// Contexta Horizon — synthetic self-test:  contexta-horizon.app/Contents/MacOS/ContextaHorizon --self-test
// Fast, deterministic and offline. Everything is fictional and made in a temporary folder (a pretend home), removed at
// the end. It opens no window, reads no real ~/WorkIndex, touches no clipboard and no settings, and never asks the
// Mail app anything (the Mail adapter is tested with its Mac side passed in). The programs it starts are a synthetic
// refresh.command it wrote itself in that temporary folder, this same executable with --aside-lookup (the headless
// lookup, pointed at the temporary folder, with every setting given on its command line), and the system's script
// runner with four tiny fixed scripts that address no app (to check the helper the Mail step uses).

import AppKit
import Foundation

func runSelfTest() -> Int32 {
    var passed = 0, failed = 0
    func check(_ id: String, _ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { passed += 1; print("PASS \(id)  \(name)") } else { failed += 1; print("FAIL \(id)  \(name)" + (detail.isEmpty ? "" : "\n       → " + detail)) }
    }
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent("horizon-selftest-" + UUID().uuidString, isDirectory: true)
    defer { try? fm.removeItem(at: temp) }
    func write(_ url: URL, _ text: String) { try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try? Data(text.utf8).write(to: url) }
    func json(_ o: Any) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data(), as: UTF8.self) }

    // ── calendar windows (a fixed "now" in Seoul time) ──
    var seoul = Calendar(identifier: .gregorian); seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date { seoul.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))! }
    let now = at(2026, 5, 31, 15, 0)
    let w3 = HorizonWindow(months: 3, now: now, calendar: seoul), w6 = HorizonWindow(months: 6, now: now, calendar: seoul)
    let leap = HorizonWindow(months: 3, now: at(2028, 5, 31, 9), calendar: seoul), sep = HorizonWindow(months: 6, now: at(2026, 3, 31, 9), calendar: seoul)
    check("H01", "calendar windows: from 31 May 2026 15:00, 3 months starts 28 Feb 00:00 and 6 months 30 Nov 2025 00:00 (the day is clamped to a shorter month's end); 29 Feb in a leap year; 31 Mar − 6 months = 30 Sep; the end is now; any other length falls back to 3",
          w3.start == at(2026, 2, 28) && w6.start == at(2025, 11, 30) && leap.start == at(2028, 2, 29) && sep.start == at(2025, 9, 30) && w3.end == now && HorizonWindow(months: 5, now: now, calendar: seoul).months == 3,
          "\(Dates.day(w3.start, seoul)) \(Dates.day(w6.start, seoul)) \(Dates.day(leap.start, seoul)) \(Dates.day(sep.start, seoul))")
    func ev(_ date: Date, dayOnly: Bool = false, origin: SourceKind = .ai, type: RecordType = .ai, title: String = "t", topics: [String] = [], source: String = "s", via: String = "feed") -> Evidence {
        Evidence(origin: origin, type: type, id: UUID().uuidString, title: title, date: date, dayOnly: dayOnly, source: source, topics: topics, locator: "", importedAt: nil, via: via)
    }
    check("H02", "boundaries: the first day of the window is in (as a day and at 00:00:00), the second before it and the day before are out; exactly now is in, one second later is future; today as a bare date is in, tomorrow is future; a record 4 months old is in 6 months but not in 3",
          w3.contains(ev(at(2026, 2, 28), dayOnly: true)) && w3.contains(ev(at(2026, 2, 28, 0, 0, 0))) && !w3.contains(ev(at(2026, 2, 27, 23, 59, 59))) && !w3.contains(ev(at(2026, 2, 27), dayOnly: true)) &&
          w3.contains(ev(now)) && !w3.contains(ev(now.addingTimeInterval(1))) && w3.isFuture(ev(now.addingTimeInterval(1))) && w3.contains(ev(at(2026, 5, 31), dayOnly: true)) &&
          !w3.contains(ev(at(2026, 6, 1), dayOnly: true)) && w3.isFuture(ev(at(2026, 6, 1), dayOnly: true)) && !w3.isFuture(ev(at(2026, 1, 15))) &&
          !w3.contains(ev(at(2026, 1, 31, 12))) && w6.contains(ev(at(2026, 1, 31, 12))) && !w6.contains(ev(at(2025, 11, 29, 23, 59, 59))))
    let parsedDates = [Dates.parse("2026-05-20T10:00:00+09:00", calendar: seoul), Dates.parse("2026-05-20T01:00:00.250Z", calendar: seoul), Dates.parse("2026-05-20", calendar: seoul), Dates.parse("2026-05-20T10:00:00", calendar: seoul)]
    check("H03", "dates: ISO date-times with a zone, with fractions, without a zone (this Mac's time) and bare YYYY-MM-DD (a local day) are read; 2026-02-30, 2026-13-01, words, numbers and overlong strings are refused",
          parsedDates[0]?.date == at(2026, 5, 20, 10) && parsedDates[0]?.dayOnly == false && parsedDates[1]?.date == at(2026, 5, 20, 10).addingTimeInterval(0.25) && parsedDates[2]?.date == at(2026, 5, 20) && parsedDates[2]?.dayOnly == true && parsedDates[3]?.date == at(2026, 5, 20, 10) &&
          Dates.parse("2026-02-30", calendar: seoul) == nil && Dates.parse("2026-13-01", calendar: seoul) == nil && Dates.parse("yesterday") == nil && Dates.parse(20260520) == nil && Dates.parse(String(repeating: "2", count: 80)) == nil)

    // ── a pretend home with fictional feeds, dated relative to the real now (the app reads with the Mac's calendar) ──
    let home = temp.appendingPathComponent("home", isDirectory: true), places = Places(home: home)
    let real = Date()
    func ago(_ days: Double) -> String { Dates.isoString(real.addingTimeInterval(-days * 86400)) }
    func fileRow(_ name: String, _ days: Double, _ tags: [String]) -> String { json(["name": name, "path": "/Users/mina/Work/" + name, "source": "Mac", "modified": ago(days), "tags": tags, "review": false]) }
    func row(_ id: String, _ title: String, _ date: String, _ topics: [String], _ source: String) -> String { json(["id": id, "title": title, "date": date, "topics": topics, "source": source, "locator": "ref:" + id]) }
    let filesText = [fileRow("Harborline Q3 quote.xlsx", 20, ["source:mac", "kind:spreadsheet", "topic:harborline", "workflow:quote", "folder:harborline"]),
                     fileRow("plan.pdf", 25, ["source:mac", "kind:pdf", "topic:harborline", "ext:pdf", "month:2026-01", "pdf", "2026-11", "Mac"]),
                     fileRow("layout A.sketch", 30, ["source:mac", "kind:design", "topic:atlas", "workflow:draft", "folder:misc"]),
                     fileRow("layout B.sketch", 31, ["source:mac", "kind:design", "topic:atlas", "ext:sketch", "month:2026-01"]),
                     fileRow("old northfield.docx", 220, ["source:mac", "kind:document", "topic:northfield", "ext:docx", "year:2026"])].joined(separator: "\n") + "\n"
    let aiText = [row("a1", "Harborline 견적 검토", ago(20), ["Harborline", "misc"], "Claude"),
                  row("a2", "Northfield cap 정리", ago(120), ["Northfield"], "Claude"),
                  row("a3", "혼자 있는 주제", ago(10), ["Solo"], "Claude"),
                  row("a4", "내일 일정", Dates.isoString(real.addingTimeInterval(2 * 86400)), ["Harborline"], "Claude"),
                  row("a5", "2026-11 pdf 정리 Claude November", ago(12), ["2026-11", "pdf", "Claude", "2026", "November", "Q3 2026", "Mac", "needs review", "11월", "스냅샷"], "Claude"),
                  row("a6", "pdf 변환과 2026 November 계획", ago(13), ["pdf", "2026", "November"], "Claude")].joined(separator: "\n") + "\n"
    let mailText = [row("m1", "RE: Harborline quote", ago(18), [], "Mail"),
                    row("m2", "Northfield 일정 확인", ago(125), ["northfield"], "Mail"),
                    row("m3", "Northfield 재확인", ago(15), [], "Mail")].joined(separator: "\n") + "\n"
    write(places.preindex, filesText); write(places.ai, aiText); write(places.mail, mailText)
    write(places.manifest, json(["files": ["collectedAt": ago(1), "coverage": "all dates"], "ai": ["collectedAt": ago(30), "coverage": ["complete": false, "from": "2026-01-01"]], "mail": ["collectedAt": ago(2), "coverage": "partial: last 90 days only"]]))
    let snap = Snapshot.read(places, now: real)
    let all = Set(SourceKind.allCases)
    let h3 = HorizonWindow(months: 3, now: real), h6 = HorizonWindow(months: 6, now: real)
    let t3 = Analysis.topics(snap.evidence, window: h3, enabled: all), t6 = Analysis.topics(snap.evidence, window: h6, enabled: all)
    func names(_ t: [TopicSummary]) -> String { t.map { "\($0.key):\($0.types.map { $0.rawValue }.joined(separator: "+")):\($0.items.count)" }.joined(separator: " | ") }
    check("H04", "3 months: Harborline is found across three record types (2 files, 1 AI, 1 mail — the mail joined by its title alone) and Atlas in files only; a topic with one inferred mention (Solo), low-signal words (misc) and the future-dated record are left out",
          names(t3) == "harborline:file+ai+mail:4 | atlas:file:2" && t3[0].multiType && !t3[1].multiType, names(t3))
    check("H05", "the vocabulary comes only from records in the window: \"Northfield\" is a topic only on records older than 3 months, so the recent mail titled \"Northfield 재확인\" does not bring it into the 3-month view; in 6 months it is a multi-type topic with that mail included",
          !t3.contains { $0.key == "northfield" } && names(t6) == "harborline:file+ai+mail:4 | northfield:ai+mail:3 | atlas:file:2", names(t6))
    check("H06", "dates, formats, source names and generated labels are never topics, even when titles repeat them: no \"2026-11\", \"2026\", \"pdf\", \"November\", \"11월\", \"Q3 2026\", \"Claude\", \"Mac\", \"needs review\" or \"스냅샷\"",
          ["2026 11", "2026", "pdf", "november", "11월", "q3 2026", "claude", "mac", "needs review", "스냅샷"].allSatisfy { k in !t6.contains { $0.key == k } } &&
          ["2026 11", "2026", "11월", "q3 2026", "fy26", "2026년 11월", "pdf", "xlsx", "november", "unknown", "not found"].allSatisfy { Topic.isLowSignal($0) } && Topic.isLowSignal("claude", sources: ["claude"]) &&
          !Topic.isLowSignal("harborline") && !Topic.isLowSignal("atlas 2") && !Topic.isLowSignal("3d 모델"), names(t6))
    let hb = t3.first { $0.key == "harborline" }
    let signals = hb?.items.map { "\($0.evidence.title)=\($0.direct ? "direct" : "inferred")" }.sorted().joined(separator: ";") ?? ""
    check("H07", "direct vs inferred: a title that names the topic is a direct signal (the quote file, the AI chat, the mail); plan.pdf is linked only by its tag, so it is inferred; Atlas is inferred throughout; the topic is shown as people wrote it (Harborline, not the lower-case tag)",
          signals == "Harborline Q3 quote.xlsx=direct;Harborline 견적 검토=direct;RE: Harborline quote=direct;plan.pdf=inferred" && hb?.direct == 3 && hb?.inferred == 1 &&
          t3[1].direct == 0 && t3[1].inferred == 2 && hb?.display == "Harborline" && (hb?.typesLabel.hasSuffix("(several types)") ?? false) && t3[1].typesLabel == "File (one type)", signals)

    // ── source switches ──
    let noMail = Analysis.topics(snap.evidence, window: h3, enabled: [.files, .ai, .imports]), onlyFiles = Analysis.topics(snap.evidence, window: h3, enabled: [.files])
    check("H08", "source switches: with mail off Harborline has two types and three items; with only files on it is single-type; a source that is off says so and is not counted",
          names(noMail) == "harborline:file+ai:3 | atlas:file:2" && names(onlyFiles) == "harborline:file:2 | atlas:file:2" &&
          snap.coverage(for: .mail, window: h3, enabled: [.files, .ai]).summary.hasPrefix("Off — not used") && Analysis.topics(snap.evidence, window: h3, enabled: []).isEmpty, names(noMail) + " // " + names(onlyFiles))

    // ── coverage ──
    let cFiles = snap.coverage(for: .files, window: h3, enabled: all).summary, cAI = snap.coverage(for: .ai, window: h3, enabled: all).summary, cMail = snap.coverage(for: .mail, window: h3, enabled: all).summary, cImp = snap.coverage(for: .imports, window: h3, enabled: all).summary
    check("H09", "coverage says what was really read: files 4 of 5 in the window, a feed collected a day ago; AI 4 in the window, 1 future-dated record excluded, collected 30 days ago (stale) and marked partial by its manifest; mail 2 in the window with the manifest's \"partial\" note; no imports yet",
          cFiles.hasPrefix("4 in this period (5 total)") && cFiles.contains("Feed collected: ") && !cFiles.contains("stale") && cFiles.contains("Coverage: all dates") &&
          cAI.hasPrefix("4 in this period (6 total)") && cAI.contains("1 future-dated left out") && cAI.contains("(stale)") && cAI.contains("Marked as partially collected") && cAI.contains("Coverage: complete: false, from: 2026-01-01") &&
          cMail.hasPrefix("2 in this period (3 total)") && cMail.contains("Coverage: partial: last 90 days only") && cMail.contains("Marked as partially collected") && cImp == "Nothing imported yet", [cFiles, cAI, cMail, cImp].joined(separator: " || "))
    let home2 = temp.appendingPathComponent("home2", isDirectory: true), p2 = Places(home: home2)
    write(p2.preindex, fileRow("ancient.docx", 400, ["topic:atlas"]) + "\n")
    write(p2.ai, "")
    try? fm.createDirectory(at: p2.horizon, withIntermediateDirectories: true)
    try? fm.createSymbolicLink(at: p2.mail, withDestinationURL: places.mail)
    let s2 = Snapshot.read(p2, now: real)
    let z = SourceKind.allCases.map { s2.coverage(for: $0, window: h3, enabled: all).summary }
    let home3 = temp.appendingPathComponent("home3", isDirectory: true), s3 = Snapshot.read(Places(home: home3), now: real)
    let missing = [SourceKind.files, .ai, .mail].map { s3.coverage(for: $0, window: h3, enabled: all).summary }
    check("H10", "zero hits is not the same as missing: rows but none in this window → \"0 in this period (1 total)\" with an unknown collection time and the file's own date; an empty file → \"Empty\"; a link → not read; no file at all → \"No data\"; and none of these makes a topic",
          z[0].hasPrefix("0 in this period (1 total)") && z[0].contains("Feed — collection time unknown · file modified: ") && z[1].hasPrefix("Empty — no rows") && z[2] == "Not read — it is a link, so it is not read" &&
          missing.allSatisfy { $0.hasPrefix("No data — the file does not exist") } && Analysis.topics(s2.evidence, window: h3, enabled: all).isEmpty && s3.evidence.isEmpty && s3.manifest.problem == "file not found", (z + missing).joined(separator: " || "))

    // ── malformed and hostile input ──
    let home4 = temp.appendingPathComponent("home4", isDirectory: true), p4 = Places(home: home4)
    var bad = Data()
    func line(_ s: String) { bad.append(Data((s + "\n").utf8)) }
    line(row("ok1", "정상\u{0007} 제목\t하나\u{202E}", ago(3), ["Harborline"] + (0..<40).map { "t\($0)" }, "Mail"))
    line("not json at all"); line("[1,2,3]"); line("{\"id\":\"x\"}")
    line(json(["id": 5, "title": "숫자 id", "date": ago(3), "topics": [String](), "source": "Mail", "locator": ""]))
    line(json(["id": "d", "title": "나쁜 날짜", "date": "2026-02-30", "topics": [String](), "source": "Mail", "locator": ""]))
    line(json(["id": "t", "title": "주제가 배열이 아님", "date": ago(3), "topics": "Harborline", "source": "Mail", "locator": ""]))
    line(json(["id": "big", "title": String(repeating: "가", count: 40_000), "date": ago(3), "topics": [String](), "source": "Mail", "locator": ""]))
    bad.append(Data([0xFF, 0xFE, 0x00, 0x80, 0x0A]))
    line(row("ok2", String(repeating: "긴 제목 ", count: 200), ago(4), ["Harborline"], "Mail"))
    line("")
    try? fm.createDirectory(at: p4.horizon, withIntermediateDirectories: true); try? bad.write(to: p4.mail)
    let s4 = Snapshot.read(p4, now: real), l4 = s4.coverage[.mail]!
    let first = l4.rows.first, c4 = s4.coverage(for: .mail, window: h3, enabled: all).summary
    check("H11", "malformed lines never stop the read: of 10 lines 2 are kept and 8 skipped and counted (not JSON, not an object, missing or wrongly typed fields, an impossible date, a line over 64 KB, bytes that are not text); control and direction characters leave titles, long titles are cut to 200 characters, topics are capped at 24; coverage says the read was partial",
          l4.lines == 10 && l4.rows.count == 2 && l4.skipped == 8 && first?.title == "정상 제목 하나" && (first?.topics.count ?? 0) == 24 && (l4.rows.last?.title.count ?? 0) == 200 &&
          c4.contains("Read in part — 8 bad lines skipped"), "\(l4.lines) \(l4.rows.count) \(l4.skipped) [\(first?.title ?? "")] \(first?.topics.count ?? -1) \(c4)")

    // ── import adapters: Gmail Takeout and Apple Mail .mbox, ChatGPT and Claude exports, normalised .jsonl ──
    let aiBefore = fm.contents(atPath: places.ai.path), mailBefore = fm.contents(atPath: places.mail.path), filesBefore = fm.contents(atPath: places.preindex.path)
    let importTime = real.addingTimeInterval(-3600)
    let gmailURL = temp.appendingPathComponent("export/All mail Including Spam and Trash.mbox")
    let euc = "=?EUC-KR?B?" + Data([0xB0, 0xDF, 0xC0, 0xFB]).base64EncodedString() + "?= Atlas"
    write(gmailURL, ["From 1234567890@xxx Mon Nov 16 10:00:00 +0000 2026", "X-Gmail-Labels: Inbox,Important", "From: Dana Okafor <dana.okafor@harborline-tooling.example>", "To: me@example.com",
                     "Subject: =?UTF-8?B?" + Data("Harborline 견적 회신".utf8).base64EncodedString() + "?=", "Date: " + rfc2822(real.addingTimeInterval(-5 * 86400)), "Message-ID: <mb1@example.com>", "",
                     "BODY-SECRET first body line", ">From the body, not a new message", "",
                     "From 1234567891@xxx Tue Nov 17 10:00:00 +0000 2026", "X-Gmail-Labels: Sent", "Subject: =?utf-8?Q?Atlas_layout_=EA=B2=80=ED=86=A0?=", "Date: " + rfc2822(real.addingTimeInterval(-6 * 86400)), "Message-ID: <mb2@example.com>", "",
                     "BODY-SECRET second", "",
                     "From sender@example.com Wed Nov 18 10:00:00 2026", "Subject: " + euc, " continued", "Date: " + rfc2822(real.addingTimeInterval(-7 * 86400)), "", "BODY-SECRET third", "",
                     "From sender@example.com Thu Nov 19 10:00:00 2026", "Subject: no date here", "", "BODY-SECRET fourth", ""].joined(separator: "\n"))
    let mb = Importer.parse(gmailURL)
    let saved1 = Importer.save(mb, name: "All mail", places: places, now: importTime)
    let savedText = saved1.file.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    let mode = { (u: URL?) -> Int in ((try? fm.attributesOfItem(atPath: u?.path ?? ""))?[.posixPermissions] as? NSNumber)?.intValue ?? 0 }
    check("H12", "Gmail Takeout .mbox: headers only — three messages with decoded subjects (UTF-8 base64, quoted-printable, EUC-KR with a folded line) and dates; Inbox and Sent told apart by X-Gmail-Labels; the message without a Date is skipped and counted; no body, no address and no raw Message-ID is kept (the id is a hash); a \">From\" body line is not a new message",
          mb.rows.count == 3 && mb.skipped == 1 && (mb.rows.map { $0["title"] as? String ?? "" }) == ["Harborline 견적 회신", "Atlas layout 검토", "견적 Atlas continued"] &&
          (mb.rows.map { $0["source"] as? String ?? "" }) == ["Gmail Takeout Inbox", "Gmail Takeout Sent", "Mail export All mail Including Spam and Trash"] &&
          ((mb.rows[0]["id"] as? String) ?? "").hasPrefix("mbox:") && !savedText.contains("BODY-SECRET") && !savedText.contains("the body") && !savedText.contains("@") && !savedText.contains("mb1") && !savedText.contains("Okafor"),
          "\(mb.rows.count) \(mb.skipped) \(mb.rows.map { $0["source"] as? String ?? "" })")
    let again = Importer.save(Importer.parse(gmailURL), name: "All mail", places: places, now: real)
    let appleURL = temp.appendingPathComponent("export/Work.mbox", isDirectory: true)
    write(appleURL.appendingPathComponent("mbox"), ["From MAILER-DAEMON Fri Nov 20 10:00:00 2026", "Subject: Atlas =?UTF-8?B?" + Data("일정 공유".utf8).base64EncodedString() + "?=", "Date: " + rfc2822(real.addingTimeInterval(-9 * 86400)), "Message-ID: <apple1@example.com>", "", "BODY-SECRET apple", "",
                                                    "From MAILER-DAEMON Fri Nov 20 11:00:00 2026", "Subject: =?UTF-8?B?" + Data("Harborline 견적 회신".utf8).base64EncodedString() + "?=", "Date: " + rfc2822(real.addingTimeInterval(-5 * 86400)), "Message-ID: <mb1@example.com>", "", "same message as in the Gmail export", ""].joined(separator: "\n"))
    let apple = Importer.parse(appleURL), saved2 = Importer.save(apple, name: "Work", places: places, now: importTime)
    let notMbox = Importer.parse(temp.appendingPathComponent("export", isDirectory: true))
    check("H13", "importing the same export again adds nothing (0 new, 3 already there, no file written); an Apple Mail export (a \"Work.mbox\" folder holding an \"mbox\" file) is read the same way and only its one new message is added — the message already imported from Gmail is not duplicated; a folder without an mbox file is refused",
          again.imported == 0 && again.duplicates == 3 && again.file == nil && again.problem == nil && apple.rows.count == 2 && saved2.imported == 1 && saved2.duplicates == 1 &&
          (apple.rows[0]["source"] as? String) == "Mail export Work" && notMbox.problem != nil && ((try? fm.contentsOfDirectory(atPath: places.imports.path))?.count ?? 0) == 2,
          "\(again.imported)/\(again.duplicates) \(saved2.imported)/\(saved2.duplicates) \(String(describing: notMbox.problem))")
    func epoch(_ days: Double) -> Double { real.addingTimeInterval(-days * 86400).timeIntervalSince1970 }
    func node(_ id: String, _ role: String, _ time: Double?, _ text: String, type: String = "text") -> [String: Any] {
        var msg: [String: Any] = ["id": id, "author": ["role": role], "content": ["content_type": type, "parts": [text]]]
        if let t = time { msg["create_time"] = t }
        return ["id": id, "message": msg]
    }
    let chatgptURL = temp.appendingPathComponent("export/chatgpt/conversations.json")
    write(chatgptURL, json([["title": "Harborline 가격 협상 준비", "conversation_id": "conv-SECRET-1", "create_time": epoch(150),
                             "mapping": ["root": ["id": "root"], "s1": node("s1", "system", epoch(150), "SYSTEM-SECRET"), "ctx": node("ctx", "user", epoch(150), "PROFILE-SECRET", type: "user_editable_context"),
                                         "u3": node("u3", "user", epoch(150), "USER-TEXT-SECRET old"), "u1": node("u1", "user", epoch(11), "USER-TEXT-SECRET 질문"), "a1": node("a1", "assistant", epoch(11), "ASSISTANT-SECRET"),
                                         "t1": node("t1", "tool", epoch(11), "TOOL-SECRET"), "u2": node("u2", "user", epoch(11) - 600, "USER-TEXT-SECRET 다시")]],
                            ["title": "Atlas 온보딩", "id": "conv-SECRET-2", "mapping": ["u1": node("u1", "user", epoch(13), "USER-TEXT-SECRET atlas"), "a1": node("a1", "assistant", epoch(13), "ASSISTANT-SECRET")]],
                            "not a conversation"] as [Any]))
    let claudeURL = temp.appendingPathComponent("export/claude/conversations.json")
    write(claudeURL, json([["uuid": "claude-SECRET-uuid", "name": "Harborline 계약 조항 질문", "created_at": ago(14),
                            "chat_messages": [["uuid": "h1", "sender": "human", "created_at": ago(14), "text": "HUMAN-TEXT-SECRET"], ["uuid": "x1", "sender": "assistant", "created_at": ago(14), "text": "ASSISTANT-SECRET-2"],
                                              ["uuid": "h2", "sender": "human", "created_at": "not a date", "text": "HUMAN-TEXT-SECRET"]]]]))
    let gpt = Importer.parse(chatgptURL), cl = Importer.parse(claudeURL)
    let saved3 = Importer.save(gpt, name: "chatgpt", places: places, now: importTime), saved4 = Importer.save(cl, name: "claude", places: places, now: importTime)
    let chatText = [saved3.file, saved4.file].compactMap { $0.flatMap { try? String(contentsOf: $0, encoding: .utf8) } }.joined()
    let gptDates = gpt.rows.compactMap { Dates.parse($0["date"])?.date }.map { Int(real.timeIntervalSince($0) / 86400 + 0.5) }.sorted()
    check("H14", "official ChatGPT and Claude exports (conversations.json): only the person's own turns become records, each with its own time and the conversation's title — ChatGPT 4 turns (system, tool, assistant and profile-context nodes are not turns), Claude 1 (a turn with no readable time is skipped and counted); no message text of anyone and no raw conversation ID is stored; they are AI records marked as snapshots",
          gpt.format == "chatgpt" && gpt.rows.count == 4 && gpt.skipped == 1 && gptDates == [11, 11, 13, 150] && Set(gpt.rows.map { $0["title"] as? String ?? "" }) == ["Harborline 가격 협상 준비", "Atlas 온보딩"] &&
          cl.format == "claude" && cl.rows.count == 1 && cl.skipped == 1 && (cl.rows[0]["title"] as? String) == "Harborline 계약 조항 질문" && saved3.imported == 4 && saved4.imported == 1 &&
          !chatText.contains("SECRET") && !chatText.contains("conv-") && chatText.contains("\"kind\":\"ai\"") && chatText.contains("\"via\":\"chatgpt\"") && chatText.contains("\"via\":\"claude\""),
          "\(gpt.format) \(gpt.rows.count)/\(gpt.skipped) \(gptDates) \(cl.rows.count)/\(cl.skipped)")
    let jsonlURL = temp.appendingPathComponent("export/chats.jsonl")
    write(jsonlURL, [row("j1", "Atlas 디자인 방향", ago(8), ["Atlas"], "export"), "garbage", json(["id": "j2", "title": "Northfield 메모", "date": Dates.day(real.addingTimeInterval(-9 * 86400)), "topics": ["Northfield"], "source": "export", "locator": "", "kind": "mail"])].joined(separator: "\n"))
    let jl = Importer.parse(jsonlURL, jsonlKind: .ai)
    let saved5 = Importer.save(jl, name: "chats", places: places, now: importTime)
    let wrong = Importer.save(Importer.parse(temp.appendingPathComponent("export/claude/missing.json")), name: "x", places: places)
    write(temp.appendingPathComponent("export/other.json"), "{\"hello\": 1}")
    let other = Importer.parse(temp.appendingPathComponent("export/other.json"))
    let importNames = (try? fm.contentsOfDirectory(atPath: places.imports.path)) ?? []
    check("H15", "imports are atomic and separate: each is a NEW file in horizon-v1/imports (0600 in a 0700 folder) written under a temporary name and linked into place, so no half-written or temporary file is left and nothing existing is replaced; preindex, ai.jsonl and mail.jsonl are byte-for-byte unchanged; a normalised .jsonl takes the chosen kind unless a row names its own; a missing file or a JSON that is not an export writes nothing",
          jl.rows.count == 2 && jl.skipped == 1 && (jl.rows[0]["kind"] as? String) == "ai" && (jl.rows[1]["kind"] as? String) == "mail" && saved5.imported == 2 && wrong.file == nil && wrong.problem != nil && other.problem != nil &&
          importNames.count == 5 && importNames.allSatisfy { $0.hasPrefix("import-") && $0.hasSuffix(".jsonl") } && mode(saved1.file) == 0o600 && mode(places.imports) == 0o700 &&
          savedText.contains("\"importedAt\":\"" + Dates.isoString(importTime) + "\"") && fm.contents(atPath: places.ai.path) == aiBefore && fm.contents(atPath: places.mail.path) == mailBefore && fm.contents(atPath: places.preindex.path) == filesBefore,
          importNames.joined(separator: ", "))

    // ── everything together ──
    let s5 = Snapshot.read(places, now: real), t5 = Analysis.topics(s5.evidence, window: h3, enabled: all)
    let hb5 = t5.first { $0.key == "harborline" }, atlas = t5.first { $0.key == "atlas" }
    let turns = hb5?.items.first { $0.evidence.via == "chatgpt" }
    let c5 = s5.coverage(for: .imports, window: h3, enabled: all).summary
    check("H16", "imported records join the evidence as snapshots with their own record dates: Harborline now has 7 lines (2 files, 3 AI, 2 mail) for 8 records — the two ChatGPT turns of one conversation on one day are one line marked ×2, and the 150-day-old turn stays outside 3 months; Atlas, files-only before, is multi-type; imports say they are snapshots that do not follow later changes",
          names(t5) == "harborline:file+ai+mail:7 | atlas:file+ai+mail:7 | northfield:mail:2" && hb5?.records == 8 && turns?.count == 2 && turns?.direct == true && turns?.evidence.provenance == "Snapshot" && turns?.evidence.isSnapshot == true &&
          hb5?.direct == 6 && atlas?.direct == 5 && c5.hasPrefix("10 in this period (11 total)") && c5.contains("11 snapshot records (as they were when imported; later changes are not reflected)") && c5.contains("Last import: " + Dates.minute(importTime)) && c5.contains(" · 5 files"),
          names(t5) + " // " + c5)
    let mailOff: Set<SourceKind> = [.files, .ai, .imports], aiOff: Set<SourceKind> = [.files, .mail, .imports]
    let tMailOff = Analysis.topics(s5.evidence, window: h3, enabled: mailOff), cOff = s5.coverage(for: .imports, window: h3, enabled: mailOff)
    check("H17", "a switch governs its type wherever the record came from: with Mail off, imported mail (Gmail, Apple Mail, a mail row in a .jsonl) is out too — Harborline and Atlas keep only files and AI, Northfield (mail only) disappears, and imports say 5 records were left out because their type is off; with AI chats off the imported ChatGPT and Claude turns are out; with Imports off the view is the feeds alone",
          names(tMailOff) == "harborline:file+ai:5 | atlas:file+ai:4" && cOff.inWindow == 5 && cOff.typeOff == 5 && cOff.summary.contains("5 left out because their type is off") &&
          names(Analysis.topics(s5.evidence, window: h3, enabled: aiOff)) == "atlas:file+mail:5 | harborline:file+mail:4 | northfield:mail:2" &&
          names(Analysis.topics(s5.evidence, window: h3, enabled: [.files, .ai, .mail])) == names(t3), names(tMailOff) + " // " + names(Analysis.topics(s5.evidence, window: h3, enabled: aiOff)) + " // " + cOff.summary)

    // ── the short handoff (what the simple screen shows and copies) ──
    let cov5 = SourceKind.allCases.map { s5.coverage(for: $0, window: h3, enabled: all) }
    let text = hb5.map { Export.simple(task: "", topic: $0, window: h3, coverage: cov5) } ?? ""
    let citeRx = #"^\[[FAM]\d\] \d{4}-\d{2}-\d{2} · (File|AI|Mail) · \S"#
    func citeLines(_ t: String) -> [String] { t.split(separator: "\n").filter { $0.range(of: citeRx, options: .regularExpression) != nil }.map(String.init) }
    func bareLines(_ t: String) -> [String] { t.split(separator: "\n").filter { $0.range(of: #"^\d{4}-\d{2}-\d{2} · (File|AI|Mail) · \S"#, options: .regularExpression) != nil }.map(String.init) }
    let cites = citeLines(text)
    check("H18", "the handoff is deliberately short: six citations for Harborline, two per record type ([F1] [F2] [A1] [A2] [M1] [M2], direct mentions first, then newest), each a date, the record type and a title, with (inferred) on the one linked only by its tag; one header line, one signal line that says titles are not completed outcomes, the omitted count, and one line of caution about the sources (stale and partial feeds, snapshots)",
          cites.count == 6 && cites.map { String($0.prefix(4)) } == ["[F1]", "[F2]", "[A1]", "[A2]", "[M1]", "[M2]"] && cites[0].hasSuffix(" · File · Harborline Q3 quote.xlsx") && cites[1].hasSuffix(" · File · plan.pdf (inferred)") &&
          cites[2].hasSuffix(" · AI · Harborline 가격 협상 준비") && cites[3].hasSuffix(" · AI · Harborline 계약 조항 질문") && cites[4].hasSuffix(" · Mail · Harborline 견적 회신") && cites[5].hasSuffix(" · Mail · RE: Harborline quote") &&
          text.hasPrefix("Topic: Harborline · " + h3.dayLabel + "\nSignals: 7 records (File 2 · AI 3 · Mail 2) · 6 direct / 1 inferred — title counts are signals, not proof of completed work\n") && text.contains("\n1 more not shown\n") &&
          text.hasSuffix("\nSource caution: AI chats: stale, partial · Mail: partial · Imports: snapshot\n") && text.split(separator: "\n").count == 10, text)
    let task = "Harborline 견적 회신 이어서 쓰기 bob.kim@example.com /Users/mina/secret/plan.pdf conv 3f2a9c1e-1111-2222-3333-444455556666"
    let withTask = hb5.map { Export.simple(task: task, topic: $0, window: h3, coverage: cov5) } ?? ""
    let taskCites = citeLines(withTask)
    check("H19", "the person's task leads the handoff with its identifiers redacted, and steers which lines are cited (titles sharing a word with the task first: the AI chat about 견적 now comes first among AI); nothing private leaves: no absolute path, locator, e-mail address, link, conversation or message ID, no body text, nothing of another topic; 11 lines at most",
          withTask.hasPrefix("Task: Harborline 견적 회신 이어서 쓰기 [email] [path] conv [ID]\nTopic: Harborline · ") && taskCites.count == 6 && taskCites[2].hasSuffix(" · AI · Harborline 견적 검토") && taskCites[4].hasSuffix(" · Mail · Harborline 견적 회신") &&
          [text, withTask].allSatisfy { t in !t.contains("/Users") && !t.contains("ref:") && !t.contains("참조") && !t.lowercased().contains("locator") && !t.contains("@") && !t.contains("://") && !t.contains("export:") && !t.contains("SECRET") && !t.contains("Atlas") && !t.contains("Northfield") && !t.contains("3f2a9c1e") } &&
          withTask.split(separator: "\n").count == 11, withTask)
    let hostileTitle = "FW: bob.kim@example.com /Users/mina/secret/plan.pdf https://mail.google.com/mail/u/0/#inbox/abc Message-ID: <q1@mail.example> 3f2a9c1e-1111-2222-3333-444455556666 Harborline_Q3_quote_2026.xlsx"
    var nastyItems: [TopicItem] = []
    for i in 0..<9 {
        let isFile = i < 5
        let title: String = i == 0 ? hostileTitle : "문서 \(i)"
        let e = ev(real.addingTimeInterval(Double(-i) * 86400), origin: isFile ? .files : .mail, type: isFile ? .file : .mail, title: title)
        nastyItems.append(TopicItem(evidence: e, direct: i % 2 == 0, count: 1))
    }
    let nasty = TopicSummary(key: "x", display: "Harborline <owner@example.com>", items: nastyItems, types: [.file, .mail])
    let nastyText = Export.simple(task: "", topic: nasty, window: h3, coverage: [])
    let nastyCites = nastyText.split(separator: "\n").filter { $0.hasPrefix("[") }
    check("H20", "redaction and limits hold for hostile titles: an address, an absolute path, a link, a Message-ID header and a UUID in a title or topic name are replaced, an ordinary file name is kept; with five files and four mails and no AI the six citations are filled from what there is (never more than six) and three are counted as omitted",
          !nastyText.contains("@") && !nastyText.contains("/Users") && !nastyText.contains("://") && !nastyText.contains("3f2a9c1e") && !nastyText.contains("q1") && nastyText.contains("Harborline_Q3_quote_2026.xlsx") &&
          nastyText.contains("[email]") && nastyText.contains("[path]") && nastyText.contains("[link]") && nastyCites.count == 6 && nastyCites.filter { $0.hasPrefix("[F") }.count + nastyCites.filter { $0.hasPrefix("[M") }.count == 6 &&
          nastyCites.filter { $0.hasPrefix("[A") }.isEmpty && nastyText.contains("\n3 more not shown"), nastyText)
    /// The handoff never states an outcome: "completed" appears only inside the caveat, and no word claims work was done.
    func claimsNoOutcome(_ t: String) -> Bool {
        let low = t.lowercased()
        let caveats = low.components(separatedBy: "not proof of completed work").count - 1
        return low.components(separatedBy: "complete").count - 1 == caveats && ["finished", "decided", "resolved", "is done", "was done", "완료했", "끝냈", "결정했"].allSatisfy { !low.contains($0) }
    }
    func tinyTopic(_ n: Int) -> TopicSummary {
        TopicSummary(key: "atlas", display: "Atlas", items: (0..<n).map { TopicItem(evidence: ev(real.addingTimeInterval(Double(-$0) * 86400), origin: .files, type: .file, title: "Atlas 문서 \($0)"), direct: true, count: 1) }, types: [.file])
    }
    let tiny1 = Export.simple(task: "", topic: tinyTopic(1), window: h3, coverage: []), tiny1Flagged = Export.simple(task: "Atlas 이어서", topic: tinyTopic(1), window: h3, coverage: cov5)
    let tiny3 = Export.simple(task: "", topic: tinyTopic(3), window: h3, coverage: cov5), four = Export.simple(task: "", topic: tinyTopic(4), window: h3, coverage: cov5)
    check("H36", "a tiny set gets no preamble longer than its list: with 1 to 3 lines of evidence the handoff is a single short header line (the topic unless the task names it, the period, the signal caveat, and any caution about the sources) plus the bare dated lines — 2 lines for one record, 4 for three; the task adds one line; from four records on it uses the two header lines, and never says anything was completed",
          tiny1.split(separator: "\n").count == 2 && tiny1 == "Topic: Atlas · " + h3.shortLabel + " · titles are signals, not proof of completed work\n" + Dates.day(real) + " · File · Atlas 문서 0\n" &&
          tiny1Flagged.split(separator: "\n").count == 3 && tiny1Flagged == "Task: Atlas 이어서\n" + h3.shortLabel + " · titles are signals, not proof of completed work · Source caution: AI chats: stale, partial · Mail: partial · Imports: snapshot\n" + Dates.day(real) + " · File · Atlas 문서 0\n" &&
          tiny3.split(separator: "\n").count == 4 && four.split(separator: "\n").count == 7 && four.hasPrefix("Topic: Atlas · " + h3.dayLabel + "\nSignals: 4 records (File 4) · 4 direct / 0 inferred — title counts are signals, not proof of completed work\n[F1] ") && citeLines(four).count == 4 && citeLines(tiny3).isEmpty &&
          [tiny1, tiny3, four, text].allSatisfy { t in claimsNoOutcome(t) }, tiny1 + "---" + tiny1Flagged + "---" + four)

    // ── round 1 (0.5.1): the 1–3 row packet costs little more than its list ──
    /// The 0.5.0 text for a small topic, rebuilt here only to measure against.
    func oldSmall(task t: String, _ topic: TopicSummary, _ w: HorizonWindow, _ cov: [SourceCoverage]) -> String {
        var l = t.isEmpty ? [String]() : ["Task: " + Redact.label(t, max: 140)]
        l.append("Topic: \(Redact.label(topic.display, max: 60)) · \(w.dayLabel) · \(plural(topic.items.count, "record")) — titles are signals, not proof of completed work" + (Export.caption(cov).map { " · Source caution: " + Redact.label($0, max: 120) } ?? ""))
        let words = Search.tokens(Redact.label(t, max: 140)).filter { !Set(topic.key.split(separator: " ").map(String.init)).contains($0) }
        func fits(_ it: TopicItem) -> Int { it.evidence.derivedTitle ? 0 : words.filter { Topic.named(in: it.evidence.title, key: $0) }.count }
        var n: [RecordType: Int] = [:]
        for ty in RecordType.allCases {
            for it in topic.items.filter({ $0.evidence.type == ty }).sorted(by: { (fits($0), $0.direct ? 1 : 0, $0.evidence.date) > (fits($1), $1.direct ? 1 : 0, $1.evidence.date) }).prefix(Export.maxCitations) {
                n[ty, default: 0] += 1
                l.append("[" + ty.letter + String(n[ty]!) + "] " + Dates.day(it.evidence.date, w.calendar) + " · " + ty.label + " · " + Redact.label(it.evidence.title) + (it.direct ? "" : " (inferred)"))
            }
        }
        return l.joined(separator: "\n") + "\n"
    }
    func pieces(_ t: String) -> Int { (try? NSRegularExpression(pattern: #"\p{L}+|\d|[^\s\p{L}\d]"#))?.numberOfMatches(in: t, range: NSRange(t.startIndex..., in: t)) ?? 0 }
    let proofTopic = TopicSummary(key: "bellwater", display: "Bellwater", items: [
        TopicItem(evidence: ev(real.addingTimeInterval(-1 * 86400), origin: .files, type: .file, title: "Bellwater proof request for bob@example.com /Users/mina/proofs/final.pdf"), direct: true, count: 1),
        TopicItem(evidence: ev(real.addingTimeInterval(-2 * 86400), origin: .ai, type: .ai, title: "layout handover checklist"), direct: false, count: 1)], types: [.file, .ai])
    let proofTask = "For Bellwater, what does the proof request specify? " + String(repeating: "and the delivery window ", count: 3) + "cc dana@example.com"
    let smallNew = Export.simple(task: proofTask, topic: proofTopic, window: h3, coverage: cov5), smallOld = oldSmall(task: proofTask, proofTopic, h3, cov5)
    let smallLines = smallNew.split(separator: "\n").map(String.init)
    let unnamed = Export.simple(task: "what does the proof request specify?", topic: proofTopic, window: h3, coverage: []), hiddenName = Export.simple(task: "see /Users/mina/bellwater/proof.pdf", topic: proofTopic, window: h3, coverage: [])
    let smallA = Calendar.current.startOfDay(for: real.addingTimeInterval(-26 * 86400)), smallB = Calendar.current.startOfDay(for: real.addingTimeInterval(-17 * 86400))
    let customSmall = Export.simple(task: "Bellwater proof", topic: proofTopic, window: HorizonWindow(customStart: smallA, customEnd: smallB, now: real), coverage: [])
    // what Horizon adds around the task and the rows themselves (which are the same in both)
    let given = pieces(smallLines.first ?? "") + pieces(bareLines(smallNew).joined(separator: "\n"))
    let overheadNew = pieces(smallNew) - given, overheadOld = pieces(smallOld) - given
    let plainNew = pieces(Export.simple(task: proofTask, topic: proofTopic, window: h3, coverage: [])) - given, plainOld = pieces(oldSmall(task: proofTask, proofTopic, h3, [])) - given
    check("H48", "round 1 — a 1–3 row packet is close to the size of its list: the header keeps the period (\"3 months to <last day>\", or the two days of a custom period), the caveat that titles are not proof, and the caution about the sources; each line keeps its date, record type, redacted title and the (inferred) mark; the whole task stays (redacted, as before); what goes is what the list already says — the count, the [F1] handles, and the topic's name when the task names it. Measured on a two-row packet: what Horizon adds around the task and the two rows is at most half of what 0.5.0 added, and with a caution about the sources (which stays in full) still 20 pieces smaller",
          smallLines.count == 4 && smallLines[0] == "Task: " + Redact.label(proofTask, max: 140) && smallLines[0].contains("delivery window and the delivery window") && smallLines[0].hasSuffix("cc [email]") &&
          smallLines[1] == h3.shortLabel + " · titles are signals, not proof of completed work · Source caution: AI chats: stale, partial · Mail: partial · Imports: snapshot" && h3.shortLabel == "3 months to " + Dates.day(real) &&
          smallLines[2] == Dates.day(real.addingTimeInterval(-86400)) + " · File · Bellwater proof request for [email] [path]" && smallLines[3] == Dates.day(real.addingTimeInterval(-2 * 86400)) + " · AI · layout handover checklist (inferred)" &&
          !smallNew.contains("[F1]") && !smallNew.contains("[A1]") && !smallNew.contains("@") && !smallNew.contains("/Users") && claimsNoOutcome(smallNew) && smallNew.components(separatedBy: "not proof of completed work").count == 2 &&
          bareLines(smallNew) == citeLines(smallOld).map { String($0.dropFirst(5)) } && plainNew * 2 <= plainOld && plainNew > 0 && overheadNew <= overheadOld - 20 && overheadNew - plainNew == overheadOld - plainOld && smallNew.count < smallOld.count - 40 &&
          customSmall.hasPrefix("Task: Bellwater proof\n" + Dates.day(smallA) + " – " + Dates.day(smallB) + " (both days included) · titles are signals, not proof of completed work\n"),
          "added around the task and rows: old \(plainOld) → new \(plainNew) pieces; with the caution: old \(overheadOld) → new \(overheadNew)\n" + smallNew + "---\n" + smallOld)
    let fourTopic = TopicSummary(key: "bellwater", display: "Bellwater", items: proofTopic.items + [TopicItem(evidence: ev(real.addingTimeInterval(-3 * 86400), origin: .mail, type: .mail, title: "Bellwater proof reply"), direct: true, count: 1), TopicItem(evidence: ev(real.addingTimeInterval(-4 * 86400), origin: .mail, type: .mail, title: "Bellwater schedule"), direct: true, count: 1)], types: [.file, .ai, .mail])
    let fourText = Export.simple(task: "Bellwater proof", topic: fourTopic, window: h3, coverage: [])
    check("H49", "round 1 leaves everything else alone: the topic's name stays in the header when there is no task, when the task does not name it, and when the name occurs only inside a part of the task that is redacted (a path); a packet of four or more rows keeps its two header lines, its counts and its [F1] handles exactly as before",
          unnamed.hasPrefix("Task: what does the proof request specify?\nTopic: Bellwater · " + h3.shortLabel + " · titles are signals, not proof of completed work\n") &&
          hiddenName.hasPrefix("Task: see [path]\nTopic: Bellwater · " + h3.shortLabel + " · ") && !hiddenName.lowercased().contains("/users") &&
          Export.simple(task: "", topic: proofTopic, window: h3, coverage: []).hasPrefix("Topic: Bellwater · " + h3.shortLabel + " · titles are signals, not proof of completed work\n" + Dates.day(real.addingTimeInterval(-86400)) + " · File · ") &&
          fourText.hasPrefix("Task: Bellwater proof\nTopic: Bellwater · " + h3.dayLabel + "\nSignals: 4 records (File 1 · AI 1 · Mail 2) · 3 direct / 1 inferred — title counts are signals, not proof of completed work\n[F1] ") && citeLines(fourText).count == 4 && bareLines(fourText).isEmpty,
          unnamed + "---" + hiddenName + "---" + fourText)

    // a small packet whose task asks "when" keeps the 0.5.0 text (release gate: the short form drew a made-up time from a small model)
    let meet = TopicSummary(key: "bellwater", display: "Bellwater", items: [
        TopicItem(evidence: ev(real.addingTimeInterval(-1 * 86400), origin: .mail, type: .mail, title: "Bellwater 회의 안건"), direct: true, count: 1),
        TopicItem(evidence: ev(real.addingTimeInterval(-3 * 86400), origin: .files, type: .file, title: "Bellwater meeting notes for bob@example.com"), direct: true, count: 1),
        TopicItem(evidence: ev(real.addingTimeInterval(-2 * 86400), origin: .ai, type: .ai, title: "layout handover checklist"), direct: false, count: 1)], types: [.file, .ai, .mail])
    let whenTasks = ["회의가 언제지?", "Bellwater 회의 날짜 알려줘", "며칠에 하기로 했지", "회의 시간이 몇 시야", "When is the Bellwater meeting?", "What date was agreed for Bellwater?", "what time does it start"]
    let whenTexts = whenTasks.map { Export.simple(task: $0, topic: meet, window: h3, coverage: cov5) }
    check("H57", "a small packet whose task asks when keeps the 0.5.0 text exactly: for 1–3 rows and a task with when / date / time or 언제 / 며칠 / 날짜 / 시간 the handoff is byte for byte what 0.5.0 wrote — \"Topic: <name> · <full period> · N records — titles are signals, not proof of completed work\", the caution about the sources, and numbered dated lines — with and without a caution, in a preset and in a custom period",
          zip(whenTasks, whenTexts).allSatisfy { q, t in t == oldSmall(task: q, meet, h3, cov5) && Array(t.utf8) == Array(oldSmall(task: q, meet, h3, cov5).utf8) } &&
          whenTexts[0] == "Task: 회의가 언제지?\nTopic: Bellwater · " + h3.dayLabel + " · 3 records — titles are signals, not proof of completed work · Source caution: AI chats: stale, partial · Mail: partial · Imports: snapshot\n[F1] " + Dates.day(real.addingTimeInterval(-3 * 86400)) + " · File · Bellwater meeting notes for [email]\n[A1] " + Dates.day(real.addingTimeInterval(-2 * 86400)) + " · AI · layout handover checklist (inferred)\n[M1] " + Dates.day(real.addingTimeInterval(-86400)) + " · Mail · Bellwater 회의 안건\n" &&
          Export.simple(task: "When is the Bellwater meeting?", topic: meet, window: HorizonWindow(customStart: smallA, customEnd: smallB, now: real), coverage: []) == oldSmall(task: "When is the Bellwater meeting?", meet, HorizonWindow(customStart: smallA, customEnd: smallB, now: real), []) &&
          Export.simple(task: "언제였지", topic: tinyTopic(1), window: h3, coverage: []) == oldSmall(task: "언제였지", tinyTopic(1), h3, []) && whenTasks.allSatisfy { Export.asksWhen($0) },
          whenTexts[0] + "---" + oldSmall(task: whenTasks[0], meet, h3, cov5))
    let notWhen = ["회의 안건 정리해줘", "What does the Bellwater meeting cover?", "Bellwater timeline and update", "sometimes dated notes", "Bellwater 회의", ""]
    let notWhenTexts = notWhen.map { Export.simple(task: $0, topic: meet, window: h3, coverage: cov5) }
    let fourWhen = Export.simple(task: "When is the Bellwater proof due?", topic: fourTopic, window: h3, coverage: [])
    check("H58", "only that case: a small packet with any other task — or none — stays in the short form (no count, no [F1] handles, the short period), words that merely contain \"time\" or \"date\" (timeline, sometimes, update, dated) do not count, and a packet of four or more rows is written as always whatever the task asks",
          zip(notWhen, notWhenTexts).allSatisfy { q, t in !Export.asksWhen(q) && t != oldSmall(task: q, meet, h3, cov5) && !t.contains("[F1]") && !t.contains("3 records") && t.contains(h3.shortLabel + " · titles are signals, not proof of completed work · Source caution: ") && bareLines(t).count == 3 } &&
          notWhenTexts[1].hasPrefix("Task: What does the Bellwater meeting cover?\n" + h3.shortLabel + " · ") && notWhenTexts[5].hasPrefix("Topic: Bellwater · " + h3.shortLabel + " · ") &&
          fourWhen.hasPrefix("Task: When is the Bellwater proof due?\nTopic: Bellwater · " + h3.dayLabel + "\nSignals: 4 records (File 1 · AI 1 · Mail 2) · 3 direct / 1 inferred — title counts are signals, not proof of completed work\n[F1] ") && citeLines(fourWhen).count == 4,
          notWhenTexts[0] + "---" + fourWhen)

    // ── round 2 (0.5.1): which six lines — chains of the same thing shown once, older one-off records not buried ──
    /// The 0.5.0 choice, kept here only to compare with.
    func oldCitations(_ topic: TopicSummary, prefer: [String] = []) -> [String] {
        let nameWords = Set(topic.key.split(separator: " ").map(String.init)), words = prefer.filter { !nameWords.contains($0) }
        func fits(_ it: TopicItem) -> Int { it.evidence.derivedTitle ? 0 : words.filter { Topic.named(in: it.evidence.title, key: $0) }.count }
        func ranked(_ list: [TopicItem]) -> [TopicItem] { list.sorted { (fits($0), $0.direct ? 1 : 0, $0.evidence.date) > (fits($1), $1.direct ? 1 : 0, $1.evidence.date) } }
        var chosen: [TopicItem] = [], rest: [TopicItem] = []
        for t in topic.types { let r = ranked(topic.items.filter { $0.evidence.type == t }); chosen += r.prefix(2); rest += r.dropFirst(2) }
        chosen += ranked(rest).prefix(max(0, Export.maxCitations - chosen.count))
        chosen = Array(chosen.prefix(Export.maxCitations))
        var n: [RecordType: Int] = [:], out: [String] = []
        for t in RecordType.allCases { for it in ranked(chosen.filter { $0.evidence.type == t }) { n[t, default: 0] += 1; out.append("[" + t.letter + String(n[t]!) + "] " + it.evidence.id) } }
        return out
    }
    func newCitations(_ topic: TopicSummary, prefer: [String] = []) -> [String] { Export.citations(topic, prefer: prefer).map { $0.label + " " + $0.item.evidence.id } }
    func made(_ key: String, _ rows: [(String, Double, RecordType)]) -> TopicSummary {
        let items = rows.map { r in TopicItem(evidence: ev(real.addingTimeInterval(-r.1 * 86400), origin: r.2.governing, type: r.2, title: r.0), direct: true, count: 1) }.sorted { $0.evidence.date > $1.evidence.date }
        return TopicSummary(key: key.lowercased(), display: key, items: items, types: RecordType.allCases.filter { t in items.contains { $0.evidence.type == t } })
    }
    func shown(_ topic: TopicSummary, task t: String = "") -> [String] { Export.citations(topic, prefer: Search.tokens(t), asking: Standing.asked(t)).map { $0.label + " " + $0.item.evidence.title } }
    let lumen = made("Lumen", [("Lumen quote v1.xlsx", 30, .file), ("Lumen quote v2.xlsx", 20, .file), ("Lumen quote v3.xlsx", 2, .file), ("Lumen quote v3 (2).xlsx", 1, .file), ("Lumen site survey findings.pdf", 50, .file),
                               ("Lumen pricing notes / revision 1", 25, .ai), ("Lumen pricing notes / revision 2", 9, .ai), ("Lumen 견적서 수정 2", 8, .ai), ("Lumen 견적서 2차 수정본", 7, .ai), ("Lumen 견적서 수정 3", 4, .ai), ("Lumen kickoff summary", 60, .ai),
                               ("Lumen delivery slots", 12, .mail), ("Lumen delivery slots", 11, .mail), ("Re: Lumen delivery slots", 10, .mail), ("RE: Re: Lumen delivery slots", 6, .mail), ("Fwd: Lumen delivery slots", 3, .mail), ("Lumen warehouse access rules", 40, .mail)])
    let lumenShown = shown(lumen), lumenText = Export.simple(task: "", topic: lumen, window: h3, coverage: [])
    let oneChain = made("Orrin", (1...8).map { ("Orrin layout draft \($0).sketch", Double(40 - $0 * 4), RecordType.file) })
    check("H50", "round 2 — the six lines are six different things: numbered revisions, copies, replies and forwards of one title (English and Korean marks) are one chain shown by its newest member; each record type keeps its best line plus one more, and for that second line an older one-off record comes before another recurring one (the survey from 50 days ago, the kickoff from 60, the access rules from 40); the task still decides first (a word of the task, also as a plural, puts its line on top); and when a topic is one chain only, the places are filled with its earlier versions, the first one included",
          lumenShown == ["[F1] Lumen quote v3 (2).xlsx", "[F2] Lumen site survey findings.pdf", "[A1] Lumen 견적서 수정 3", "[A2] Lumen kickoff summary", "[M1] Fwd: Lumen delivery slots", "[M2] Lumen warehouse access rules"] &&
          Set(Export.citations(lumen).map { Export.stem($0.item.evidence.title) }).count == 6 && lumenText.contains("\n11 more not shown\n") && lumenText.contains("Signals: 17 records (File 5 · AI 6 · Mail 6)") &&
          shown(lumen, task: "Lumen pricing")[2] == "[A1] Lumen pricing notes / revision 2" && shown(lumen, task: "Lumen pricing")[3] == "[A2] Lumen kickoff summary" && shown(lumen, task: "what did the survey finding say")[0] == "[F1] Lumen site survey findings.pdf" &&
          shown(lumen, task: "delivery slot")[4] == "[M1] Fwd: Lumen delivery slots" && Export.mentions("48 cartons; pickup Thursday", word: "carton") && Export.mentions("policy update", word: "policies") && !Export.mentions("cartoons", word: "carton") &&
          shown(oneChain) == ["[F1] Orrin layout draft 8.sketch", "[F2] Orrin layout draft 7.sketch", "[F3] Orrin layout draft 6.sketch", "[F4] Orrin layout draft 5.sketch", "[F5] Orrin layout draft 4.sketch", "[F6] Orrin layout draft 1.sketch"] &&
          Export.stem("RE: Fwd: 답장: Lumen 견적서 (2).xlsx") == "lumen 견적서.xlsx" && Export.stem("Plan - v2.1 (copy).pdf") == Export.stem("Plan.pdf") && Export.stem("Budget copy 2.xlsx") == "budget.xlsx" && Export.stem("계약서 개정 3판") == "계약서",
          lumenShown.joined(separator: " | ") + " // " + shown(oneChain).joined(separator: " | ") + " // " + [Export.stem("RE: Fwd: 답장: Lumen 견적서 (2).xlsx"), Export.stem("Plan - v2.1 (copy).pdf"), Export.stem("Budget copy 2.xlsx"), Export.stem("계약서 개정 3판")].joined(separator: " | "))
    let plain = made("Vesper", [("Vesper Phase 2 plan", 3, .file), ("Vesper Phase 3 plan", 5, .file), ("Vesper Q3 report", 9, .file), ("Vesper Q4 report", 12, .file), ("Vesper 2차 미팅 메모", 4, .ai), ("Vesper 3차 미팅 메모", 6, .ai), ("Vesper cap 17 units", 30, .ai),
                                ("Vesper cap 12 units", 8, .ai), ("Vesper design review", 2, .mail), ("Vesper design revision", 7, .mail), ("Vesper hard copy", 10, .mail), ("Vesper Phase 2 plan", 11, .mail)])
    let sameAsBefore = [(hb5!, ""), (hb5!, task), (nasty, ""), (plain, ""), (plain, "Vesper report and cap"), (tinyTopic(3), ""), (proofTopic, proofTask)].allSatisfy { t, q in newCitations(t, prefer: Search.tokens(Redact.label(q, max: 140))) == oldCitations(t, prefer: Search.tokens(Redact.label(q, max: 140))) }
    check("H51", "round 2 changes nothing where nothing repeats: for topics whose titles are all different the choice is exactly the 0.5.0 one, with and without a task (the rule for tasks that ask where something stands is round 3, tested below); a bare number is not a revision mark (Phase 2 / Phase 3, Q3 / Q4, 2차 미팅 / 3차 미팅, \"cap 17 units\" / \"cap 12 units\" stay separate lines), nor is \"review\", \"revision\" without a number, or \"hard copy\"; a title that is only a mark keeps itself; the same title as a file and as a mail is two lines, one per type; and no topic name, value or question is known to the code (a made-up topic behaves the same)",
          sameAsBefore && Set(plain.items.map { Export.stem($0.evidence.title) }).count == 11 && Export.stem("Vesper Phase 2 plan") != Export.stem("Vesper Phase 3 plan") && Export.stem("Vesper 2차 미팅 메모") == "vesper 2차 미팅 메모" &&
          Export.stem("Revision 3") == "revision 3" && Export.stem("v2") == "v2" && Export.stem("Design review") == "design review" && Export.stem("Budget review 2026") == "budget review 2026" && Export.stem("Vesper hard copy") == "vesper hard copy" &&
          shown(plain).contains("[F1] Vesper Phase 2 plan") && shown(plain).contains("[M2] Vesper design revision") && shown(plain).filter { $0.hasSuffix("Vesper Phase 2 plan") }.count == 1 &&
          shown(made("Vesper", [("Vesper Phase 2 plan", 3, .file), ("Vesper Phase 2 plan", 11, .mail)])) == ["[F1] Vesper Phase 2 plan", "[M1] Vesper Phase 2 plan"],
          "same=\(sameAsBefore) stems=\(Set(plain.items.map { Export.stem($0.evidence.title) }).count) " + shown(plain).joined(separator: " | "))

    // ── round 3 (0.5.1): when the task asks where something stands — decisions, limits, and what is pending or corrected ──
    let marrow = made("Marrow", [("Marrow approved cap 17 units per order", 40, .mail), ("Marrow correction: cap lowered to 12 units", 6, .mail), ("Marrow weekly sync", 12, .mail), ("Re: Marrow weekly sync", 9, .mail), ("Re: Marrow weekly sync", 5, .mail),
                                 ("RE: Re: Marrow weekly sync", 1, .mail), ("Marrow parking reminder", 3, .mail), ("Marrow lunch order", 2, .mail),
                                 ("Marrow rollout plan v1.pdf", 30, .file), ("Marrow rollout plan v2.pdf", 20, .file), ("Marrow rollout plan v3.pdf", 10, .file), ("Marrow rollout plan v4.pdf", 2, .file), ("Marrow pricing sheet.xlsx", 5, .file),
                                 ("Marrow contract draft sent for signature - not signed", 9, .file), ("Marrow budget 2026 summary with 14 line items and 3 totals", 4, .file),
                                 ("Marrow brainstorm notes", 1, .ai), ("Marrow naming ideas", 3, .ai), ("Marrow retro summary", 8, .ai)])
    let askOpen = "How many are permitted now, and is anything still unsettled?", askNamed = "Was the Marrow contract signed, and what is the cap now?"
    let marrowOpen = shown(marrow, task: askOpen), marrowNamed = shown(marrow, task: askNamed)
    let marrowText = Export.simple(task: askOpen, topic: marrow, window: h3, coverage: [])
    let marrowLines = marrowText.split(separator: "\n").map(String.init)
    func at(_ list: [String], _ title: String) -> Int { list.firstIndex { $0.hasSuffix(title) } ?? -1 }
    let sora = made("Sora", [("Sora 한도 예외 승인: 상한 17개", 40, .mail), ("Sora 정정: 상한 12개로 변경", 5, .mail), ("Sora 주간 회의록 수정 1", 20, .mail), ("Sora 주간 회의록 수정 2", 13, .mail), ("Sora 주간 회의록 수정 3", 2, .mail), ("Sora 점심 메뉴", 3, .mail),
                             ("Sora 계약서 초안 검토 중 - 서명 미확정", 9, .file), ("Sora 일정표.xlsx", 1, .file), ("Sora 견적 14건 합계 3종", 4, .file)])
    let soraShown = shown(sora, task: "현재 Sora 한도가 얼마로 확정됐나요?")
    func m(_ t: String) -> String { let x = Standing.marks(title: t); return ["-", "d", "D"][x.decision] + ["-", "p", "P"][x.pending] }       // capital: in so many words; small: weakly
    check("H52", "round 3 — when the task asks where something stands (what is permitted, signed, final, current; 확정, 한도, 현재), titles that speak of a decision or limit and titles that speak of something pending or corrected are shown together, in English and in Korean: the older approval and the newer correction both appear, the unsigned draft appears, and they come before other candidates for a type's second line — without any word of the task matching them; within a type the lines run newest first, so the correction stands above the approval it follows; each type still keeps its best line (the newest one here); the words of the task still decide first; and nothing is added to a line or concluded in the header",
          marrowOpen == ["[F1] Marrow rollout plan v4.pdf", "[F2] Marrow contract draft sent for signature - not signed", "[A1] Marrow brainstorm notes", "[M1] RE: Re: Marrow weekly sync", "[M2] Marrow correction: cap lowered to 12 units", "[M3] Marrow approved cap 17 units per order"] &&
          at(marrowOpen, "cap lowered to 12 units") < at(marrowOpen, "approved cap 17 units per order") && at(marrowOpen, "14 line items and 3 totals") == -1 &&
          marrowNamed == ["[F1] Marrow budget 2026 summary with 14 line items and 3 totals", "[F2] Marrow contract draft sent for signature - not signed", "[A1] Marrow brainstorm notes", "[A2] Marrow naming ideas", "[M1] Marrow correction: cap lowered to 12 units", "[M2] Marrow approved cap 17 units per order"] &&
          marrowLines.count == 10 && marrowLines[0] == "Task: " + askOpen && marrowLines[1] == "Topic: Marrow · " + h3.dayLabel && marrowLines[2] == "Signals: 18 records (File 7 · AI 3 · Mail 8) · 18 direct / 0 inferred — title counts are signals, not proof of completed work" && marrowLines[9] == "12 more not shown" &&
          citeLines(marrowText).count == 6 && citeLines(marrowText).allSatisfy { l in marrow.items.contains { l.hasSuffix(" · " + $0.evidence.title) } } && claimsNoOutcome(marrowText) &&
          soraShown == ["[F1] Sora 일정표.xlsx", "[F2] Sora 견적 14건 합계 3종", "[F3] Sora 계약서 초안 검토 중 - 서명 미확정", "[M1] Sora 점심 메뉴", "[M2] Sora 정정: 상한 12개로 변경", "[M3] Sora 한도 예외 승인: 상한 17개"] &&
          m("draft agreement sent for legal review; signature not confirmed") == "-P" && m("original exception: cap 17 units; review February") == "D-" && m("Decision: cap stays at 12; no longer subject to review") == "DP" &&
          m("한도 예외 승인: 상한 17개") == "D-" && m("계약서 초안 검토 중 - 서명 미확정") == "-P" && m("정정: 상한 12개로 변경") == "DP" && m("승인 보류") == "-P" && m("승인 완료") == "D-" && m("contract draft v3") == "-p" && m("계약서 초안") == "-p" &&
          Standing.asked(askOpen) && Standing.asked(askNamed) && Standing.asked("현재 한도가 얼마로 확정됐나요?") && Standing.asked("is it still on hold?") && Standing.asked("아직 미정인가요"),
          marrowOpen.joined(separator: " | ") + " // " + marrowNamed.joined(separator: " | ") + " // " + soraShown.joined(separator: " | ") + " // " + marrowText)
    let generated = Evidence(origin: .ai, type: .ai, id: "g", title: "Marrow approved final decision summary", date: real.addingTimeInterval(-86400), dayOnly: false, source: "s", topics: [], locator: "", importedAt: nil, via: "feed", derivedTitle: true)
    let marrowPlain = shown(marrow, task: "Marrow rollout plan")
    let quiet = ["weekly operations review", "progress review and outstanding documentation", "budget 2026 summary with 14 line items and 3 totals", "capital plan for the unlimited tier", "Limited edition artwork", "signing ceremony photos", "designed layout", "Q3 update notes 17 units", "주간 회의록", "견적 14건 합계 3종", "일정 확인",
                 "approval meeting agenda", "approval calendar", "decision log template", "policy onboarding checklist", "deadline reminder", "승인 회의 안건", "승인 일정 캘린더", "결정 사안 목록 양식", "정책 온보딩 체크리스트"]
    check("H53", "round 3 applies only where it is relevant and never guesses: a task that does not ask about standing leaves the choice as round 2 made it (the correction, the approval and the draft are not pulled in); a task that asks, on a topic whose titles say nothing of the kind, changes nothing; numbers, \"review\", \"update\", \"notes\", look-alike words (capital, unlimited, Limited, signing, designed) and nouns that only name the subject (approval, decision, policy, deadline; 승인, 결정, 정책) are not marks; \"not confirmed\" and 미확정 are read as pending, never as confirmed; a machine-generated title carries no mark; a task that only follows up or compares does not count as asking",
          marrowPlain == ["[F1] Marrow rollout plan v4.pdf", "[F2] Marrow budget 2026 summary with 14 line items and 3 totals", "[A1] Marrow brainstorm notes", "[A2] Marrow naming ideas", "[M1] RE: Re: Marrow weekly sync", "[M2] Marrow lunch order"] &&
          !Standing.asked("Marrow rollout plan") && !Standing.asked("Follow up on the Harborline quote") && !Standing.asked("compare harborline and atlas") && !Standing.asked("Harborline 견적 회신 이어서 쓰기") && !Standing.asked("") &&
          shown(lumen, task: "is anything still pending now?") == lumenShown && shown(plain.items.isEmpty ? plain : made("Vesper", [("Vesper Phase 2 plan", 3, .file), ("Vesper Q3 report", 9, .file), ("Vesper design notes", 4, .mail)]), task: "what is the current status?") == ["[F1] Vesper Phase 2 plan", "[F2] Vesper Q3 report", "[M1] Vesper design notes"] &&
          quiet.allSatisfy { m($0) == "--" } && m("signature not confirmed") == "-P" && m("서명 미확정") == "-P" && m("not yet approved by legal") == "-P" && m("confirmed") == "D-" &&
          Standing.marks(generated) == (0, 0) && Standing.marks(title: generated.title) == (2, 0),
          marrowPlain.joined(separator: " | ") + " // " + quiet.map { $0 + "=" + m($0) }.joined(separator: ", "))
    // routine titles that all carry the subject's noun must not crowd out the two lines that say where it stands
    func crowded(_ name: String, _ routine: [String], _ paused: String, _ limited: String, split: Bool) -> TopicSummary {
        var rows: [(String, Double, RecordType)] = []
        for (i, r) in routine.enumerated() { rows.append((name + " " + r, Double(i + 1), split ? [RecordType.mail, .file, .file, .ai, .ai, .mail][i % 6] : .mail)) }
        rows.append((name + " " + paused, 30, .mail)); rows.append((name + " " + limited, 45, .mail))
        return made(name, rows)
    }
    let routineEN = ["approval meeting agenda", "approval calendar invite", "approval onboarding checklist", "approval workflow overview", "approval contacts list", "approval training slides"]
    let routineKO = ["승인 회의 안건", "승인 일정 캘린더", "승인 온보딩 체크리스트", "승인 절차 개요", "승인 담당자 목록", "승인 교육 자료"]
    let pausedEN = "approval paused pending inspection", limitedEN = "approval conditional on quantity 40", pausedKO = "승인 보류 - 점검 대기", limitedKO = "수량 40개 조건부 승인"
    let crowdRuns: [(String, [String])] = [("EN one type", shown(crowded("Kestrel", routineEN, pausedEN, limitedEN, split: false), task: "Is the Kestrel approval in force?")),
                                           ("EN three types", shown(crowded("Kestrel", routineEN, pausedEN, limitedEN, split: true), task: "Is the Kestrel approval in force?")),
                                           ("KO one type", shown(crowded("Haneul", routineKO, pausedKO, limitedKO, split: false), task: "Haneul 승인이 지금 유효한가요?")),
                                           ("KO three types", shown(crowded("Haneul", routineKO, pausedKO, limitedKO, split: true), task: "Haneul 승인이 지금 유효한가요?"))]
    let draftCrowd = made("Ibis", [("Ibis approval draft agenda", 1, .mail), ("Ibis approval draft calendar", 2, .mail), ("Ibis draft onboarding", 1, .file), ("Ibis draft workflow", 3, .file), ("Ibis draft contacts", 2, .ai), ("Ibis draft slides", 4, .ai),
                                   ("Ibis approval paused pending inspection", 30, .mail), ("Ibis approval conditional on quantity 40", 45, .mail)])
    let draftShown = shown(draftCrowd, task: "Is the Ibis approval in force?")
    let noPair = shown(made("Kestrel", routineEN.enumerated().map { (i, r) in ("Kestrel " + r, Double(i + 1), [RecordType.mail, .file, .ai][i % 3]) } + [("Kestrel floor plan", 30, .mail)]), task: "Is the Kestrel approval in force?")
    check("H55", "round 3 under crowding — six routine titles that all carry the subject's noun (an approval agenda, calendar, checklist …; 승인 회의 안건, 일정 …) and two older titles that say where it stands (paused pending inspection; conditional on a quantity — 보류·대기; 조건부): both older lines are shown, in English and in Korean, whether everything is mail or spread over three types; each type keeps its newest line; the paused line and the conditional line take the place of the weakest other line, also when the routine titles are themselves weakly marked (\"draft\"); and when no title says where the thing stands, the routine noun changes nothing (the choice is the plain one)",
          crowdRuns.allSatisfy { _, list in list.count == 6 && list.filter { $0.contains("paused pending inspection") || $0.contains("보류 - 점검 대기") }.count == 1 && list.filter { $0.contains("conditional on quantity 40") || $0.contains("조건부 승인") }.count == 1 } &&
          crowdRuns[0].1 == ["[M1] Kestrel approval meeting agenda", "[M2] Kestrel approval calendar invite", "[M3] Kestrel approval onboarding checklist", "[M4] Kestrel approval workflow overview", "[M5] Kestrel approval paused pending inspection", "[M6] Kestrel approval conditional on quantity 40"] &&
          crowdRuns[1].1.contains("[M1] Kestrel approval meeting agenda") && crowdRuns[1].1.contains("[F1] Kestrel approval calendar invite") && crowdRuns[1].1.contains("[A1] Kestrel approval workflow overview") &&
          crowdRuns[3].1.contains("[M1] Haneul 승인 회의 안건") && crowdRuns[3].1.contains("[F1] Haneul 승인 일정 캘린더") && crowdRuns[3].1.contains("[A1] Haneul 승인 절차 개요") &&
          draftShown.count == 6 && draftShown.contains { $0.hasSuffix("paused pending inspection") } && draftShown.contains { $0.hasSuffix("conditional on quantity 40") } && draftShown.contains("[M1] Ibis approval draft agenda") && draftShown.contains { $0.hasPrefix("[F1] Ibis draft onboarding") } && draftShown.contains { $0.hasPrefix("[A1] Ibis draft contacts") } &&
          noPair == ["[F1] Kestrel approval calendar invite", "[F2] Kestrel approval contacts list", "[A1] Kestrel approval onboarding checklist", "[A2] Kestrel approval training slides", "[M1] Kestrel approval meeting agenda", "[M2] Kestrel approval workflow overview"] &&
          m(pausedEN) == "-P" && m(limitedEN) == "D-" && m(pausedKO) == "-P" && m(limitedKO) == "D-" && routineEN.allSatisfy { m($0) == "--" } && routineKO.allSatisfy { m($0) == "--" },
          crowdRuns.map { $0.0 + ": " + $0.1.joined(separator: " | ") }.joined(separator: " // ") + " // draft: " + draftShown.joined(separator: " | ") + " // none: " + noPair.joined(separator: " | "))

    // a stated condition and a bound on a number are limits; the noun "condition" and a number alone are not
    let boundKO = shown(crowded("Haneul", routineKO, pausedKO, "승인 조건: 상자당 8개 이하", split: true), task: "Haneul 승인이 지금 유효한가요?")
    let boundOnly = shown(crowded("Haneul", routineKO, pausedKO, "상자당 12개 미만으로 출고", split: false), task: "Haneul 승인이 지금 유효한가요?")
    let boundEN = shown(crowded("Kestrel", routineEN, pausedEN, "approval condition: 8 per box", split: true), task: "Is the Kestrel approval in force?")
    let nounOnly = shown(crowded("Haneul", routineKO, pausedKO, "승인 조건 설명회", split: true), task: "Haneul 승인이 지금 유효한가요?")
    let limits = ["승인 조건: 상자당 8개 이하", "조건 : 선금 30%", "상자당 8개 이하", "10kg 미만", "3일 이상 소요", "1,000원 초과", "수량 40개 조건부 승인", "condition: 8 per box", "Conditions: net 30"]
    let notLimits = ["조건 설명회", "승인 조건 안내", "조건:", "이상 없음", "초과 근무 일정", "8개 발송", "상자 8개와 팔레트 2개", "2026년 3분기 수량 40개 견적", "terms and conditions overview", "air conditioning schedule", "condition report", "8 per box shipped"]
    check("H56", "a stated condition and a bound on a number are limits; the bare noun and a bare number are not — \"조건: <value>\" (and \"condition: <value>\") and a number with its unit followed by 이하 / 이상 / 미만 / 초과 are read as a limit, so a title like \"승인 조건: 상자당 8개 이하\" is shown beside the paused line even under six routine 승인 titles; \"조건 설명회\", \"조건:\" with nothing after it, 이상 or 초과 without a number, and titles that merely contain numbers carry no mark and are not pulled in",
          boundKO.count == 6 && boundKO.contains { $0.hasSuffix("승인 조건: 상자당 8개 이하") } && boundKO.contains { $0.hasSuffix(pausedKO) } && boundOnly.contains { $0.hasSuffix("상자당 12개 미만으로 출고") } && boundOnly.contains { $0.hasSuffix(pausedKO) } &&
          boundEN.contains { $0.hasSuffix("approval condition: 8 per box") } && boundEN.contains { $0.hasSuffix(pausedEN) } &&
          nounOnly.count == 6 && !nounOnly.contains { $0.hasSuffix("승인 조건 설명회") } && nounOnly.contains { $0.hasSuffix(pausedKO) } &&
          limits.allSatisfy { m($0) == "D-" } && notLimits.allSatisfy { m($0) == "--" },
          boundKO.joined(separator: " | ") + " // " + nounOnly.joined(separator: " | ") + " // " + (limits + notLimits).map { $0 + "=" + m($0) }.joined(separator: ", "))

    // ids are only unique within one source: a file, a chat and a mail may all be "shared-a"
    func sharedTopic(_ rows: [(String, String, Double, RecordType)]) -> TopicSummary {
        let items = rows.map { r in TopicItem(evidence: Evidence(origin: r.3.governing, type: r.3, id: r.0, title: r.1, date: real.addingTimeInterval(-r.2 * 86400), dayOnly: false, source: "s", topics: [], locator: "", importedAt: nil, via: "feed"), direct: true, count: 1) }.sorted { $0.evidence.date > $1.evidence.date }
        return TopicSummary(key: "pell", display: "Pell", items: items, types: RecordType.allCases.filter { t in items.contains { $0.evidence.type == t } })
    }
    let sharedSix = sharedTopic([("shared-a", "Pell intake form", 1, .file), ("shared-b", "Pell floor plan", 2, .file), ("shared-a", "Pell kickoff chat", 3, .ai), ("shared-b", "Pell naming chat", 4, .ai), ("shared-a", "Pell approved cap 9 seats", 5, .mail), ("shared-b", "Pell seating draft", 6, .mail)])
    let sharedText = Export.simple(task: "", topic: sharedSix, window: h3, coverage: [])
    let sharedChains = sharedTopic([("x", "Pell layout v1.pdf", 9, .file), ("x", "Pell layout v2.pdf", 2, .file), ("x", "Pell notes.txt", 5, .file), ("x", "Pell thread", 8, .mail), ("x", "Re: Pell thread", 1, .mail), ("x", "Pell single", 4, .mail)])
    check("H54", "lines are told apart by their place in the topic, not by record id (ids are only unique within one source): six different dated titles, two per type, whose ids are \"shared-a\" and \"shared-b\" in every type are all six cited — with no task, with a task, and with a task that asks about standing; and with one id on every record the chains are still grouped by title (newest revision and newest reply first, the one-off next, the earlier members only to fill the places)",
          shown(sharedSix) == ["[F1] Pell intake form", "[F2] Pell floor plan", "[A1] Pell kickoff chat", "[A2] Pell naming chat", "[M1] Pell approved cap 9 seats", "[M2] Pell seating draft"] &&
          citeLines(sharedText).count == 6 && !sharedText.contains("more not shown") && sharedText.contains("Signals: 6 records (File 2 · AI 2 · Mail 2)") &&
          shown(sharedSix, task: "Pell floor plan and naming") == ["[F1] Pell floor plan", "[F2] Pell intake form", "[A1] Pell naming chat", "[A2] Pell kickoff chat", "[M1] Pell approved cap 9 seats", "[M2] Pell seating draft"] &&
          Set(shown(sharedSix, task: "is the seating cap final yet?")).count == 6 && shown(sharedSix, task: "is the seating cap final yet?").count == 6 &&
          shown(sharedChains) == ["[F1] Pell layout v2.pdf", "[F2] Pell notes.txt", "[F3] Pell layout v1.pdf", "[M1] Re: Pell thread", "[M2] Pell single", "[M3] Pell thread"],
          shown(sharedSix).joined(separator: " | ") + " // " + shown(sharedSix, task: "is the seating cap final yet?").joined(separator: " | ") + " // " + shown(sharedChains).joined(separator: " | "))

    // ── finding a topic for what is typed (local, deterministic) ──
    func found(_ q: String, _ list: [TopicSummary], limit: Int = 3) -> String { Search.rank(q, topics: list, limit: limit).map { $0.topic.key }.joined(separator: ",") }
    check("H37", "search ranks the topics that are in view: the topic named in the task comes first and a topic that only shares a title word comes after it (\"Harborline 견적 이어서\" → Harborline, then Atlas); a name word plus a title word; a name typed halfway (\"harb\"); a Korean word with its particle (\"견적을\"); a word found only in titles (\"quote\"); letter case and \"_\" do not matter; the same input always gives the same answer",
          found("Harborline 견적 이어서", t5) == "harborline,atlas" && found("atlas layout", t5) == "atlas" && found("harb", t5) == "harborline" && found("견적을 다시", t5) == "harborline,atlas" &&
          found("quote", t5) == "harborline" && found("HARBORLINE_견적", t5) == "harborline,atlas" && found("Harborline 견적 이어서", t5) == found("Harborline 견적 이어서", t5) &&
          Search.tokens("Harborline 견적을 이어서 2026-11 pdf the") == ["harborline", "견적을", "견적"],
          [found("Harborline 견적 이어서", t5), found("atlas layout", t5), found("harb", t5), found("견적을 다시", t5), found("quote", t5), Search.tokens("Harborline 견적을 이어서 2026-11 pdf the").joined(separator: "+")].joined(separator: " | "))

    // ── the optional local Mac Mail adapter, with the Mac's side passed in (Mail itself is never asked here) ──
    var ran = 0, asked = 0
    let offCase = MailAdapter.collect(isRunning: { false }, permission: { asked += 1; return 0 }, run: { _ in ran += 1; return ("", 0) })
    let deniedCase = MailAdapter.collect(isRunning: { true }, permission: { -1743 }, run: { _ in ran += 1; return ("", 0) })
    let sepc = "\u{1F}"
    var reply = ["N", "I", "1500"].joined(separator: sepc) + "\n" + ["I", "<a1@mail.example>", "2026-11-20T10:00:00", "Harborline 회신 건"].joined(separator: sepc) + "\n" + ["I", "<a2@mail.example>", "no date", "x"].joined(separator: sepc) + "\n"
    reply += ["N", "S", "2"].joined(separator: sepc) + "\n" + ["S", "<a3@mail.example>", "2026-11-19T09:00:00", "Atlas 발송\u{0007} 확인"].joined(separator: sepc) + "\n"
    var scriptSeen = ""
    let okCase = MailAdapter.collect(isRunning: { true }, permission: { 0 }, run: { s in scriptSeen = s; return (reply, 0) })
    let many = (0..<230).map { ["I", "<n\($0)@mail.example>", "2026-11-20T10:00:00", "메일 \($0)"].joined(separator: sepc) }.joined(separator: "\n")
    let capCase = MailAdapter.parse(["N", "I", "230"].joined(separator: sepc) + "\n" + many)
    let timeoutCase = MailAdapter.collect(isRunning: { true }, permission: { 0 }, run: { _ in (nil, -1712) }), quitCase = MailAdapter.collect(isRunning: { true }, permission: { 0 }, run: { _ in (nil, -600) })
    check("H21", "Mac Mail adapter decisions: Mail not running → nothing is asked and nothing is run (it is never started); macOS refuses → \"Permission denied\", nothing run; allowed → the fixed script runs once and its answer becomes rows; a timeout and Mail quitting are reported as they are",
          offCase.outcome == .notRunning && asked == 0 && deniedCase.outcome == .denied && ran == 0 && offCase.rows.isEmpty && deniedCase.rows.isEmpty && okCase.rows.count == 2 &&
          okCase.outcome == .collected(inbox: 1, sent: 1, inboxTotal: 1500, sentTotal: 2, skipped: 1) && timeoutCase.outcome == .unavailable("Mail did not answer in time (timed out)") && quitCase.outcome == .notRunning &&
          MailAdapter.Outcome.denied.message.hasPrefix("Permission denied") && MailAdapter.Outcome.notRunning.message.contains("never opens Mail by itself"), "\(offCase.outcome) \(deniedCase.outcome) \(okCase.outcome) ran=\(ran) asked=\(asked)")
    check("H22", "Mac Mail adapter data: subject and date only — titles are sanitised, the Message-ID is kept only as a hash, no address is stored, rows are mail records marked \"From Mail\" from Inbox or Sent; the cap is honest: 1,500 in the Inbox but 200 asked → the message says only the newest 200 are included, and a longer answer is cut at 200",
          (okCase.rows.map { $0["title"] as? String ?? "" }) == ["Harborline 회신 건", "Atlas 발송 확인"] && (okCase.rows.map { $0["source"] as? String ?? "" }) == ["Mac Mail Inbox", "Mac Mail Sent"] &&
          !json(okCase.rows).contains("@") && !json(okCase.rows).contains("a1") && (okCase.rows.allSatisfy { ($0["via"] as? String) == "macmail" && ($0["kind"] as? String) == "mail" && (($0["id"] as? String) ?? "").hasPrefix("macmail:") }) &&
          okCase.outcome.message.contains("Inbox 1 (of 1500), Sent 1 (of 2)") && okCase.outcome.message.contains("only the newest 200 of each; older mail is not included") && okCase.outcome.message.hasSuffix(" · 1 line could not be read") && capCase.rows.count == 200 && capCase.outcome.message.contains("only the newest 200 of each"), okCase.outcome.message)
    let scriptLower = scriptSeen.lowercased()
    check("H23", "the Mail script is fixed and read-only: it addresses Mail by its bundle ID, asks only for message id, date and subject of the first 200 messages of inbox and sent mailbox, and has no word that opens, activates, sends, deletes, moves or reads content, senders or recipients",
          scriptSeen == MailAdapter.script(cap: 200) && scriptSeen.contains("tell application id \"com.apple.mail\"") && scriptSeen.contains("if n > 200 then set n to 200") && scriptSeen.contains("subject of m") &&
          ["activate", "launch", "open ", "send", "delete", "move ", "content", "sender", "recipient", "address", "source of", "do shell", "attachment", "set subject", "make new"].allSatisfy { !scriptLower.contains($0) }, scriptSeen)
    var macParsed = Importer.Parsed(); macParsed.rows = okCase.rows; macParsed.format = "macmail"
    let savedMac = Importer.save(macParsed, name: "mac-mail", places: places, now: real), savedMacAgain = Importer.save(macParsed, name: "mac-mail", places: places, now: real)
    let s6 = Snapshot.read(places, now: real), c6 = s6.coverage(for: .imports, window: h3, enabled: all)
    let macRow = s6.evidence.first { $0.via == "macmail" }
    check("H24", "collecting from Mail again adds only what is new, as its own file: the first save adds 2, the second adds none; the Gmail feed (mail.jsonl) and earlier imports are untouched; those rows are marked \"From Mail\", not snapshots, and coverage counts them apart from the snapshots",
          savedMac.imported == 2 && savedMacAgain.imported == 0 && savedMacAgain.duplicates == 2 && savedMacAgain.file == nil && fm.contents(atPath: places.mail.path) == mailBefore &&
          macRow?.provenance == "From Mail" && macRow?.isSnapshot == false && macRow?.type == .mail && c6.snapshots == 11 && c6.mailCollected == 2 && c6.summary.contains("11 snapshot records") && c6.summary.contains(" · 2 collected from Mail") &&
          ((try? fm.contentsOfDirectory(atPath: places.imports.path)) ?? []).filter { $0.hasPrefix(".") }.isEmpty, c6.summary)

    // ── the optional refresh tool ──
    let tool = places.refreshTool, toolsDir = tool.deletingLastPathComponent()
    let none = RefreshTool.check(tool)
    try? fm.createDirectory(at: toolsDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let marker = toolsDir.appendingPathComponent("ran.txt")
    fm.createFile(atPath: tool.path, contents: Data("#!/bin/sh\necho \"args=$#\" > \"$(dirname \"$0\")/ran.txt\"\n".utf8), attributes: [.posixPermissions: 0o700])
    let good = RefreshTool.check(tool)
    try? fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: tool.path); let writable = RefreshTool.check(tool)
    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tool.path); let notExec = RefreshTool.check(tool)
    try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
    try? fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: toolsDir.path); let openDir = RefreshTool.check(tool)
    try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: toolsDir.path)
    let linkHome = temp.appendingPathComponent("home5", isDirectory: true), linkTool = Places(home: linkHome).refreshTool
    try? fm.createDirectory(at: linkTool.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try? fm.createSymbolicLink(at: linkTool, withDestinationURL: tool)
    let linked = RefreshTool.check(linkTool)
    check("H25", "the refresh tool is offered only when it is safe: missing → not offered; a regular file owned by me, executable, in my own closed folder → offered; writable by others, not executable, a folder others can write, or a symbolic link → refused; its place is fixed at ~/WorkIndex/horizon-tools/refresh.command",
          !none.ok && good.ok && !writable.ok && !notExec.ok && !openDir.ok && !linked.ok && tool.path.hasSuffix("/WorkIndex/horizon-tools/refresh.command"), [none, good, writable, notExec, openDir, linked].map { "\($0.ok)" }.joined(separator: ","))
    let ranBefore = fm.fileExists(atPath: marker.path)
    let wait = DispatchSemaphore(value: 0)
    var exitStatus: Int32? = nil
    RefreshTool.run(tool, timeout: 20) { status, _ in exitStatus = status; wait.signal() }
    _ = wait.wait(timeout: .now() + 25)
    var refusedRan = false
    let wait2 = DispatchSemaphore(value: 0)
    RefreshTool.run(linkTool, timeout: 5) { status, _ in refusedRan = status != nil; wait2.signal() }
    _ = wait2.wait(timeout: .now() + 6)
    let ranText = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
    check("H26", "checking the tool never runs it; run (which the window calls only after the person confirms) starts that one file with no arguments and reports its exit status; a refused tool is not started; imports made before are still there afterwards (the tool and the imports are independent)",
          !ranBefore && exitStatus == 0 && ranText == "args=0\n" && !refusedRan && ((try? fm.contentsOfDirectory(atPath: places.imports.path))?.count ?? 0) == 6, "before=\(ranBefore) exit=\(String(describing: exitStatus)) ran=\(ranText)")

    // ── the custom period (Custom): whole days, start and end included ──
    func msg(_ c: CustomPeriod.Check) -> String { c.message }
    let vReversed = CustomPeriod.validate(start: at(2026, 5, 10), end: at(2026, 5, 9), now: now, calendar: seoul)
    let vFutureEnd = CustomPeriod.validate(start: at(2026, 5, 1), end: at(2026, 6, 1), now: now, calendar: seoul)
    let vFutureBoth = CustomPeriod.validate(start: at(2026, 6, 2), end: at(2026, 6, 3), now: now, calendar: seoul)
    let vTooLong = CustomPeriod.validate(start: at(2025, 11, 29), end: at(2026, 5, 31), now: now, calendar: seoul)
    let vSixMonths = CustomPeriod.validate(start: at(2025, 11, 30), end: at(2026, 5, 31), now: now, calendar: seoul)
    let augNow = at(2026, 8, 31, 9)
    let vClampOK = CustomPeriod.validate(start: at(2026, 2, 28), end: at(2026, 8, 31), now: augNow, calendar: seoul), vClampOver = CustomPeriod.validate(start: at(2026, 2, 27), end: at(2026, 8, 31), now: augNow, calendar: seoul)
    check("H29", "custom period, refused with useful feedback: a start after the end names both days; an end (or a whole period) after today names today; more than six calendar months names the earliest start allowed for that end — with the day clamped at a month's end (for 31 Aug, 28 Feb is allowed and 27 Feb is not); exactly six calendar months is accepted",
          vReversed == .refused("The start date (2026-05-10) is after the end date (2026-05-09). Choose a start date on or before the end date.") &&
          vFutureEnd == .refused("The end date (2026-06-01) is in the future. You can choose dates up to today (2026-05-31).") && msg(vFutureBoth).hasPrefix("The end date (2026-06-03) is in the future.") &&
          vTooLong == .refused("The period is longer than 6 months. With an end date of 2026-05-31, the start date must be 2025-11-30 or later.") && vSixMonths == .ok(start: at(2025, 11, 30), end: at(2026, 5, 31), days: 183) &&
          vClampOK.isOK && msg(vClampOver).contains("the start date must be 2026-02-28 or later") && !vReversed.isOK && !vFutureEnd.isOK && !vTooLong.isOK,
          [vReversed, vFutureEnd, vFutureBoth, vTooLong, vSixMonths, vClampOver].map(msg).joined(separator: " | "))
    let vSameToday = CustomPeriod.validate(start: at(2026, 5, 31), end: at(2026, 5, 31), now: now, calendar: seoul), vSamePast = CustomPeriod.validate(start: at(2026, 4, 1, 23, 59), end: at(2026, 4, 1, 0, 1), now: now, calendar: seoul)
    let vToday = CustomPeriod.validate(start: at(2026, 5, 1), end: at(2026, 5, 31, 23, 59), now: now, calendar: seoul)
    check("H30", "custom period, accepted: a single day (today, or a past day — the time of day is ignored, so 23:59 to 00:01 of one day is not \"reversed\"); a period ending today even when the picker's time is later than now; the feedback says the days and that both ends are included",
          vSameToday == .ok(start: at(2026, 5, 31), end: at(2026, 5, 31), days: 1) && vSamePast == .ok(start: at(2026, 4, 1), end: at(2026, 4, 1), days: 1) && vToday == .ok(start: at(2026, 5, 1), end: at(2026, 5, 31), days: 31) &&
          CustomPeriod.earliestStart(for: at(2026, 5, 31), calendar: seoul) == at(2025, 11, 30), msg(vSameToday) + " | " + msg(vToday))
    let cw = HorizonWindow(customStart: at(2026, 3, 10), customEnd: at(2026, 4, 20), now: now, calendar: seoul)
    check("H31", "custom period boundaries, both days included: 10 Mar 00:00:00 and 20 Apr 23:59:59 are in, 9 Mar 23:59:59 and 21 Apr 00:00:00 are out, and the same for bare dates; a record after the period but before now is simply outside (not \"future\"); the label gives the days and their number (42)",
          cw.contains(ev(at(2026, 3, 10, 0, 0, 0))) && cw.contains(ev(at(2026, 4, 20, 23, 59, 59))) && !cw.contains(ev(at(2026, 3, 9, 23, 59, 59))) && !cw.contains(ev(at(2026, 4, 21, 0, 0, 0))) &&
          cw.contains(ev(at(2026, 3, 10), dayOnly: true)) && cw.contains(ev(at(2026, 4, 20), dayOnly: true)) && !cw.contains(ev(at(2026, 3, 9), dayOnly: true)) && !cw.contains(ev(at(2026, 4, 21), dayOnly: true)) &&
          !cw.isFuture(ev(at(2026, 4, 21))) && cw.isFuture(ev(at(2026, 6, 1))) && cw.isFuture(ev(now.addingTimeInterval(1))) && cw.days == 42 && cw.isCustom &&
          cw.label == "Custom · 2026-03-10 – 2026-04-20 (both days included, 42 days)" && cw.dayLabel == "Custom · 2026-03-10 – 2026-04-20 (both days included)", cw.label)
    let oneToday = HorizonWindow(customStart: at(2026, 5, 31), customEnd: at(2026, 5, 31), now: now, calendar: seoul), onePast = HorizonWindow(customStart: at(2026, 4, 1), customEnd: at(2026, 4, 1), now: now, calendar: seoul)
    check("H32", "same-day periods: today alone holds 00:00:00 up to now (15:00) and today as a bare date, not yesterday 23:59:59 and not one second after now (that is future); a past single day holds 00:00:00 to 23:59:59 of that day only; presets are unchanged (not custom, ending now)",
          oneToday.days == 1 && oneToday.contains(ev(at(2026, 5, 31, 0, 0, 0))) && oneToday.contains(ev(now)) && oneToday.contains(ev(at(2026, 5, 31), dayOnly: true)) && !oneToday.contains(ev(at(2026, 5, 30, 23, 59, 59))) &&
          !oneToday.contains(ev(now.addingTimeInterval(1))) && oneToday.isFuture(ev(now.addingTimeInterval(1))) && oneToday.end == now &&
          onePast.contains(ev(at(2026, 4, 1, 0, 0, 0))) && onePast.contains(ev(at(2026, 4, 1, 23, 59, 59))) && !onePast.contains(ev(at(2026, 4, 2, 0, 0, 0))) && !onePast.contains(ev(at(2026, 3, 31, 23, 59, 59))) && !onePast.contains(ev(at(2026, 4, 2), dayOnly: true)) &&
          !w3.isCustom && w3.days == 93 && w3.end == now && w3.endDay == at(2026, 5, 31), "\(oneToday.label) | \(onePast.label) | \(w3.days)")
    // the chosen days drive topics, coverage and the handoff (the fictional sources from above, dated relative to the real now)
    let cal = Calendar.current
    let cStart = cal.startOfDay(for: real.addingTimeInterval(-26 * 86400)), cEnd = cal.startOfDay(for: real.addingTimeInterval(-17 * 86400))
    let hc = HorizonWindow(customStart: cStart, customEnd: cEnd, now: real)
    let tc = Analysis.topics(s5.evidence, window: hc, enabled: all)
    let covC = SourceKind.allCases.map { s5.coverage(for: $0, window: hc, enabled: all) }
    let textC = tc.first.map { Export.simple(task: "", topic: $0, window: hc, coverage: covC) } ?? ""
    let oneDay = HorizonWindow(customStart: real.addingTimeInterval(-20 * 86400), customEnd: real.addingTimeInterval(-20 * 86400), now: real)
    check("H33", "the chosen days are what is used: a custom period from 26 to 17 days ago shows only what is dated inside it — Harborline from 2 files, 1 AI chat and 1 mail, no Atlas or Northfield, no imports; coverage counts that period per source (files 2, AI 1 with the future record still reported, mail 1, imports 0 of 11); the handoff states the custom days; a one-day period 20 days ago shows the two records of that day",
          names(tc) == "harborline:file+ai+mail:4" && covC[0].summary.hasPrefix("2 in this period (5 total)") && covC[1].summary.hasPrefix("1 in this period (6 total)") && covC[1].summary.contains("1 future-dated left out") &&
          covC[2].summary.hasPrefix("1 in this period (3 total)") && covC[3].summary.hasPrefix("0 in this period (11 total)") &&
          textC.hasPrefix("Topic: Harborline · Custom · " + Dates.day(cStart) + " – " + Dates.day(cEnd) + " (both days included)\n") && textC.contains("\nSignals: 4 records (File 2 · AI 1 · Mail 1)") && textC.contains("\nSource caution: ") &&
          textC.split(separator: "\n").filter { $0.hasPrefix("[") }.count == 4 && names(Analysis.topics(s5.evidence, window: oneDay, enabled: all)) == "harborline:file+ai:2" &&
          names(Analysis.topics(s5.evidence, window: hc, enabled: [.files, .ai, .imports])) == "harborline:file+ai:3", names(tc) + " // " + covC.map { $0.summary }.joined(separator: " || ") + " // " + textC)
    let cStore = MemoryStore(), cPrefs = Preferences(store: cStore)
    let before = cPrefs.window(now: now, calendar: seoul)
    cPrefs.setCustom(start: at(2026, 3, 10, 14), end: at(2026, 4, 20, 9), calendar: seoul)
    cPrefs.set(.mail, false)
    let storedDays = (cStore.string("customStart") ?? "") + ".." + (cStore.string("customEnd") ?? "")
    let reopened = Preferences(store: cStore).window(now: now, calendar: seoul)
    cPrefs.usesCustom = false; cPrefs.months = 6
    let preset = Preferences(store: cStore).window(now: now, calendar: seoul), keptDays = Preferences(store: cStore).customDays(calendar: seoul)
    cStore.set("2026-04-20", "customStart"); cStore.set("2026-03-10", "customEnd"); cPrefs.usesCustom = true
    let reversedStored = cPrefs.window(now: now, calendar: seoul)
    cStore.set("soon", "customStart")
    let garbageStored = cPrefs.window(now: now, calendar: seoul)
    check("H34", "the choice is kept: 3 months by default; a custom period is saved as two days and is in force again after reopening, with the source switches as they were; choosing a preset again uses the preset and remembers the custom days for next time; a stored period that is reversed or unreadable is not used — the preset is shown with the reason",
          !before.window.isCustom && before.window.months == 3 && before.note == nil && reopened.window.isCustom && reopened.window.start == at(2026, 3, 10) && reopened.window.endDay == at(2026, 4, 20) && reopened.note == nil &&
          storedDays == "2026-03-10..2026-04-20" && Preferences(store: cStore).enabled == [.files, .ai, .imports] &&
          !preset.window.isCustom && preset.window.months == 6 && keptDays?.start == at(2026, 3, 10) &&
          !reversedStored.window.isCustom && reversedStored.window.months == 6 && (reversedStored.note ?? "").contains("cannot be used; showing 6 months — The start date (2026-04-20) is after the end date (2026-03-10)") &&
          !garbageStored.window.isCustom && (garbageStored.note ?? "").contains("could not be read; showing 6 months"), "\(reopened.window.label) | \(preset.window.label) | \(reversedStored.note ?? "") | \(garbageStored.note ?? "")")

    // ── machine-generated titles ("derivedTitle": true) ──
    let home7 = temp.appendingPathComponent("home7", isDirectory: true), p7 = Places(home: home7)
    func aiRow(_ id: String, _ title: String, _ days: Double, _ topics: [String], derived: Any? = nil) -> String {
        var o: [String: Any] = ["id": id, "title": title, "date": ago(days), "topics": topics, "source": "Claude", "locator": ""]
        if let d = derived { o["derivedTitle"] = d }
        return json(o)
    }
    let derivedRows: [(String, String, Double, [String], Any?)] = [
        ("a1", "Harborline 견적 검토", 19, ["Harborline"], nil),                    // the person's own title: direct
        ("d1", "Harborline 가격 협상 요약", 10, [], true),                          // generated, no topics: must not join by its title
        ("d2", "Harborline 후속 정리", 9, ["Harborline"], true),                    // generated, own topic: joins, inferred
        ("z1", "Zephyr 출시 계획", 8, ["Zephyr"], true), ("z2", "Zephyr 일정", 7, ["Zephyr"], true),   // two generated: listed, both inferred
        ("o1", "Onyx 검토", 6, ["Onyx"], true),                                      // one generated alone: not a topic
        ("q1", "Quartz 검토", 6, ["Quartz"], true), ("q2", "Quartz 재검토", 5, [], 1),                   // 1 is not true: an ordinary title
        ("q3", "Quartz 회의", 4, [], "true"), ("q4", "Quartz 메모", 3, [], false)]
    write(p7.preindex, fileRow("Harborline Q3 quote.xlsx", 20, ["topic:harborline"]) + "\n")
    write(p7.ai, derivedRows.map { aiRow($0.0, $0.1, $0.2, $0.3, derived: $0.4) }.joined(separator: "\n") + "\n")
    let s7 = Snapshot.read(p7, now: real), t7 = Analysis.topics(s7.evidence, window: h3, enabled: all)
    func signalsOf(_ list: [TopicSummary], _ key: String) -> String { (list.first { $0.key == key }?.items ?? []).map { (item: TopicItem) -> String in String(item.evidence.id.suffix(2)) + "=" + (item.direct ? "direct" : "inferred") }.sorted().joined(separator: ",") }
    write(p7.ai, derivedRows.map { aiRow($0.0, $0.1, $0.2, $0.3) }.joined(separator: "\n") + "\n")          // the same rows without any flag
    let t7plain = Analysis.topics(Snapshot.read(p7, now: real).evidence, window: h3, enabled: all)
    let flags = s7.evidence.filter { $0.derivedTitle }.map { $0.id }.sorted().joined(separator: ",")
    let flagURL = temp.appendingPathComponent("export/derived.jsonl")
    write(flagURL, aiRow("x1", "자동 생성 제목", 3, ["Zephyr"], derived: true) + "\n" + aiRow("x2", "직접 쓴 제목", 3, ["Zephyr"]) + "\n")
    let flagParsed = Importer.parse(flagURL, jsonlKind: .ai)
    check("H35", "machine-generated titles (\"derivedTitle\": true) are never a direct mention and never matched by title: a generated \"Harborline …\" title with no topics does not join Harborline; one with the topic joins as inferred; two generated records make Zephyr a topic with 0 direct; one alone (Onyx) is not a topic; only a JSON true counts (1, \"true\", false and a missing flag are ordinary titles); without the flags the same rows would all be direct; the flag travels with an imported .jsonl row",
          names(t7) == "harborline:file+ai:3 | quartz:ai:4 | zephyr:ai:2" && signalsOf(t7, "harborline") == "a1=direct,d2=inferred,sx=direct" && signalsOf(t7, "zephyr") == "z1=inferred,z2=inferred" &&
          signalsOf(t7, "quartz") == "q1=inferred,q2=direct,q3=direct,q4=direct" && !t7.contains { $0.key == "onyx" } && flags == "d1,d2,o1,q1,z1,z2" &&
          names(t7plain) == "harborline:file+ai:4 | quartz:ai:4 | zephyr:ai:2 | onyx:ai:1" && signalsOf(t7plain, "harborline").contains("d1=direct") && signalsOf(t7plain, "zephyr") == "z1=direct,z2=direct" &&
          (flagParsed.rows[0]["derivedTitle"] as? Bool) == true && flagParsed.rows[1]["derivedTitle"] == nil && Reader.flag(true) && !Reader.flag(1) && !Reader.flag("true") && !Reader.flag(nil),
          names(t7) + " // " + signalsOf(t7, "harborline") + " // " + signalsOf(t7, "quartz") + " // " + flags + " // " + names(t7plain))

    check("H38", "no arbitrary match: unknown words, fillers, dates, formats, one- or two-letter Latin fragments and an empty task return nothing at all (there is no \"closest guess\"); at most three topics come back; a topic whose source is switched off cannot be found; words that appear only in machine-generated titles do not match, while the topic's own name still does",
          found("zzqx 없는주제", t5).isEmpty && found("이어서 계속 정리해줘", t5).isEmpty && found("2026-11 pdf the", t5).isEmpty && found("ha", t5).isEmpty && found("a", t5).isEmpty && found("   ", t5).isEmpty && found("", t5).isEmpty &&
          found("harborline atlas northfield", t5).split(separator: ",").count == 3 && found("harborline atlas northfield", t5, limit: 2).split(separator: ",").count == 2 &&
          found("northfield", t5) == "northfield" && found("northfield", tMailOff).isEmpty && found("출시", t7).isEmpty && found("zephyr", t7) == "zephyr" && found("출시", t7plain) == "zephyr",
          [found("zzqx 없는주제", t5), found("ha", t5), found("harborline atlas northfield", t5), found("northfield", tMailOff), found("출시", t7), found("출시", t7plain)].joined(separator: " | "))

    // ── an install with only an imported .mbox: no record carries a topic list ──
    let home8 = temp.appendingPathComponent("home8", isDirectory: true), p8 = Places(home: home8)
    func mboxText(_ list: [(subject: String, days: Double)]) -> String {
        var out: [String] = []
        for (i, m) in list.enumerated() { out += ["From sample@example.invalid Mon Jan  1 00:00:00 2024", "X-Gmail-Labels: Inbox", "Subject: " + m.subject, "Date: " + rfc2822(real.addingTimeInterval(-m.days * 86400)), "Message-ID: <fb\(i)@example.invalid>", "", "body line", ""] }
        return out.joined(separator: "\n")
    }
    let fbURL = temp.appendingPathComponent("export/fallback.mbox")
    write(fbURL, mboxText([("Harborline quote revision", 3), ("Re: Harborline quote revision", 2), ("Harborline contract draft", 5), ("Atlas onboarding checklist", 6), ("Atlas onboarding schedule", 8),
                           ("Team lunch on Friday", 4), ("회의 일정 안내", 4), ("견적서 검토 요청", 7), ("Re: 견적서 수정본", 9), ("2026 November pdf report", 10), ("FW: 2026 November pdf report", 11)]))
    let fbSaved = Importer.save(Importer.parse(fbURL), name: "fallback", places: p8, now: real)
    let t8 = Analysis.topics(Snapshot.read(p8, now: real).evidence, window: h3, enabled: all)
    let hb8 = t8.first { $0.key == "harborline" }
    let fbText = hb8.map { Export.simple(task: "Follow up on the Harborline quote", topic: $0, window: h3, coverage: []) } ?? ""
    write(p8.ai, [aiRow("g1", "Quartz launch plan", 3, [], derived: true), aiRow("g2", "Quartz launch notes", 4, [], derived: true)].joined(separator: "\n") + "\n")
    let t8derived = Analysis.topics(Snapshot.read(p8, now: real).evidence, window: h3, enabled: all)
    write(p8.ai, [aiRow("z1", "Planning notes one", 3, ["Zephyr"]), aiRow("z2", "Planning notes two", 4, ["Zephyr"])].joined(separator: "\n") + "\n")
    let t8feed = Analysis.topics(Snapshot.read(p8, now: real).evidence, window: h3, enabled: all)
    check("H39", "an install with only an imported .mbox still shows topics: when no record in view carries a topic list, words that recur across at least two different subject lines become the topics (Harborline, Atlas, onboarding and the Korean 견적서) — a reply (\"Re:\") is not a second subject, so \"quote\" is not a topic; greetings, weekdays, dates, formats and one-off words are not; machine-generated titles never lend a word; the handoff and the search work on them; and as soon as any record brings its own topic the fallback is not used at all",
          fbSaved.imported == 11 && names(t8).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.sorted() == ["atlas:mail:2", "harborline:mail:3", "onboarding:mail:2", "견적서:mail:2"] && t8.first?.key == "harborline" &&
          hb8?.display == "Harborline" && hb8?.direct == 3 && hb8?.inferred == 0 && found("Follow up on the Harborline quote", t8) == "harborline" && found("견적서를 다시", t8) == "견적서" &&
          fbText.hasPrefix("Task: Follow up on the Harborline quote\n" + h3.shortLabel + " · titles are signals, not proof of completed work\n" + Dates.day(real.addingTimeInterval(-2 * 86400)) + " · Mail · Re: Harborline quote revision\n") && bareLines(fbText).count == 3 && fbText.split(separator: "\n").count == 5 && !fbText.contains("@") && !fbText.contains("body line") &&
          names(t8derived) == names(t8) && !t8derived.contains { $0.key == "quartz" || $0.key == "launch" } && names(t8feed) == "zephyr:ai:2",
          names(t8) + " // " + names(t8derived) + " // " + names(t8feed) + " // " + fbText)

    // ── data written by the Korean-language 0.4.0 build keeps working ──
    let home9 = temp.appendingPathComponent("home9", isDirectory: true), p9 = Places(home: home9)
    let oldId = "mbox:c8ce8b789e4300cc341a9f5f3a3f274f"                       // what 0.4.0 stored for Message-ID <mb1@example.com>
    write(p9.imports.appendingPathComponent("import-20261101-090000-all-mail.jsonl"),
          [json(["id": oldId, "title": "Harborline 견적 회신", "date": ago(5), "topics": [String](), "source": "Gmail Takeout 받은편지함", "locator": "mbox-export:c8ce8b789e43", "importedAt": ago(21), "kind": "mail", "via": "mbox"]),
           json(["id": "macmail:51953c03fe5c071ea34afbf6ca47dc4d", "title": "Harborline 회신 건", "date": ago(4), "topics": [String](), "source": "Mac Mail 받은편지함", "locator": "", "importedAt": ago(21), "kind": "mail", "via": "macmail"])].joined(separator: "\n") + "\n")
    let s9before = Snapshot.read(p9, now: real)
    let reimport = Importer.save(Importer.parse(gmailURL), name: "All mail", places: p9, now: real)
    let recollect = Importer.save(macParsed, name: "mac-mail", places: p9, now: real)
    let s9 = Snapshot.read(p9, now: real), t9 = Analysis.topics(s9.evidence, window: h3, enabled: all)
    let koLabelURL = temp.appendingPathComponent("export/ko-label.mbox")
    write(koLabelURL, ["From 1@xxx Mon Nov 16 10:00:00 +0000 2026", "X-Gmail-Labels: 보낸편지함,중요", "Subject: Atlas 발송", "Date: " + rfc2822(real.addingTimeInterval(-3 * 86400)), "Message-ID: <ko1@example.com>", "", "body", ""].joined(separator: "\n"))
    write(p9.manifest, json(["mail": ["collectedAt": ago(1), "coverage": "부분 수집: 최근 90일"]]))
    check("H40", "data from the Korean-language 0.4.0 build keeps working: record ids are computed exactly as before (the stored id for a known Message-ID is unchanged), so importing the same export or collecting from Mail again after the update adds only what is new; rows saved with Korean source names are read as snapshots and Mail collections as before; a Gmail label in Korean still marks Sent; a Korean \"부분\" coverage note still marks a feed partial; the Korean redaction marks of an older handoff pasted as a task are ignored like the English ones; Korean generated labels are still never topics",
          "mbox:" + Hash.hex("<mb1@example.com>") == oldId && "macmail:" + Hash.hex("<a1@mail.example>") == "macmail:51953c03fe5c071ea34afbf6ca47dc4d" && s9before.evidence.count == 2 &&
          reimport.imported == 2 && reimport.duplicates == 1 && recollect.imported == 1 && recollect.duplicates == 1 && s9.evidence.count == 5 &&
          (s9.evidence.first { $0.id == oldId }?.source) == "Gmail Takeout 받은편지함" && (s9.evidence.first { $0.id == oldId }?.provenance) == "Snapshot" && (s9before.evidence.first { $0.via == "macmail" }?.provenance) == "From Mail" &&
          (t9.first { $0.key == "harborline" }?.items.count ?? 0) == 2 && !t9.contains { $0.key.contains("받은편지함") || $0.key.contains("gmail") } &&
          (Importer.parse(koLabelURL).rows.first?["source"] as? String) == "Gmail Takeout Sent" && Manifest.read(p9.manifest).entries[.mail]?.partial == true &&
          Search.tokens("[이메일] [경로] [email] [path] Harborline 견적을") == ["harborline", "견적을", "견적"] && ["스냅샷", "가져온 자료", "ai 대화", "피드", "검토 필요", "제목 없음"].allSatisfy { Topic.isLowSignal($0) },
          "\(reimport.imported)/\(reimport.duplicates) \(recollect.imported)/\(recollect.duplicates) \(s9.evidence.count) " + names(t9) + " " + Hash.hex("<mb1@example.com>"))

    // ── the headless lookup (--aside-lookup), run as the real command in a separate process ──
    /// What the simple screen shows for this text, worked out here the way the windows do it (period and switches from
    /// the settings, the first ranked topic, Export.simple) — not through the command's own code path.
    func nativePreview(_ q: String, home h: URL, _ configure: (Preferences) -> Void = { _ in }) -> String {
        let prefs = Preferences(store: MemoryStore()); configure(prefs)
        let w = prefs.window(now: Date()).window, on = prefs.enabled
        let snapNow = Snapshot.read(Places(home: h), enabled: on)                // as the windows read from 0.5.2 on: only what the switches allow
        let list = Analysis.topics(snapNow.evidence, window: w, enabled: on), typed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let top = Search.rank(typed, topics: list).first?.topic else { return "" }
        return Export.simple(task: typed, topic: top, window: w, coverage: SourceKind.allCases.map { snapNow.coverage(for: $0, window: w, enabled: on) })
    }
    func fingerprint(_ dir: URL) -> [String] {
        var out: [String] = []
        for case let u as URL in fm.enumerator(at: dir, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator() {
            let attrs = try? fm.attributesOfItem(atPath: u.path)
            var h: UInt64 = 0xcbf29ce484222325
            if attrs?[.type] as? FileAttributeType == .typeRegular { for b in (fm.contents(atPath: u.path) ?? Data()) { h ^= UInt64(b); h = h &* 0x100000001b3 } }
            out.append(u.path + " \(attrs?[.size] ?? 0) \(attrs?[.modificationDate] ?? 0) \(attrs?[.posixPermissions] ?? 0) \(h)")
        }
        return out.sorted()
    }
    let home10 = temp.appendingPathComponent("home10", isDirectory: true)
    write(Places(home: home10).ai, "")                                  // a feed that exists and holds nothing
    let treeBefore = fingerprint(temp)
    let allOK = ["files": "ok", "ai": "ok", "mail": "ok", "imports": "ok"]
    let askQueries = [task, "atlas layout", "  Follow up on the Harborline quote \n", "견적을 다시", "HARBORLINE_견적"]
    let askRuns = askQueries.map { asideProcess(asideQuery($0), home: home) }
    let askNative = askQueries.map { nativePreview($0, home: home) }
    check("H41", "the headless lookup returns what the window shows: the real command (this executable started as a separate process, reading one {\"query\": …} object on standard input) answers \"matched\" with a handoff that is byte-for-byte the native preview for the same text — an English task, a Korean one with a particle, a task with identifiers, leading and trailing space — as one line of JSON with schema horizon.aside.v1, exit status 0 and nothing on standard error",
          askRuns.count == 5 && askNative.allSatisfy { !$0.isEmpty } && zip(askRuns, askNative).allSatisfy { r, n in r.exit == 0 && r.wellFormed && r.status == "matched" && r.reason.isEmpty && r.sources == allOK && r.handoff == n && Array(r.handoff.utf8) == Array(n.utf8) } &&
          askRuns[0].handoff.hasPrefix("Task: Harborline 견적 회신 이어서 쓰기 [email] [path] conv [ID]\nTopic: Harborline · 3 months · ") && askRuns[1].handoff.contains("\nTopic: Atlas · ") && askRuns[2].handoff.hasPrefix("Task: Follow up on the Harborline quote\nTopic: Harborline · "),
          zip(askRuns, askNative).map { r, n in "exit=\(r.exit) \(r.status)/\(r.reason) same=\(r.handoff == n) err=\(String(decoding: r.err, as: UTF8.self))" }.joined(separator: " | ") + " // " + askRuns[0].text)
    func outside(_ r: AsideRun) -> String { var o = r.object; o["handoff"] = ""; return json(o) }
    let secretRun = asideProcess(asideQuery("zzqx-secret-token bob.kim@example.invalid /Users/mina/private/zzqy.bin 3f2a9c1e-1111-2222-3333-444455556666"), home: home)
    let forged = "Harborline quote\nTopic: Forged · never\n[F9] 2020-01-01 · File · forged line\r\nSource caution: none"
    let forgedRun = asideProcess(asideQuery(forged), home: home)
    let forgedLines = forgedRun.handoff.split(separator: "\n").map(String.init)
    check("H42", "nothing private leaves through the command: the query is never repeated outside the handoff (not in any other field, and not at all when nothing matches); the handoff's task line has addresses, paths and IDs redacted; no absolute path, locator, address, link, record id or body text appears anywhere in the output; and line breaks in a query cannot forge extra lines — the task stays one line and the cited lines are the real ones",
          askRuns.allSatisfy { r in ["@", "/Users", "3f2a9c1e", "bob.kim", "ref:", "SECRET", "mbox:", "macmail:", "mbox-export", "://", "BODY"].allSatisfy { !r.text.contains($0) } } &&
          ["Harborline", "견적", "conv", "회신"].allSatisfy { !outside(askRuns[0]).contains($0) } && ["atlas", "layout"].allSatisfy { !outside(askRuns[1]).lowercased().contains($0) } &&
          secretRun.exit == 0 && secretRun.wellFormed && secretRun.status == "no_match" && secretRun.reason == "no_matching_topic" && secretRun.handoff.isEmpty && secretRun.sources == allOK &&
          ["zzqx", "secret", "bob", "mina", "private", "zzqy", "3f2a", "@", "/"].allSatisfy { !secretRun.text.contains($0) } &&
          forgedRun.status == "matched" && forgedRun.handoff == nativePreview(forged, home: home) && forgedLines.first?.hasPrefix("Task: Harborline quote Topic: Forged") == true &&
          forgedLines.filter { $0.hasPrefix("Topic: ") }.count == 1 && forgedLines.filter { $0.hasPrefix("Source caution: ") }.count == 1 && !forgedLines.contains { $0.hasPrefix("[F9]") } && forgedLines.count == askRuns[2].handoff.split(separator: "\n").count,
          outside(askRuns[0]) + " // " + secretRun.text + " // " + forgedRun.handoff)
    func padded(_ bytes: Int, marker: String = "") -> Data {
        let base = asideQuery("Harborline " + marker).count
        return asideQuery("Harborline " + marker + String(repeating: "x", count: bytes - base))
    }
    let refused: [(Data, String)] = [(Data(), "no_input"), (Data("not json at all".utf8), "not_json"), (Data("[1,2]".utf8), "not_an_object"), (Data("\"Harborline\"".utf8), "not_an_object"), (Data("{}".utf8), "no_query"),
                                     (Data("{\"q\":\"Harborline\"}".utf8), "no_query"), (Data("{\"query\":5}".utf8), "bad_query"), (Data("{\"query\":null}".utf8), "bad_query"), (Data("{\"query\":[\"Harborline\"]}".utf8), "bad_query"),
                                     (Data("{\"query\":\"  \\n \"}".utf8), "bad_query"), (Data("{\"query\":\"Harborline\",\"limit\":9}".utf8), "unknown_field"), (Data("{\"query\":\"Harborline\"}{\"query\":\"Atlas\"}".utf8), "not_json"),
                                     (Data("{\"query\":\"Harborline\"".utf8), "not_json"), (Data([0x7B, 0x22, 0x71, 0x75, 0x65, 0x72, 0x79, 0x22, 0x3A, 0x22, 0xFF, 0xFE, 0x22, 0x7D]), "not_json"),
                                     (padded(AsideLookup.maxInputBytes + 1, marker: "OVERSIZE-MARKER "), "input_too_large"), (padded(12_000, marker: "OVERSIZE-MARKER "), "input_too_large")]
    let refusedRuns = refused.map { asideProcess($0.0, home: home) }
    let refusedNoHome = asideProcess(Data("{}".utf8), home: home3)
    let atLimit = padded(AsideLookup.maxInputBytes), atLimitRun = asideProcess(atLimit, home: home)
    let atLimitQuery = ((try? JSONSerialization.jsonObject(with: atLimit)) as? [String: String])?["query"] ?? ""
    check("H43", "invalid input is refused before anything is read: no input, text that is not JSON, an array or a bare string, an object without \"query\", a query that is not a string or is blank, an extra member, two objects, a cut-off object, bytes that are not UTF-8, and anything over 8 KiB (8,193 and 12,000 bytes) all give status \"invalid\" with a fixed reason word, an empty handoff, no source states and exit status 2 — with nothing of the input repeated; exactly 8,192 bytes is still accepted and answered like the window",
          zip(refusedRuns, refused).allSatisfy { r, want in r.exit == 2 && r.wellFormed && r.status == "invalid" && r.reason == want.1 && r.handoff.isEmpty && r.sources.isEmpty } &&
          refusedRuns.allSatisfy { !$0.text.contains("OVERSIZE") && !$0.text.contains("Harborline") && !$0.text.contains("xxxx") } && refusedNoHome.status == "invalid" && refusedNoHome.reason == "no_query" && refusedNoHome.exit == 2 &&
          atLimit.count == 8192 && AsideLookup.maxInputBytes == 8192 && atLimitRun.exit == 0 && atLimitRun.status == "matched" && atLimitRun.handoff == nativePreview(atLimitQuery, home: home) && atLimitRun.handoff.hasPrefix("Task: Harborline xxxx"),
          zip(refusedRuns, refused).map { r, want in "\(want.1)→\(r.status)/\(r.reason)/\(r.exit)" }.joined(separator: " ") + " // atLimit \(atLimit.count) \(atLimitRun.status)/\(atLimitRun.reason)")
    let nothingRun = asideProcess(asideQuery("Harborline"), home: home3), emptyRun = asideProcess(asideQuery("Harborline"), home: home10)
    let oldRun = asideProcess(asideQuery("atlas"), home: home2), linkRun = asideProcess(asideQuery("atlas"), home: home2, ["source.files": "NO"])
    let offRun = asideProcess(asideQuery("Harborline"), home: home, ["source.files": "NO", "source.ai": "NO", "source.mail": "NO", "source.imports": "NO"])
    let missRun = asideProcess(asideQuery("zzqx nosuchtopic"), home: home), badLinesRun = asideProcess(asideQuery("Harborline"), home: home4)
    check("H44", "\"nothing to search\" is told apart from \"nothing found\": with no feed files at all the answer is \"unavailable\" (sources_missing, every feed \"missing\"), with only an empty feed \"unavailable\" (no_records), with only an unreadable feed (a link) \"unavailable\" (sources_unreadable), with every source switched off \"unavailable\" (all_sources_off) — exit status 3 each; when records were read but none is in the period or none fits the query the answer is \"no_match\" with exit 0, and each source's state (ok, empty, missing, unreadable, off) is reported either way; a feed with bad lines still answers from its good ones",
          nothingRun.exit == 3 && nothingRun.wellFormed && nothingRun.status == "unavailable" && nothingRun.reason == "sources_missing" && nothingRun.sources == ["files": "missing", "ai": "missing", "mail": "missing", "imports": "empty"] && nothingRun.handoff.isEmpty &&
          emptyRun.exit == 3 && emptyRun.status == "unavailable" && emptyRun.reason == "sources_missing" && emptyRun.sources == ["files": "missing", "ai": "empty", "mail": "missing", "imports": "empty"] &&
          asideProcess(asideQuery("Harborline"), home: home10, ["source.files": "NO", "source.mail": "NO"]).reason == "no_records" &&
          oldRun.exit == 0 && oldRun.wellFormed && oldRun.status == "no_match" && oldRun.reason == "no_topics_in_period" && oldRun.sources == ["files": "ok", "ai": "empty", "mail": "unreadable", "imports": "empty"] && oldRun.handoff.isEmpty &&
          linkRun.exit == 3 && linkRun.status == "unavailable" && linkRun.reason == "sources_unreadable" && linkRun.sources == ["files": "off", "ai": "empty", "mail": "unreadable", "imports": "empty"] &&
          offRun.exit == 3 && offRun.status == "unavailable" && offRun.reason == "all_sources_off" && Set(offRun.sources.values) == ["off"] && offRun.handoff.isEmpty &&
          missRun.exit == 0 && missRun.status == "no_match" && missRun.reason == "no_matching_topic" && missRun.sources == allOK &&
          badLinesRun.status == "matched" && badLinesRun.handoff == nativePreview("Harborline", home: home4) && badLinesRun.handoff.contains("Source caution: ") && badLinesRun.sources == ["files": "missing", "ai": "missing", "mail": "ok", "imports": "empty"],
          [nothingRun, emptyRun, oldRun, linkRun, offRun, missRun, badLinesRun].map { $0.text.trimmingCharacters(in: .newlines) }.joined(separator: " // "))
    let mailOffRun = asideProcess(asideQuery("Harborline 견적"), home: home, ["source.mail": "NO"]), mailOffNative = nativePreview("Harborline 견적", home: home) { $0.set(.mail, false) }
    let aiOffRun = asideProcess(asideQuery("Harborline 견적"), home: home, ["source.ai": "NO"]), importsOffRun = asideProcess(asideQuery("Harborline 견적"), home: home, ["source.imports": "NO"])
    let northOn = asideProcess(asideQuery("northfield"), home: home), northMailOff = asideProcess(asideQuery("northfield"), home: home, ["source.mail": "NO"])
    let allOnRun = asideProcess(asideQuery("Harborline 견적"), home: home)
    check("H45", "the saved source switches are honoured exactly as in the windows, and from 0.5.2 they decide what is opened: with Mail off the command's handoff is the native preview with Mail off — no mail line, mail reported \"off\" — and the imports are skipped whole (an import file can mix chat and mail records, so none is opened: no imported chat title appears, imports are reported \"off\", and the caution says \"Imports: skipped\" rather than nothing); likewise with AI chats off (the feed's own mail line stays, no imported mail); with Imports off the caution does not mention imports at all; with everything on the imported snapshots are there as before; a topic that exists only in mail (Northfield) is matched by default and is \"no_match\" with Mail off",
          mailOffRun.status == "matched" && !mailOffNative.isEmpty && mailOffRun.handoff == mailOffNative && mailOffRun.handoff != allOnRun.handoff && !mailOffRun.handoff.contains(" · Mail · ") && mailOffRun.sources == ["files": "ok", "ai": "ok", "mail": "off", "imports": "off"] &&
          mailOffRun.handoff.contains(" · AI · Harborline 견적 검토\n") && !mailOffRun.handoff.contains("가격 협상") && !mailOffRun.handoff.contains("계약 조항") && mailOffRun.handoff.contains("Source caution: AI chats: stale, partial · Imports: skipped\n") &&
          aiOffRun.handoff == nativePreview("Harborline 견적", home: home) { $0.set(.ai, false) } && !aiOffRun.handoff.contains(" · AI · ") && aiOffRun.handoff.contains(" · Mail · RE: Harborline quote\n") && !aiOffRun.handoff.contains("견적 회신") && !aiOffRun.handoff.contains("회신 건") &&
          aiOffRun.sources == ["files": "ok", "ai": "off", "mail": "ok", "imports": "off"] && aiOffRun.handoff.contains("Source caution: Mail: partial · Imports: skipped\n") &&
          importsOffRun.handoff == nativePreview("Harborline 견적", home: home) { $0.set(.imports, false) } && importsOffRun.sources["imports"] == "off" && !importsOffRun.handoff.contains("snapshot") && !importsOffRun.handoff.contains("Imports") &&
          allOnRun.handoff == nativePreview("Harborline 견적", home: home) && allOnRun.handoff.contains("Imports: snapshot") && allOnRun.handoff.contains(" · AI · Harborline 가격 협상 준비") && allOnRun.sources == allOK &&
          northOn.status == "matched" && northOn.handoff.hasPrefix("Task: northfield\n3 months to ") && northOn.handoff.contains(" · Mail · Northfield ") && northMailOff.status == "no_match" && northMailOff.reason == "no_matching_topic" && northMailOff.exit == 0,
          mailOffRun.text + " // " + aiOffRun.text + " // " + importsOffRun.text + " // " + northMailOff.text)
    let sixRun = asideProcess(asideQuery("northfield cap"), home: home, ["windowMonths": "6"]), threeRun = asideProcess(asideQuery("northfield cap"), home: home)
    let dayA = Dates.day(cStart), dayB = Dates.day(cEnd)
    let customRun = asideProcess(asideQuery("Harborline 견적"), home: home, ["windowCustom": "YES", "customStart": dayA, "customEnd": dayB, "windowMonths": "6"])
    let customAtlas = asideProcess(asideQuery("atlas layout"), home: home, ["windowCustom": "YES", "customStart": dayA, "customEnd": dayB])
    let reversedRun = asideProcess(asideQuery("northfield cap"), home: home, ["windowCustom": "YES", "customStart": dayB, "customEnd": dayA, "windowMonths": "6"])
    let garbageRun = asideProcess(asideQuery("northfield cap"), home: home, ["windowCustom": "YES", "customStart": "soon", "customEnd": dayB, "windowMonths": "5"])
    check("H46", "the saved period is honoured exactly as in the windows: 6 months brings in the older Northfield chat that 3 months leaves out, and each handoff names its period; a saved custom period (both days included) is used and stated, and a topic with nothing in those days is \"no_match\"; a saved custom period that is reversed or unreadable is not used — the 6- or 3-month preset is, as the window does — and a stored length that is neither 3 nor 6 reads as 3",
          sixRun.handoff == nativePreview("northfield cap", home: home) { $0.months = 6 } && sixRun.handoff.contains("\nTopic: Northfield · 6 months · ") && sixRun.handoff.contains(" · AI · Northfield cap 정리") &&
          threeRun.handoff == nativePreview("northfield cap", home: home) && threeRun.handoff.hasPrefix("Task: northfield cap\n3 months to " + Dates.day(real) + " · titles are signals, not proof of completed work") && !threeRun.handoff.contains("Northfield cap 정리") && threeRun.handoff != sixRun.handoff &&
          customRun.handoff == nativePreview("Harborline 견적", home: home) { $0.months = 6; $0.setCustom(start: cStart, end: cEnd) } && customRun.handoff.contains("\nTopic: Harborline · Custom · " + dayA + " – " + dayB + " (both days included)\n") && customRun.handoff.contains("Signals: 4 records (File 2 · AI 1 · Mail 1)") &&
          customAtlas.status == "no_match" && customAtlas.reason == "no_matching_topic" &&
          reversedRun.handoff == sixRun.handoff && reversedRun.status == "matched" && garbageRun.handoff == threeRun.handoff && garbageRun.status == "matched",
          sixRun.text + " // " + customRun.text + " // " + reversedRun.status + " " + garbageRun.status)
    let treeAfter = fingerprint(temp)
    check("H47", "the command changes nothing: after every run above (about fifty, matched, refused and unavailable alike) each file and folder of the synthetic homes is as it was — same names, sizes, dates, permissions and contents — and no file was added anywhere; the settings were given on the command line, so none was read from or written to anybody's saved preferences",
          !treeBefore.isEmpty && treeBefore == treeAfter && asideSettings().count == 16 && asideSettings(["source.mail": "NO"]).joined(separator: " ").contains("-source.mail NO"),
          "\(treeBefore.count) → \(treeAfter.count): " + Set(treeAfter).symmetricDifference(Set(treeBefore)).prefix(4).joined(separator: " | "))

    // ── 0.5.2: a switch decides what is opened — watched at the reader's own dispatch (Reader.probe) ──
    let trace = ReadTrace(); trace.start()
    let fullSnap = Snapshot.read(places, now: real)
    let fullEvents = trace.events
    let importFilesNow = ((try? fm.contentsOfDirectory(atPath: places.imports.path)) ?? []).filter { $0.hasSuffix(".jsonl") }.count
    func key(_ e: Evidence) -> String { e.origin.rawValue + "|" + e.type.rawValue + "|" + e.id + "|" + e.title }
    var gateFailures: [String] = [], comboAnswers: [String] = []
    for mask in 0..<16 {
        let on = Set(SourceKind.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map { $0.element })
        let name = on.isEmpty ? "none" : SourceKind.allCases.filter(on.contains).map { $0.rawValue }.joined(separator: "+")
        trace.reset()
        let g = Snapshot.read(places, enabled: on, now: real)
        let ev = trace.events
        let wantImports = on.isSuperset(of: [.imports, .ai, .mail]), wantManifest = !on.isDisjoint(with: [.files, .ai, .mail])
        let allowed = Set(fullSnap.evidence.filter { $0.isOn(on) && ($0.origin != .imports || wantImports) }.map(key))
        var why: [String] = []
        if trace.touched(places.preindex) != (on.contains(.files) ? 1 : 0) { why.append("preindex") }
        if trace.touched(places.ai) != (on.contains(.ai) ? 1 : 0) { why.append("ai.jsonl") }
        if trace.touched(places.mail) != (on.contains(.mail) ? 1 : 0) { why.append("mail.jsonl") }
        if trace.touched(places.manifest) != (wantManifest ? 1 : 0) { why.append("manifest") }
        if trace.under(places.imports) != (wantImports ? 1 + importFilesNow : 0) { why.append("imports \(trace.under(places.imports))") }
        if ev.count != (on.contains(.files) ? 1 : 0) + (on.contains(.ai) ? 1 : 0) + (on.contains(.mail) ? 1 : 0) + (wantManifest ? 1 : 0) + (wantImports ? 1 + importFilesNow : 0) { why.append("other paths: \(ev.count)") }
        if on.isEmpty && !ev.isEmpty { why.append("all off but something was opened") }
        if !g.evidence.allSatisfy({ $0.isOn(on) }) || Set(g.evidence.map(key)) != allowed { why.append("kept records") }
        if !SourceKind.allCases.allSatisfy({ k in g.coverage[k]?.gated == !(k == .imports ? wantImports : on.contains(k)) }) { why.append("gated flags") }
        // the command's own decision, in this process with the same trace, and the real command as a separate process: the same answer
        let prefs = Preferences(store: MemoryStore()); for k in SourceKind.allCases { prefs.set(k, on.contains(k)) }
        trace.reset()
        let answer = AsideLookup.answer(input: asideQuery("Harborline 견적"), places: places, preferences: prefs)
        let evAnswer = trace.events
        if trace.touched(places.preindex) != (on.contains(.files) ? 1 : 0) || trace.touched(places.ai) != (on.contains(.ai) ? 1 : 0) || trace.touched(places.mail) != (on.contains(.mail) ? 1 : 0) || trace.touched(places.manifest) != (wantManifest ? 1 : 0) || trace.under(places.imports) != (wantImports ? 1 + importFilesNow : 0) || (on.isEmpty && !evAnswer.isEmpty) { why.append("lookup opened \(evAnswer.count)") }
        var changes: [String: String] = [:]
        for k in SourceKind.allCases { changes["source." + k.rawValue] = on.contains(k) ? "YES" : "NO" }
        let run = asideProcess(asideQuery("Harborline 견적"), home: home, changes)
        if run.text != AsideLookup.json(answer) + "\n" || run.exit != answer.exitCode { why.append("process answer differs") }
        if answer.sources["imports"] != (wantImports ? "ok" : "off") || SourceKind.allCases.filter({ $0 != .imports }).contains(where: { answer.sources[$0.rawValue] != (on.contains($0) ? "ok" : "off") }) { why.append("source states \(answer.sources)") }
        if on.isEmpty && !(answer.status == .unavailable && answer.reason == "all_sources_off" && answer.handoff.isEmpty) { why.append("all-off answer") }
        comboAnswers.append(name + "=" + answer.status.rawValue)
        if !why.isEmpty { gateFailures.append(name + ": " + why.joined(separator: ", ")) }
    }
    trace.reset()
    let refusedTrace = AsideLookup.answer(input: Data("{}".utf8), places: places, preferences: Preferences(store: MemoryStore()))
    let refusedEvents = trace.events
    check("H59", "a switch decides what is opened, in all 16 combinations of the four switches, watched at the reader's own dispatch (the place every source file is lstat'ed, opened and read, and the place the imports folder is looked for and listed): the preindex, ai.jsonl and mail.jsonl are each reached for exactly once when their own switch is on and never when it is off; the imports folder and its files only while Imports, AI chats and Mail are all on; the manifest only while at least one feed is on; with every switch off nothing at all — and nothing outside these paths in any case. What is kept is exactly the records the switches allow. The lookup command decides the same way (traced in this process), and the real command, run as a separate process with the same switches, gives the identical answer each time; invalid input still reads nothing",
          gateFailures.isEmpty && comboAnswers.count == 16 && fullEvents.count == 5 + importFilesNow && importFilesNow >= 5 && fullSnap.evidence.contains { $0.origin == .imports && $0.type == .mail } && fullSnap.evidence.contains { $0.origin == .imports && $0.type == .ai } &&
          refusedTrace.status == .invalid && refusedEvents.isEmpty,
          gateFailures.joined(separator: " | ") + " // " + comboAnswers.joined(separator: " "))
    let mailOffSet: Set<SourceKind> = [.files, .ai, .imports]
    trace.reset()
    let cut = fullSnap.restricted(to: mailOffSet)
    let cutEvents = trace.events
    let gatedRead = Snapshot.read(places, enabled: mailOffSet, now: real)
    let cutCov = SourceKind.allCases.map { cut.coverage(for: $0, window: h3, enabled: mailOffSet) }, gatedCov = SourceKind.allCases.map { gatedRead.coverage(for: $0, window: h3, enabled: mailOffSet) }
    let back = Snapshot.read(places, enabled: all, now: real)
    let emptyHomeCov = Snapshot.read(Places(home: home3), enabled: all, now: real).coverage(for: .imports, window: h3, enabled: all)
    let importsOffCov = Snapshot.read(places, enabled: [.files, .ai, .mail], now: real).coverage(for: .imports, window: h3, enabled: [.files, .ai, .mail])
    check("H60", "turning a switch off empties it from memory at once and reads nothing: restricting a full snapshot to \"Mail off\" touches no file, leaves no mail record and no imported record at all (imports can mix chat and mail, so they go whole), and is the same as reading afresh with Mail off; it no longer covers \"everything on\", so turning Mail back on is a new read, which brings every record back. Skipped imports are told apart from absent ones and from a switch that is off: \"Skipped, not opened — …\" (the lookup's fixed state: off; the caution: \"Imports: skipped\"), \"Nothing imported yet\" (state: empty), \"Off — not used in the results\"; the wording states the fact and does not tell anyone to turn a source on",
          cutEvents.isEmpty && !cut.evidence.isEmpty && cut.evidence.allSatisfy { $0.type != .mail && $0.origin != .imports && $0.origin != .mail } && Set(cut.evidence.map(key)) == Set(gatedRead.evidence.map(key)) &&
          zip(cutCov, gatedCov).allSatisfy { $0.summary == $1.summary } && cut.coverage[.imports]?.gated == true && cut.coverage[.mail]?.gated == true && cut.coverage[.imports]?.rows.isEmpty == true && cut.importFiles == 0 &&
          cut.covers(mailOffSet) && !cut.covers(all) && fullSnap.covers(all) && fullSnap.covers(mailOffSet) && Set(back.evidence.map(key)) == Set(fullSnap.evidence.map(key)) && back.evidence.count == fullSnap.evidence.count &&
          cutCov[3].summary.hasPrefix("Skipped, not opened — an import file can mix AI chat and mail records, so none is opened while AI chats or Mail is off") && AsideLookup.state(cutCov[3]) == "off" && cutCov[2].summary == "Off — not used in the results" &&
          (Export.caption(cutCov) ?? "").hasSuffix("Imports: skipped") && emptyHomeCov.summary == "Nothing imported yet" && AsideLookup.state(emptyHomeCov) == "empty" && importsOffCov.summary == "Off — not used in the results" && !(Export.caption([importsOffCov]) ?? "").contains("Imports") &&
          !cutCov[3].summary.lowercased().contains("turn ") && !cutCov[3].summary.lowercased().contains("switch on") && !cutCov[3].summary.lowercased().contains("enable"),
          "\(cutEvents.count) events; " + cutCov.map { $0.summary }.joined(separator: " || ") + " // " + (Export.caption(cutCov) ?? "nil"))
    // switching off either of the two types an import file can mix: both types of imported record go, as in a cold start of the command
    var toggleFailures: [String] = []
    for offKind in [SourceKind.ai, .mail] {
        let on = all.subtracting([offKind])
        trace.reset()
        let warm = fullSnap.restricted(to: on)                                   // the dashboard's snapshot the moment the switch is turned off
        if !trace.events.isEmpty { toggleFailures.append("\(offKind.rawValue) off: read something") }
        if warm.evidence.contains(where: { $0.origin == .imports }) || (warm.coverage[.imports]?.rows.isEmpty == false) { toggleFailures.append("\(offKind.rawValue) off: imported records kept (" + Set(warm.evidence.filter { $0.origin == .imports }.map { $0.type.rawValue }).sorted().joined(separator: ",") + ")") }
        if warm.evidence.contains(where: { $0.type.governing == offKind }) { toggleFailures.append("\(offKind.rawValue) off: its own records kept") }
        let prefs = Preferences(store: MemoryStore()); prefs.set(offKind, false)
        let cold = AsideLookup.answer(input: asideQuery("Harborline 견적"), places: places, preferences: prefs, now: real)
        let warmText = AsideLookup.handoff(query: "Harborline 견적", view: AsideLookup.view(warm, preferences: prefs, now: real)) ?? ""
        if cold.status != .matched || warmText != cold.handoff || warmText.isEmpty { toggleFailures.append("\(offKind.rawValue) off: differs from a cold start") }
        if Set(warm.evidence.map(key)) != Set(Snapshot.read(places, enabled: on, now: real).evidence.map(key)) { toggleFailures.append("\(offKind.rawValue) off: not the cold read's records") }
        let again = Snapshot.read(places, enabled: all, now: real)               // the switch turned on again: a new read
        if warm.covers(all) || Set(again.evidence.map(key)) != Set(fullSnap.evidence.map(key)) || !again.evidence.contains(where: { $0.origin == .imports && $0.type == .ai }) || !again.evidence.contains(where: { $0.origin == .imports && $0.type == .mail }) { toggleFailures.append("\(offKind.rawValue) on again: not everything back") }
    }
    check("H62", "an import file can mix chat and mail records, so turning off either AI chats or Mail removes BOTH kinds of imported record from memory at once — the list of records and the per-source coverage agree — without reading anything; what is left, and the handoff made from it, is exactly what a cold start of the lookup command gives with that switch off; turning the switch on again is a new read and brings both kinds of imported record back",
          toggleFailures.isEmpty && fullSnap.evidence.filter { $0.origin == .imports && $0.type == .ai }.count >= 2 && fullSnap.evidence.filter { $0.origin == .imports && $0.type == .mail }.count >= 2,
          toggleFailures.joined(separator: " | "))
    // the fictional example: in memory only, never part of anything real
    let treeBeforeExample = fingerprint(temp)
    trace.reset()
    let fiction = FictionalExample.make(now: real)
    let fictionText = fiction.topics.first.map { Export.simple(task: "Follow up on the Harborline quote", topic: $0, window: fiction.window, coverage: []) } ?? ""
    let fictionEvents = trace.events
    let realAnswer = AsideLookup.answer(input: asideQuery("Harborline delivery plan"), places: places, preferences: Preferences(store: MemoryStore()))
    let emptyAnswer = AsideLookup.answer(input: asideQuery("Harborline quote"), places: Places(home: home3), preferences: Preferences(store: MemoryStore()))
    check("H61", "the fictional example is made in memory and stays apart: building it and its preview reaches for no file (reader trace empty) and changes nothing on disk; it is one made-up topic, Harborline, with two file, two chat and two mail titles dated within the last three weeks, and its preview is the ordinary Export.simple text (task line, topic, signals with the \"not proof\" caveat, six numbered dated lines); none of it can reach the lookup command — on an empty home the command still answers \"unavailable\" with an empty handoff, and on the synthetic home a title that exists only in the example is not in its answer",
          fictionEvents.isEmpty && fingerprint(temp) == treeBeforeExample && fiction.topics.count == 1 && fiction.topics[0].key == FictionalExample.key && fiction.topics[0].display == "Harborline" && fiction.topics[0].items.count == 6 && fiction.topics[0].types == [.file, .ai, .mail] &&
          fiction.topics[0].items.allSatisfy { $0.evidence.id.hasPrefix("fictional-example-") && $0.evidence.source == "Fictional example" && $0.evidence.locator.isEmpty && $0.direct && real.timeIntervalSince($0.evidence.date) <= 21 * 86400 } &&
          fictionText.hasPrefix("Task: Follow up on the Harborline quote\nTopic: Harborline · " + h3.dayLabel + "\nSignals: 6 records (File 2 · AI 2 · Mail 2) · 6 direct / 0 inferred — title counts are signals, not proof of completed work\n[F1] " + Dates.day(real.addingTimeInterval(-3 * 86400)) + " · File · Harborline Q3 quote.xlsx\n") &&
          citeLines(fictionText).count == 6 && fictionText.contains(" · AI · Harborline quote review notes\n") && fictionText.contains(" · Mail · Re: Harborline quote revision\n") && !fictionText.contains("Source caution") && claimsNoOutcome(fictionText) &&
          emptyAnswer.status == .unavailable && emptyAnswer.handoff.isEmpty && !AsideLookup.json(emptyAnswer).contains("Harborline") && realAnswer.status == .matched && !realAnswer.handoff.contains("delivery plan.pdf") && !realAnswer.handoff.contains("pricing questions") && !AsideLookup.json(realAnswer).lowercased().contains("fictional"),
          "\(fictionEvents.count) events // " + fictionText + " // " + AsideLookup.json(emptyAnswer))
    trace.stop()

    // ── 0.5.3: "Read Sources" and Mail — the decision, with the Mac's side mocked ──
    var stepFailures: [String] = []
    for mask in 0..<16 {
        let on = Set(SourceKind.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map { $0.element })
        let m = MailMock(); m.set(running: true)
        let step = MailAdapter.step(enabled: on, underway: false, isRunning: m.side.isRunning)
        let allOn = on.isSuperset(of: [.imports, .ai, .mail])
        if allOn ? !(step == .ask && m.counts.running == 1) : !(step == .skip("Imports, AI chats and Mail are not all switched on") && m.counts.running == 0) { stepFailures.append("mask \(mask): \(step) asked \(m.counts.running)") }
        if MailAdapter.mayKeep(on) != allOn { stepFailures.append("mask \(mask): mayKeep") }
    }
    let mailQuiet = MailMock(); mailQuiet.set(running: false)
    let stepNotRunning = MailAdapter.step(enabled: all, underway: false, isRunning: mailQuiet.side.isRunning)
    let busyMock = MailMock(); busyMock.set(running: true)
    let stepUnderway = MailAdapter.step(enabled: all, underway: true, isRunning: busyMock.side.isRunning)
    func outcome(_ configure: (MailMock) -> Void) -> (MailAdapter.Outcome, Int, (running: Int, permission: Int, run: Int, onMain: Int)) {
        let m = MailMock(); configure(m)
        let got = MailAdapter.collect(isRunning: m.side.isRunning, permission: m.side.permission, run: m.side.run)
        return (got.outcome, got.rows.count, m.counts)
    }
    let oDenied = outcome { $0.set(running: true, permission: -1743) }, oQuit = outcome { $0.set(running: false) }, oTimeout = outcome { $0.set(running: true, reply: .some(nil), error: -1712) }
    let oBlocked = outcome { $0.set(running: true, reply: .some(nil), error: MailAdapter.refusedOnMainThread) }
    let oGood = outcome { $0.set(running: true, reply: MailMock.reply([("I", "<k1@mail.example>", real.addingTimeInterval(-86400), "Harborline note"), ("S", "<k2@mail.example>", real.addingTimeInterval(-2 * 86400), "Atlas reply")])) }
    check("H63", "what \"Read Sources\" does about Mail is decided before anything of Mail is touched: in the 15 switch combinations where Imports, AI chats and Mail are not all on, Mail is left out with that reason and not even \"is Mail running?\" is asked; the same when a collection is already under way; with all three on and Mail not running it is left out and Mail is not opened; only with all three on and Mail running is the person asked. What was collected may be kept only while all three are still on. After a yes: macOS refusing gives \"Permission denied\" and the script is not run; Mail having quit gives \"not running\" with nothing asked of macOS; a timeout and a refused main-thread call are reported as they are; a good answer becomes rows. The script itself now stops, rather than starts Mail, when Mail is not running",
          stepFailures.isEmpty && stepNotRunning == .skip("Mail is not running, and Horizon never opens it") && mailQuiet.counts == (1, 0, 0, 0) && stepUnderway == .skip("a Mail collection is already under way") && busyMock.counts.running == 0 &&
          oDenied.0 == .denied && oDenied.2.run == 0 && oDenied.2.permission == 1 && oQuit.0 == .notRunning && oQuit.2.permission == 0 && oQuit.2.run == 0 && oTimeout.0 == .unavailable("Mail did not answer in time (timed out)") &&
          oBlocked.0 == .unavailable("not asked (the request would have blocked the window)") && oGood.0 == .collected(inbox: 1, sent: 1, inboxTotal: 1, sentTotal: 1, skipped: 0) && oGood.1 == 2 && oGood.2.run == 1 &&
          MailAdapter.script(cap: 200).hasPrefix("if application id \"com.apple.mail\" is not running then error number -600\n") && MailAdapter.helper == "/usr/bin/osascript",
          stepFailures.joined(separator: " | ") + " \(stepNotRunning) \(stepUnderway) \(oDenied.0) \(oQuit.0) \(oTimeout.0) \(oBlocked.0) \(oGood.0)")
    // the helper process: the system's script runner, given tiny fixed scripts that address no app at all
    let onMain = MailAdapter.osascript("return 1", timeout: 5)
    var helperText: (reply: String?, error: Int) = (nil, 0), helperDenied: (reply: String?, error: Int) = (nil, 0), helperQuit: (reply: String?, error: Int) = (nil, 0), helperSlow: (reply: String?, error: Int) = (nil, 0), slowTook = 0.0
    let helperDone = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async {
        helperText = MailAdapter.osascript("set sep to character id 31\nreturn \"I\" & sep & \"<x@y>\" & sep & \"한글 제목\" & linefeed & \"second line\"", timeout: 10)
        helperDenied = MailAdapter.osascript("error number -1743", timeout: 10)
        helperQuit = MailAdapter.osascript("error number -600", timeout: 10)
        let began = Date()
        helperSlow = MailAdapter.osascript("delay 8\nreturn \"late\"", timeout: 0.6)
        slowTook = Date().timeIntervalSince(began)
        helperDone.signal()
    }
    let helperFinished = helperDone.wait(timeout: .now() + 30) == .success
    let parsedDenied = MailAdapter.helperResult(status: 1, timedOut: false, output: Data(), errors: Data("0:5: execution error: Mail got an error: Not authorized to send Apple events to Mail. (-1743)\n".utf8))
    let parsedOdd = MailAdapter.helperResult(status: 1, timedOut: false, output: Data(), errors: Data("something else went wrong".utf8)), parsedGood = MailAdapter.helperResult(status: 0, timedOut: false, output: Data("a\nb\n".utf8), errors: Data())
    check("H64", "the script runs in a helper process, never in the app and never on the main thread: asked on the main thread the helper refuses at once and starts nothing; off it, the system's script runner gets the script on standard input and its answer comes back intact (the separator character, Korean text and line breaks included); an AppleScript error number comes back as that number (-1743 refused, -600 not running); and a script that does not answer is stopped when the time is up and reported as a timeout, well before it would have finished",
          onMain.reply == nil && onMain.error == MailAdapter.refusedOnMainThread && helperFinished && helperText.reply == "I\u{1F}<x@y>\u{1F}한글 제목\nsecond line" && helperText.error == 0 &&
          helperDenied.reply == nil && helperDenied.error == -1743 && helperQuit.error == -600 && helperSlow.reply == nil && helperSlow.error == -1712 && slowTook < 4 &&
          parsedDenied.reply == nil && parsedDenied.error == -1743 && parsedOdd.error == 0 && parsedOdd.reply == nil && parsedGood.reply == "a\nb" && MailAdapter.helperResult(status: 0, timedOut: true, output: Data("x".utf8), errors: Data()).error == -1712,
          "main=\(onMain) text=\(String(describing: helperText.reply)) denied=\(helperDenied.error) quit=\(helperQuit.error) slow=\(helperSlow.error) in \(slowTook)s")

    // ── the shared window background: a material, or a plain plate when macOS asks for less transparency ──
    // The app's reading of the setting is replaced here; the setting itself is never touched.
    let liveReduce = WindowBackdrop.reduceTransparency
    var asksLess = false, askedTimes = 0
    WindowBackdrop.reduceTransparency = { askedTimes += 1; return asksLess }
    let said = { NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil) }
    func look(_ b: WindowBackdrop) -> String { (b.showsThrough ? "material" : "plain") + " effectHidden=\(b.effect.isHidden) plateHidden=\(b.plate.isHidden)" }
    let pane = WindowBackdrop(), pane2 = WindowBackdrop()
    let over = NSView(); pane.addSubview(over)                          // what a window lays on it
    let made = look(pane)
    asksLess = true; let unsaid = look(pane)                            // the answer changed but macOS has not said so: nothing polls
    said(); let less = [look(pane), look(pane2)]
    asksLess = false; said(); let more = [look(pane), look(pane2)]
    autoreleasepool { let gone = WindowBackdrop(); _ = gone.showsThrough }       // one that is let go stops listening
    let askedBefore = askedTimes; said(); let askedBy = askedTimes - askedBefore
    // the window it is put into follows (this window is never put on screen)
    func frame(_ w: NSWindow) -> String { "opaque=\(w.isOpaque) clear=\(w.backgroundColor == NSColor.clear) standard=\(w.backgroundColor == NSColor.windowBackgroundColor) alpha=\(w.alphaValue)" }
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled, .closable], backing: .buffered, defer: true)
    host.isReleasedWhenClosed = false
    let born = frame(host)
    host.contentView = pane; let attached = frame(host)
    asksLess = true; said(); let hostLess = frame(host)
    asksLess = false; said(); let hostMore = frame(host)
    asksLess = true; let late = WindowBackdrop(); host.contentView = late; let attachedLess = frame(host)      // attached while less transparency is asked for
    asksLess = false; said()
    host.isOpaque = false; host.backgroundColor = .clear; host.alphaValue = 0.5; said(); let putRight = frame(host)     // whatever it was made, it is set right
    let hostWants = (material: "opaque=true clear=false standard=true alpha=1.0", plain: "opaque=true clear=false standard=true alpha=1.0")
    WindowBackdrop.reduceTransparency = liveReduce
    check("H65", "both windows share one background: a real NSVisualEffectView (sidebar material, blended behind the window, following the window's active state) with the window's content laid over it, not inside it; when macOS says its display options changed and \"Reduce transparency\" is on, the material is hidden and a plain plate shown, and back again when it is off — one of the two, never both, in every background at once, only when macOS says so, and a background that is let go stops listening; the window it is in is, in both states, at alpha 1, opaque and in the standard window colour — set when the background is attached (also with less transparency already asked for) and on each change, even if something had made the window clear, not opaque or faint",
          pane.subviews.count == 3 && pane.subviews[0] === pane.plate && pane.subviews[1] === pane.effect && pane.subviews[2] === over && !over.isDescendant(of: pane.effect) &&
          pane.effect.material == .sidebar && pane.effect.blendingMode == .behindWindow && pane.effect.state == .followsWindowActiveState && pane.plate.isOpaque &&
          made == "material effectHidden=false plateHidden=true" && unsaid == made && less == Array(repeating: "plain effectHidden=true plateHidden=false", count: 2) && more == [made, made] && askedBy == 2 &&
          born == hostWants.plain && attached == hostWants.material && hostLess == hostWants.plain && hostMore == hostWants.material && attachedLess == hostWants.plain && putRight == hostWants.material && frame(host) == hostWants.material,
          "made=\(made) unsaid=\(unsaid) less=\(less) more=\(more) askedBy=\(askedBy) born=\(born) attached=\(attached) hostLess=\(hostLess) hostMore=\(hostMore) attachedLess=\(attachedLess) putRight=\(putRight) end=\(frame(host))")

    // ── the shared look: this Mac's own regular and small metrics, a standard toolbar, lists in Finder's list-view density ──
    let sysFamily = NSFont.systemFont(ofSize: NSFont.systemFontSize).familyName
    let fontsSaid = [Style.body, Style.caption, Style.headline].map { "\($0.pointSize)" + (NSFontManager.shared.weight(of: $0) > 5 ? " heavy" : "") + ($0.familyName == sysFamily ? "" : " OTHER FAMILY") }
    let native = NSTableView(), styled = NSTableView(); Style.list(styled)
    let listSaid = "inset=\(styled.style == .inset) row=\(styled.rowHeight) spacing=\(styled.intercellSpacing.width)x\(styled.intercellSpacing.height) striped=\(styled.usesAlternatingRowBackgroundColors) grid=\(styled.gridStyleMask.isEmpty) one=\(!styled.allowsMultipleSelection)"
    let narrow = Style.column("signal", "Direct / Inferred", width: 10), wide = Style.column("title", "Title", width: 140, flexible: true)
    let lead = Style.cell(NSUserInterfaceItemIdentifier("topic"), primary: true), plainCell = Style.cell(NSUserInterfaceItemIdentifier("types"), primary: false)
    let wrapped = Style.label("A caption", Style.caption, .secondaryLabelColor)
    let barButton = NSButton(title: "Simple View", target: nil, action: nil), barOther = NSButton(title: "Read Sources", target: nil, action: nil)
    barOther.toolTip = "Reads again"
    let strip = WindowToolbar(name: "SelfTest", entries: [.init("back", "Simple View", barButton, navigational: true), .space, .init("read", "Read Sources", barOther)])
    let backItem = strip.toolbar(strip.toolbar, itemForItemIdentifier: NSToolbarItem.Identifier("back"), willBeInsertedIntoToolbar: true)
    let readItem = strip.toolbar(strip.toolbar, itemForItemIdentifier: NSToolbarItem.Identifier("read"), willBeInsertedIntoToolbar: true)
    let shell = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)   // never put on screen
    shell.isReleasedWhenClosed = false
    let maskBefore = shell.styleMask
    strip.install(in: shell)
    let styleOk: Bool = Style.body.pointSize == NSFont.systemFontSize && Style.caption.pointSize == NSFont.smallSystemFontSize && fontsSaid == ["13.0", "11.0", "15.0 heavy"] && Style.margin == 20 && Style.spacing == 8
    let listOk: Bool = listSaid == "inset=true row=24.0 spacing=17.0x0.0 striped=true grid=true one=true" && native.rowHeight == Style.rowHeight && native.intercellSpacing == Style.cellSpacing
    let headerNeeds: CGFloat = narrow.headerCell.cellSize.width
    let columnOk: Bool = narrow.width >= headerNeeds && narrow.minWidth >= headerNeeds && narrow.width > 10 && !narrow.resizingMask.contains(.autoresizingMask) && wide.width == 140 && wide.minWidth == 140 && wide.resizingMask.contains(.autoresizingMask)
        && type(of: narrow.headerCell) == NSTableHeaderCell.self && narrow.headerCell.font?.pointSize == NSFont.smallSystemFontSize
    let leadText = lead.textField, plainText = plainCell.textField
    let cellOk: Bool = leadText?.font?.pointSize == 13 && leadText?.textColor == NSColor.labelColor && plainText?.textColor == NSColor.secondaryLabelColor && plainText?.lineBreakMode == NSLineBreakMode.byTruncatingTail && plainText?.isEditable == false
        && wrapped.font?.pointSize == 11 && wrapped.cell?.wraps == true && !wrapped.isSelectable
    let barIds: [String] = strip.toolbarDefaultItemIdentifiers(strip.toolbar).map { $0.rawValue }
    let barOk: Bool = strip.toolbar.displayMode == .iconOnly && !strip.toolbar.allowsUserCustomization && !strip.toolbar.autosavesConfiguration && barIds == ["back", NSToolbarItem.Identifier.flexibleSpace.rawValue, "read"]
        && backItem?.view === barButton && backItem?.isNavigational == true && readItem?.view === barOther && readItem?.isNavigational == false && readItem?.toolTip == "Reads again" && readItem?.label == "Read Sources"
    let shellOk: Bool = shell.toolbar === strip.toolbar && shell.toolbarStyle == .unified && shell.styleMask == maskBefore && !shell.styleMask.contains(.fullSizeContentView) && shell.contentRect(forFrameRect: shell.frame).size == NSSize(width: 400, height: 300)
    check("H66", "one shared set of styles, all asked of AppKit: regular text is the system's regular size (13), captions its small size (11), the one headline its third title size (15) in semibold, all in the system font; a list is inset, striped, without a grid, with 24-point rows 17 apart and none between — AppKit's own default row on this Mac; a column is never narrower than its title and only a flexible one takes spare room; a cell is one truncating line of regular text, the leading one in the label colour and the others secondary; the title area is a standard unified toolbar — icon-only mode, not customisable, nothing saved — whose items are the window's own controls with their tooltips, the way back placed before the title; installing it leaves the window's style and content size as they were",
          styleOk && listOk && columnOk && cellOk && barOk && shellOk,
          "fonts=\(fontsSaid) list=\(listSaid) native row=\(native.rowHeight) spacing=\(native.intercellSpacing) narrow=\(narrow.width)/\(narrow.headerCell.cellSize.width) content=\(shell.contentRect(forFrameRect: shell.frame).size)")

    // ── settings and manifest ──
    let store = MemoryStore(), prefs = Preferences(store: store)
    let d0 = prefs.months, on0 = prefs.enabled
    prefs.months = 6; let d1 = Preferences(store: store).months
    store.set(5, "windowMonths"); let d2 = prefs.months
    prefs.set(.mail, false); let on1 = Preferences(store: store).enabled
    check("H27", "settings: 3 months and every source on by default; choosing 6 months and switching a source off are kept; a stored value that is neither 3 nor 6 reads as 3",
          d0 == 3 && on0 == all && d1 == 6 && d2 == 3 && on1 == [.files, .ai, .imports])
    let home6 = temp.appendingPathComponent("home6", isDirectory: true), p6 = Places(home: home6)
    write(p6.manifest, "{\"ai\":{\"collectedAt\":\"not a date\",\"coverage\":12},\"mail\":\"oops\",\"files\":{\"collectedAt\":\"2026-11-01\",\"coverage\":{\"partial\":true,\"note\":\"3개월만\"}}}")
    let m6 = Manifest.read(p6.manifest)
    write(p6.manifest, "{ broken"); let m7 = Manifest.read(p6.manifest)
    check("H28", "the manifest is optional and read defensively: a bad date gives no collection time, a non-object entry is ignored, object coverage is summarised and {partial:true} marks the source partial; broken JSON is reported and nothing is assumed",
          m6.entries[.ai]?.collectedAt == nil && m6.entries[.ai]?.coverage == nil && m6.entries[.mail] == nil && m6.entries[.files]?.collectedAt != nil && m6.entries[.files]?.partial == true &&
          (m6.entries[.files]?.coverage ?? "").contains("note: 3개월만") && m7.entries.isEmpty && m7.problem != nil)

    print("\n== \(passed)/\(passed + failed) Horizon self-test checks passed ==")
    print("Synthetic data in a temporary folder only. Not checked here: the menu-bar item, dialogs, real sources, the real Mail app, a real refresh tool.")
    return failed == 0 ? 0 : 1
}

/// A stand-in for the Mac's side of a Mail collection: it counts every question, remembers whether any came on the
/// main thread, and answers as told. The real Mail app is never involved.
final class MailMock {
    private let lock = NSLock()
    private var asked = (running: 0, permission: 0, run: 0, onMain: 0)
    private var answers = (running: false, permission: 0, reply: String?.some(""), error: 0, delay: 0.0)
    func set(running: Bool? = nil, permission: Int? = nil, reply: String?? = nil, error: Int? = nil, delay: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let v = running { answers.running = v }; if let v = permission { answers.permission = v }; if let v = reply { answers.reply = v }; if let v = error { answers.error = v }; if let v = delay { answers.delay = v }
    }
    var counts: (running: Int, permission: Int, run: Int, onMain: Int) { lock.lock(); defer { lock.unlock() }; return asked }
    var side: MailAdapter.Side {
        MailAdapter.Side(isRunning: { [self] in lock.lock(); defer { lock.unlock() }; asked.running += 1; return answers.running },
                         permission: { [self] in lock.lock(); defer { lock.unlock() }; asked.permission += 1; if Thread.isMainThread { asked.onMain += 1 }; return answers.permission },
                         run: { [self] _ in
                             lock.lock(); asked.run += 1; if Thread.isMainThread { asked.onMain += 1 }; let a = answers; lock.unlock()
                             if a.delay > 0 { Thread.sleep(forTimeInterval: a.delay) }
                             return (a.reply, a.error) })
    }
    static func reply(_ rows: [(box: String, id: String, date: Date, subject: String)]) -> String {
        let sep = "\u{1F}", f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        var out = ""
        for box in ["I", "S"] {
            let mine = rows.filter { $0.box == box }
            out += ["N", box, String(mine.count)].joined(separator: sep) + "\n"
            for r in mine { out += [box, r.id, f.string(from: r.date), r.subject].joined(separator: sep) + "\n" }
        }
        return out
    }
}

/// What the reader actually reached for on disk, recorded through Reader.probe: one entry for every file it is about
/// to lstat (and then perhaps open and read) and for every look at the imports folder. Reads may run on a background queue.
final class ReadTrace {
    private var list: [String] = []
    private let lock = NSLock()
    func start() { Reader.probe = { [weak self] what, path in self?.add(what + " " + path) } }
    func stop() { Reader.probe = nil }
    private func add(_ e: String) { lock.lock(); list.append(e); lock.unlock() }
    func reset() { lock.lock(); list = []; lock.unlock() }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return list }
    func touched(_ url: URL) -> Int { events.filter { $0.hasSuffix(" " + url.path) }.count }
    func under(_ url: URL) -> Int { events.filter { $0.contains(" " + url.path) }.count }
}

/// Runs the REAL headless command — this same executable, as a separate process — against a synthetic home, with every
/// setting given on the command line (the defaults system reads "-key value" arguments before anything stored, so the
/// run neither reads nor writes anybody's saved settings). Only HORIZON_HOME is in its environment.
struct AsideRun {
    var exit: Int32 = -1
    var out = Data(), err = Data()
    var object: [String: Any] { ((try? JSONSerialization.jsonObject(with: out)) as? [String: Any]) ?? [:] }
    var status: String { object["status"] as? String ?? "?" }
    var reason: String { object["reason"] as? String ?? "?" }
    var handoff: String { object["handoff"] as? String ?? "?" }
    var sources: [String: String] { object["sources"] as? [String: String] ?? ["?": "?"] }
    var text: String { String(decoding: out, as: UTF8.self) }
    /// One line, one object, exactly the five members, nothing on standard error.
    var wellFormed: Bool { err.isEmpty && text.hasSuffix("}\n") && text.dropLast().firstIndex(of: "\n") == nil && Set(object.keys) == ["schema", "status", "handoff", "reason", "sources"] && (object["schema"] as? String) == AsideLookup.schema }
}
func asideSettings(_ changes: [String: String] = [:]) -> [String] {
    var s = ["windowMonths": "3", "windowCustom": "NO", "customStart": "none", "customEnd": "none", "source.files": "YES", "source.ai": "YES", "source.mail": "YES", "source.imports": "YES"]
    for (k, v) in changes { s[k] = v }
    return s.keys.sorted().flatMap { ["-" + $0, s[$0] ?? ""] }
}
func asideProcess(_ input: Data, home: URL, _ changes: [String: String] = [:]) -> AsideRun {
    signal(SIGPIPE, SIG_IGN)                                         // an early exit of the command must not stop the test
    let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    p.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    p.arguments = asideSettings(changes) + ["--aside-lookup"]
    p.environment = ["HORIZON_HOME": home.path]
    p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
    var r = AsideRun()
    guard (try? p.run()) != nil else { return r }
    try? stdin.fileHandleForWriting.write(contentsOf: input)
    try? stdin.fileHandleForWriting.close()
    r.out = stdout.fileHandleForReading.readDataToEndOfFile()
    r.err = stderr.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    r.exit = p.terminationStatus
    return r
}
func asideQuery(_ q: String) -> Data { (try? JSONSerialization.data(withJSONObject: ["query": q])) ?? Data() }

private func rfc2822(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
    return f.string(from: d)
}

/// Sample check:  ContextaHorizon --check-sample <file.mbox>
/// Imports the given example file into a temporary, empty pretend home (never the real ~/WorkIndex), exactly as the
/// Import… button would, and says what a new user would get from it: the topics in the default 3-month view and the
/// handoff for the first one. Fails when the file brings nothing useful — for example when its dates have aged out
/// of the view (Examples/make-sample.sh writes a fresh copy dated relative to today).
func runSampleCheck(_ path: String) -> Int32 {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent("horizon-sample-" + UUID().uuidString, isDirectory: true)
    defer { try? fm.removeItem(at: temp) }
    let places = Places(home: temp), now = Date(), all = Set(SourceKind.allCases)
    let parsed = Importer.parse(URL(fileURLWithPath: path))
    if let p = parsed.problem { print("SAMPLE FAIL  not imported — " + p); return 1 }
    let saved = Importer.save(parsed, name: "sample", places: places, now: now)
    let snap = Snapshot.read(places, now: now)
    let w3 = HorizonWindow(months: 3, now: now), w6 = HorizonWindow(months: 6, now: now)
    let topics = Analysis.topics(snap.evidence, window: w3, enabled: all)
    let inView = snap.evidence.filter { w3.contains($0) }.count, inSix = snap.evidence.filter { w6.contains($0) }.count
    let dates = snap.evidence.map { $0.date }.sorted()
    print("Sample: \(path)")
    print("Imported \(saved.imported) of \(parsed.rows.count) messages (\(parsed.skipped) skipped); dated " + (dates.first.map { Dates.day($0) } ?? "?") + " – " + (dates.last.map { Dates.day($0) } ?? "?") + "; \(inView) in the 3-month view, \(inSix) in 6 months")
    print("Topics (3 months): " + topics.map { "\($0.display) (\($0.items.count))" }.joined(separator: ", "))
    guard let first = topics.first else {
        print("SAMPLE FAIL  no topic in the default 3-month view" + (inView == 0 ? " — the sample's dates are outside it; run Examples/make-sample.sh to write a fresh copy" : ""))
        return 1
    }
    let coverage = SourceKind.allCases.map { snap.coverage(for: $0, window: w3, enabled: all) }
    let task = "Follow up on the " + first.display + " thread"
    let handoff = Export.simple(task: task, topic: first, window: w3, coverage: coverage)
    print("Handoff for “" + task + "”:\n" + handoff.split(separator: "\n").map { "  | " + $0 }.joined(separator: "\n"))
    let cites = handoff.split(separator: "\n").filter { $0.hasPrefix("[M") }.count
    let found = Search.rank(task, topics: topics, limit: 3).first?.topic.key == first.key
    let leaks = handoff.contains("@") || handoff.contains("/Users") || handoff.contains("://")
    let ok = saved.imported >= 6 && saved.imported == parsed.rows.count && inView == saved.imported && topics.count >= 2 && cites >= 2 && found && !leaks
    print(ok ? "SAMPLE PASS  the example imports on an empty install and gives \(topics.count) topics and a handoff with \(cites) citations; only subjects and dates were kept"
             : "SAMPLE FAIL  imported=\(saved.imported) inView=\(inView) topics=\(topics.count) citations=\(cites) searchFindsIt=\(found) leaks=\(leaks)")
    return ok ? 0 : 1
}

/// Window smoke test:  ContextaHorizon --smoke-window <folder-or-png>
/// Opens the real windows against a synthetic home made in a temporary folder (never the real ~/WorkIndex), with
/// settings kept in memory, and walks the everyday path as a person would: the simple screen opens with the field
/// focused → a task is typed → the preview appears → Return (copies nothing) → another suggestion is picked → a task
/// with no match (no preview, Copy off, pressing it does nothing) → Sources & Settings (the dashboard: custom period, refusals,
/// a preset) → back to the simple screen. Pictures are saved beside the given path. The clipboard is never written:
/// Copy is only ever pressed while it is disabled.
@MainActor func runWindowSmoke(savingTo out: String) -> Never {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent("horizon-smoke-" + UUID().uuidString, isDirectory: true)
    let places = Places(home: temp)
    let trace = ReadTrace(); trace.start()                              // what the windows actually reach for on disk, at the reader's own dispatch
    let folder = URL(fileURLWithPath: out).deletingLastPathComponent()
    func put(_ url: URL, _ lines: [[String: Any]]) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.map { String(decoding: (try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])) ?? Data(), as: UTF8.self) }.joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: url)
    }
    let now = Date()
    func ago(_ d: Double) -> String { Dates.isoString(now.addingTimeInterval(-d * 86400)) }
    put(places.preindex, [["name": "Harborline Q3 quote.xlsx", "path": "/Users/mina/Work/Harborline/Harborline Q3 quote.xlsx", "source": "Google Drive", "modified": ago(12), "tags": ["source:google-drive", "kind:spreadsheet", "topic:harborline", "workflow:quote", "folder:harborline"], "review": false],
                          ["name": "plan.pdf", "path": "/Users/mina/Work/Harborline/plan.pdf", "source": "Mac", "modified": ago(25), "tags": ["source:mac", "kind:pdf", "topic:harborline", "ext:pdf", "month:2026-10"], "review": true],
                          ["name": "Atlas layout A.sketch", "path": "/Users/mina/Work/Atlas/Atlas layout A.sketch", "source": "Mac", "modified": ago(30), "tags": ["source:mac", "kind:design", "topic:atlas", "workflow:draft", "folder:atlas"], "review": false]])
    put(places.ai, [["id": "a1", "title": "Harborline quote review notes", "date": ago(10), "topics": ["Harborline"], "source": "Claude", "locator": "claude:a1"],
                    ["id": "a2", "title": "Atlas screen layout ideas", "date": ago(40), "topics": ["Atlas"], "source": "Claude", "locator": "claude:a2"],
                    ["id": "a3", "title": "Northfield cap summary", "date": ago(130), "topics": ["Northfield"], "source": "Claude", "locator": "claude:a3"],
                    ["id": "a4", "title": "Zephyr launch schedule", "date": ago(100), "topics": ["Zephyr"], "source": "Claude", "locator": "claude:a4"],
                    ["id": "a5", "title": "Zephyr price list", "date": ago(110), "topics": ["Zephyr"], "source": "Claude", "locator": "claude:a5"]])
    put(places.mail, [["id": "m1", "title": "RE: Harborline quote reply", "date": ago(8), "topics": [], "source": "Mail", "locator": "message:m1"],
                      ["id": "m2", "title": "Northfield schedule check", "date": ago(125), "topics": ["Northfield"], "source": "Mail", "locator": "message:m2"]])
    put(places.manifest, [["files": ["collectedAt": ago(1), "coverage": "all dates"], "ai": ["collectedAt": ago(20), "coverage": ["complete": false]], "mail": ["collectedAt": ago(2), "coverage": "last 6 months"]]])
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let dashboard = HorizonController(places: places, preferences: Preferences(store: MemoryStore()))
    let simple = SimpleController(dashboard: dashboard)
    dashboard.onChange = { simple.refresh() }
    dashboard.onBack = { simple.show() }
    dashboard.onUseTopic = { key in simple.show(pick: key) }
    let mock = MailMock()                                              // the Mac's Mail side: every question is counted; the real Mail app is never involved
    dashboard.mailSide = mock.side
    dashboard.onBackgroundRead = { Thread.sleep(forTimeInterval: 1.2) }  // the first read is made slow, to watch the windows while it runs
    var failures: [String] = []
    func expect(_ name: String, _ ok: Bool, _ detail: [String] = []) { print((ok ? "ok    " : "FAIL  ") + name); if !ok { failures.append(name); detail.forEach { print("        " + $0) } } }
    func picture(_ window: NSWindow, _ name: String) -> Bool {
        guard let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: folder.appendingPathComponent(name))) != nil
    }
    func value(_ state: [String], _ key: String) -> String { String((state.first { $0.hasPrefix(key + "=") } ?? "").dropFirst(key.count + 1)) }
    var step = 0
    dashboard.onRead = {
        step += 1
        guard step == 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // 1. launch: the simple screen, field focused, suggestions offered, nothing to copy yet
            var st = simple.smokeState()
            expect("launch opens the simple screen with the field focused; the dashboard stays closed", simple.smokeWindow.isVisible && !dashboard.smokeWindow.isVisible && value(st, "simple.fieldFocused") == "true", st)
            expect("with nothing typed: two suggested topics, none chosen, no preview, Copy off", value(st, "simple.suggestions") == "Harborline · 4 | Atlas · 2" && value(st, "simple.copyEnabled") == "false" && value(st, "simple.preview").isEmpty && value(st, "simple.empty").hasPrefix("Choose a topic or type a task."), st)
            expect("the caption names the period and what to be careful about (a stale, partial AI feed)", value(st, "simple.caption").hasPrefix("Period: 3 months · ") && value(st, "simple.caption").contains("Source caution: AI chats: stale, partial"), st)
            expect("when the read is done the spinner stops and \"reading\" is gone; launch and the reopenings asked nothing of the Mail side and put no question", value(st, "simple.loading") == "false" && value(st, "simple.spinner") == "false" && mock.counts == (0, 0, 0, 0) && dashboard.smokeMail.asks == 0 && dashboard.smokeReads.asked == 1 && dashboard.smokeReads.stale == 0, st)
            expect("with records in view the fictional example is not offered", value(st, "simple.exampleOffer") == "hidden" && value(st, "simple.exampleBanner") == "hidden" && value(st, "simple.example") == "false", st)
            _ = picture(simple.smokeWindow, "simple-1-start.png")
            // 2. type a task: suggestions ranked, the best match previewed with the task (identifier redacted)
            simple.smokeType("Follow up on the Harborline quote bob@example.com")
            st = simple.smokeState()
            let typed = value(st, "simple.preview")
            expect("typing a task shows the best match chosen and its exact handoff, the task first with the address redacted", value(st, "simple.suggestions") == "Harborline · 4*" && typed.hasPrefix("Task: Follow up on the Harborline quote [email]\nTopic: Harborline · 3 months · ") && !typed.contains("@") && !typed.contains("/Users") && value(st, "simple.copyEnabled") == "true", st)
            expect("the preview cites date · type · title, generated or tag-only links marked (inferred)", typed.contains(" · AI · Harborline quote review notes\n") && typed.contains(" · File · plan.pdf (inferred)\n") && typed.contains(" · Mail · RE: Harborline quote reply\n") && typed.contains("Source caution: AI chats: stale, partial"), [typed])
            let handled = simple.smokeReturn()
            st = simple.smokeState()
            expect("Return settles on the topic and copies nothing", handled && value(st, "simple.copyCount") == "0" && value(st, "simple.status") == "Topic chosen. Press Copy to copy it." && value(st, "simple.preview") == typed, st)
            _ = picture(simple.smokeWindow, "simple-2-typed.png")
            // 2b. the headless lookup: the real command, as a separate process on the same synthetic data, against this window
            let cliTyped = asideProcess(asideQuery("Follow up on the Harborline quote bob@example.com"), home: temp)
            expect("the headless lookup (--aside-lookup, run as a separate process) returns byte-for-byte the text this window shows for the same task", cliTyped.exit == 0 && cliTyped.wellFormed && cliTyped.status == "matched" && !typed.isEmpty && Array(cliTyped.handoff.utf8) == Array(typed.utf8) && !cliTyped.text.contains("@") && !cliTyped.text.contains("/Users"), [cliTyped.text, String(decoding: cliTyped.err, as: UTF8.self)])
            // 3. two matches: the first is shown, the other can be picked
            simple.smokeType("compare harborline and atlas")
            st = simple.smokeState()
            expect("a task naming two topics offers both, the first chosen", value(st, "simple.suggestions") == "Harborline · 4* | Atlas · 2" && value(st, "simple.preview").contains("\nTopic: Harborline · "), st)
            simple.smokePick(1)
            st = simple.smokeState()
            expect("picking the other suggestion switches the preview to it (a tiny set: one header line)", value(st, "simple.suggestions") == "Harborline · 4 | Atlas · 2*" && value(st, "simple.preview").hasPrefix("Task: compare harborline and atlas\n3 months to " + Dates.day(now) + " · titles are signals, not proof of completed work · Source caution: AI chats: stale, partial\n" + Dates.day(now.addingTimeInterval(-30 * 86400)) + " · File · Atlas layout A.sketch\n") && !value(st, "simple.preview").contains("[F1]") && !value(st, "simple.preview").contains("Topic:") && value(st, "simple.preview").split(separator: "\n").count == 4, st)
            _ = picture(simple.smokeWindow, "simple-3-picked.png")
            // 4. no match: the old preview is cleared, Copy is off, pressing it does nothing
            simple.smokeType("zzqx nosuchtopic")
            simple.smokePressCopyWhileDisabled()
            _ = simple.smokeReturn()
            st = simple.smokeState()
            expect("a task with no match clears the preview and turns Copy off; pressing Copy or Return copies nothing", value(st, "simple.suggestions").isEmpty && value(st, "simple.preview").isEmpty && value(st, "simple.copyEnabled") == "false" && value(st, "simple.copyCount") == "0" && value(st, "simple.hint") == "No matching topic was found." && value(st, "simple.empty").hasPrefix("No topic matches “zzqx nosuchtopic”."), st)
            simple.smokeForceTryExample()
            st = simple.smokeState()
            expect("an ordinary task with no match does not offer the fictional example, and the example cannot be entered", value(st, "simple.exampleOffer") == "hidden" && value(st, "simple.example") == "false" && value(st, "simple.hint") == "No matching topic was found.", st)
            _ = picture(simple.smokeWindow, "simple-4-no-match.png")
            let cliNone = asideProcess(asideQuery("zzqx nosuchtopic"), home: temp)
            expect("where the window shows no preview, the headless lookup answers no_match with an empty handoff and does not repeat the task", cliNone.exit == 0 && cliNone.wellFormed && cliNone.status == "no_match" && cliNone.handoff.isEmpty && !cliNone.text.contains("zzqx"), [cliNone.text])
            // 5. no task, a suggestion pressed: the handoff without a task line
            simple.smokeType("")
            simple.smokePick(0)
            st = simple.smokeState()
            expect("pressing a suggested topic without typing shows its handoff (no task line)", value(st, "simple.suggestions") == "Harborline · 4* | Atlas · 2" && value(st, "simple.preview").hasPrefix("Topic: Harborline · 3 months · ") && value(st, "simple.copyEnabled") == "true", st)
            // 6. Sources & Settings: the dashboard with its options; the custom period; back
            simple.smokeOpenAdvanced()
            var ds = dashboard.smokeState()
            expect("Sources & Settings opens the dashboard with every option, and one \"Read Sources\" button where \"Reread Sources\" and \"Collect from Mail…\" were (period, sources, read, imports, refresh)", dashboard.smokeWindow.isVisible && value(ds, "title") == "Contexta Horizon — Sources & Settings" && value(ds, "period").hasSuffix("[3 months,6 months,Custom]") && value(ds, "buttons") == "Read Sources,Import…,Refresh Feeds…,Open in Simple View" && value(ds, "topics") == "2", ds)
            _ = picture(dashboard.smokeWindow, URL(fileURLWithPath: out).lastPathComponent)
            // 6g. the background of both windows: a real material behind the window, and a plain plate when "Reduce transparency" is on.
            //     The app's reading of that setting is replaced for the test; the setting itself is never touched.
            let systemReduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            let liveReduce = WindowBackdrop.reduceTransparency
            let announce = { NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil) }
            let both: [(String, NSWindow)] = [("the simple window", simple.smokeWindow), ("Sources & Settings", dashboard.smokeWindow)]
            func everything(_ v: NSView) -> [NSView] { v.subviews.flatMap { [$0] + everything($0) } }
            /// What a window's background is made of, and what lies on it.
            func made(_ w: NSWindow) -> [String] {
                guard let b = w.contentView as? WindowBackdrop, b.subviews.count == 3 else { return ["background=missing"] }
                let content = b.subviews[2], laid = everything(content)
                // every control and surface the window lays on the background is at full strength, counting everything it sits in up to the
                // background (a scroll bar, which macOS fades out while idle, and AppKit's own parts inside a scroll view are not the window's content)
                func strength(_ v: NSView) -> CGFloat { var a = v.alphaValue, up = v.superview; while let s = up { a *= s.alphaValue; if s === b { break }; up = s.superview }; return a }
                let own = laid.filter { ($0 is NSControl || $0 is NSBox || $0 is NSStackView || $0 is NSScrollView || $0 is NSClipView || $0 is NSSplitView || $0 is NSTextView || $0 is NSProgressIndicator) && !($0 is NSScroller) }
                let faint = own.filter { strength($0) != 1 }
                let previews = laid.compactMap { $0 as? NSBox }.filter { $0.boxType == .custom && $0.fillColor == NSColor.textBackgroundColor && $0.borderWidth == 1 }.count
                let tables = laid.compactMap { $0 as? NSScrollView }.filter { ($0.documentView as? NSTableView).map { t in t.backgroundColor.alphaComponent == 1 } == true && $0.drawsBackground }.count
                let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].filter { w.standardWindowButton($0)?.isHidden == false }.count
                return ["order=" + (b.subviews[0] === b.plate && b.subviews[1] === b.effect ? "plate,material,content" : "other"),
                        "material=" + (b.effect.material == .sidebar ? "sidebar" : "other") + " behindWindow=\(b.effect.blendingMode == .behindWindow) followsActive=\(b.effect.state == .followsWindowActiveState)",
                        "shown=" + (b.showsThrough ? "material" : "plain") + " materialHidden=\(b.effect.isHidden) plateHidden=\(b.plate.isHidden)",
                        "contentOver=\(!content.isDescendant(of: b.effect) && b.effect.subviews.allSatisfy { !($0 is NSControl) }) fullStrength=\(faint.isEmpty && b.alphaValue == 1)" + (faint.isEmpty ? "" : " faint=" + Set(faint.map { String(describing: type(of: $0)) }).sorted().joined(separator: ",")) + " laid=\(own.count > 10)",
                        "window opaque=\(w.isOpaque) clear=\(w.backgroundColor == NSColor.clear) standardColour=\(w.backgroundColor == NSColor.windowBackgroundColor) alpha=\(w.alphaValue) titled=\(w.styleMask.contains(.titled)) fullSize=\(w.styleMask.contains(.fullSizeContentView)) clearTitleBar=\(w.titlebarAppearsTransparent) buttons=\(buttons)",
                        "surfaces preview=\(previews) tables=\(tables)"]
            }
            func wanted(_ shown: String, preview: Int, tables: Int) -> [String] {
                ["order=plate,material,content", "material=sidebar behindWindow=true followsActive=true", shown, "contentOver=true fullStrength=true laid=true",
                 "window opaque=true clear=false standardColour=true alpha=1.0 titled=true fullSize=false clearTitleBar=false buttons=3", "surfaces preview=\(preview) tables=\(tables)"]
            }
            /// The brightness of the background as it is drawn, at a point near the top left corner where nothing else is.
            func ground(_ w: NSWindow) -> CGFloat {
                guard let view = w.contentView else { return -1 }
                view.layoutSubtreeIfNeeded(); view.needsDisplay = true
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
                view.cacheDisplay(in: view.bounds, to: rep)
                return rep.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? -1
            }
            let materialSaid = "shown=material materialHidden=false plateHidden=true", plainSaid = "shown=plain materialHidden=true plateHidden=false"
            WindowBackdrop.reduceTransparency = { false }; announce()
            simple.smokeType("Follow up on the Harborline quote")
            let glassSimple = simple.smokeState(), glassDash = dashboard.smokeState()
            expect("both windows have the same kind of background: a sidebar material blended behind the window that follows the window's active state, with the content laid over it at full strength (not inside it); the window itself is at alpha 1, opaque, in its standard colour, with its standard title bar and three buttons; the preview and the two tables keep their own solid surfaces",
                   made(simple.smokeWindow) == wanted(materialSaid, preview: 1, tables: 0) && made(dashboard.smokeWindow) == wanted(materialSaid, preview: 0, tables: 2), made(simple.smokeWindow) + made(dashboard.smokeWindow))
            _ = picture(simple.smokeWindow, "glass-simple-material.png"); _ = picture(dashboard.smokeWindow, "glass-dashboard-material.png")
            WindowBackdrop.reduceTransparency = { true }; announce()
            expect("when macOS says \"Reduce transparency\" is on, both windows switch at once to the plain background: the material is hidden; each window is as before — opaque, in its standard colour, at alpha 1, with its title bar and buttons",
                   made(simple.smokeWindow) == wanted(plainSaid, preview: 1, tables: 0) && made(dashboard.smokeWindow) == wanted(plainSaid, preview: 0, tables: 2), made(simple.smokeWindow) + made(dashboard.smokeWindow))
            expect("the switch leaves the work alone: the typed task, its preview, the chosen topic and the focus in the simple window, and everything in Sources & Settings, are as they were",
                   simple.smokeState() == glassSimple && dashboard.smokeState() == glassDash && value(glassSimple, "simple.query") == "Follow up on the Harborline quote" && value(glassSimple, "simple.preview").hasPrefix("Task: Follow up on the Harborline quote\n") && value(glassSimple, "simple.copyEnabled") == "true", simple.smokeState())
            simple.smokeType("compare harborline and atlas"); simple.smokePick(1)
            var gs = simple.smokeState()
            expect("on the plain background the window works as before: another task is typed and another topic picked", value(gs, "simple.suggestions") == "Harborline · 4 | Atlas · 2*" && value(gs, "simple.preview").hasPrefix("Task: compare harborline and atlas\n") && value(gs, "simple.copyCount") == "0", gs)
            simple.smokePick(0); simple.smokeType("Follow up on the Harborline quote")
            var grounds: [String] = []
            for (name, w) in both {
                let file = name == "the simple window" ? "simple" : "dashboard"
                w.appearance = NSAppearance(named: .aqua); let light = ground(w); _ = picture(w, "glass-\(file)-plain-light.png")
                w.appearance = NSAppearance(named: .darkAqua); let dark = ground(w); _ = picture(w, "glass-\(file)-plain-dark.png")
                let followed = (w.contentView as? WindowBackdrop).map { $0.effect.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua && $0.plate.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua } == true
                WindowBackdrop.reduceTransparency = { false }; announce()
                let darkMaterial = made(w)[2] == materialSaid; _ = picture(w, "glass-\(file)-material-dark.png")
                WindowBackdrop.reduceTransparency = { true }; announce()
                w.appearance = nil
                grounds.append("\(name): light=\(light) dark=\(dark)")
                expect("\(name): the plain background is the window's own colour, light in a light window and dark in a dark one, and the material follows a dark window too", light > 0.8 && dark >= 0 && dark < 0.3 && followed && darkMaterial && made(w)[2] == plainSaid, [grounds.last ?? ""] + made(w))
            }
            WindowBackdrop.reduceTransparency = { false }; announce()
            gs = simple.smokeState()
            expect("when \"Reduce transparency\" goes off again the material is back in both windows (still opaque, standard colour, alpha 1), with the same task, preview and focus", made(simple.smokeWindow) == wanted(materialSaid, preview: 1, tables: 0) && made(dashboard.smokeWindow) == wanted(materialSaid, preview: 0, tables: 2) && gs == glassSimple && dashboard.smokeState() == glassDash, gs)
            WindowBackdrop.reduceTransparency = liveReduce; announce()
            simple.smokeType("")
            expect("the test only replaced the app's reading of the setting: macOS's own \"Reduce transparency\" is what it was, and the simple window is back where this step found it", NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency == systemReduce && simple.smokeState() == st, simple.smokeState())
            // 6h. the look, measured on the live windows: this Mac's regular and small control metrics, a standard toolbar as the title
            //     area, lists in the density of Finder's list view — and nothing clipped at the default or the smallest size.
            let regular = NSFont.systemFontSize, small = NSFont.smallSystemFontSize, headlineSize = NSFont.preferredFont(forTextStyle: .title3).pointSize
            let family = NSFont.systemFont(ofSize: regular).familyName ?? ""
            let lookSimple = simple.smokeState(), lookDash = dashboard.smokeState()
            simple.smokeType("Follow up on the Harborline quote")
            _ = dashboard.smokeSelect(key: "harborline")                      // so that both lists have rows
            func laidOn(_ w: NSWindow) -> NSView? { (w.contentView as? WindowBackdrop)?.subviews.last }
            func barViews(_ w: NSWindow) -> [NSView] { (w.toolbar?.items ?? []).compactMap { $0.view } }
            func within<V: NSView>(_ v: NSView, _ kind: V.Type) -> Bool { var up = v.superview; while let s = up { if s is V { return true }; up = s.superview }; return false }
            /// Every piece of text a window shows outside its lists — in its content and in its toolbar — with its font.
            func texts(_ w: NSWindow) -> [(what: String, font: NSFont, view: NSView)] {
                var out: [(what: String, font: NSFont, view: NSView)] = []
                let all = (laidOn(w).map { everything($0) } ?? []) + barViews(w).flatMap { [$0] + everything($0) }
                for v in all where !v.isHiddenOrHasHiddenAncestor && !within(v, NSTableView.self) && !within(v, NSTableHeaderView.self) && !within(v, NSControl.self) {
                    if let t = v as? NSTextField, let f = t.font { out.append(((t.isEditable ? "field:" : "label:") + String(t.stringValue.prefix(40)), f, t)) }
                    else if let b = v as? NSButton, let f = b.font { out.append(("button:" + b.title, f, b)) }
                    else if let c = v as? NSControl, c is NSSegmentedControl || c is NSDatePicker, let f = c.font { out.append((c is NSDatePicker ? "date" : "segments", f, c)) }
                    else if let t = v as? NSTextView, let f = t.font { out.append(("text", f, t)) }
                }
                return out
            }
            func heavy(_ f: NSFont) -> Bool { NSFontManager.shared.weight(of: f) > 5 }
            /// Text that is not the system font at the regular, the small or the headline size, or whose size does not fit its role.
            func odd(_ w: NSWindow, headline: String?) -> [String] {
                texts(w).compactMap { t in
                    let size = t.font.pointSize, label = t.view as? NSTextField
                    var want = regular
                    if let h = headline, t.what == "label:" + h { want = headlineSize }
                    else if let l = label, !l.isEditable, l.textColor == NSColor.secondaryLabelColor { want = small }          // secondary captions are small
                    else if let b = t.view as? NSButton, b.controlSize == .small { want = small }
                    let ok = t.font.familyName == family && size == want && heavy(t.font) == (want == headlineSize) && ((t.view as? NSControl)?.controlSize ?? .regular) != .large && ((t.view as? NSControl)?.controlSize ?? .regular) != .mini
                    return ok ? nil : "\(t.what): \(t.font.fontName) \(size), wanted \(want)"
                }
            }
            let simpleTexts = texts(simple.smokeWindow), dashTexts = texts(dashboard.smokeWindow)
            let sizes: ([(what: String, font: NSFont, view: NSView)]) -> String = { all in Dictionary(grouping: all, by: { $0.font.pointSize }).map { "\($0.key)pt ×\($0.value.count)" }.sorted().joined(separator: ", ") }
            print("        measured: regular \(regular), small \(small), headline \(headlineSize); simple window text: \(sizes(simpleTexts)); Sources & Settings text: \(sizes(dashTexts))")
            expect("type: every piece of text in both windows is the system font at this Mac's regular size (13), its small size (11) for secondary captions, or — once, for the simple window's question — a compact semibold headline (15) where the 22-point one was; the task field, the preview and every button are regular; no control is large or mini",
                   regular == 13 && small == 11 && headlineSize == 15 && odd(simple.smokeWindow, headline: "What do you want to continue?").isEmpty && odd(dashboard.smokeWindow, headline: nil).isEmpty &&
                   simpleTexts.filter { $0.font.pointSize == headlineSize }.count == 1 && simpleTexts.contains { $0.what.hasPrefix("field:") && $0.font.pointSize == regular } && simpleTexts.contains { $0.what == "text" && $0.font.pointSize == regular } &&
                   simpleTexts.contains { $0.what == "button:Copy" && ($0.view as? NSButton)?.controlSize == .regular } && simpleTexts.filter { $0.font.pointSize == small }.count >= 2 && dashTexts.filter { $0.font.pointSize == small }.count >= 6 && simpleTexts.count >= 6 && dashTexts.count >= 14,
                   odd(simple.smokeWindow, headline: "What do you want to continue?") + odd(dashboard.smokeWindow, headline: nil) + simpleTexts.map { $0.what } + dashTexts.map { $0.what })
            /// The title area: a standard toolbar and what is in it.
            func bar(_ w: NSWindow) -> String {
                guard let t = w.toolbar else { return "no toolbar" }
                let items = t.items.map { i -> String in
                    let shown = (i.view as? NSButton)?.title ?? (i.view as? NSSegmentedControl).map { s in (0..<s.segmentCount).map { s.label(forSegment: $0) ?? "" }.joined(separator: "/") } ?? "space"
                    return i.itemIdentifier.rawValue + "=" + shown + (i.isNavigational ? " (before the title)" : "")
                }
                return "unified=\(w.toolbarStyle == .unified) customisable=\(t.allowsUserCustomization) shown=\(t.visibleItems?.count ?? -1)/\(t.items.count) [" + items.joined(separator: ", ") + "] title=" + w.title + " titleShown=\(w.titleVisibility == .visible)"
            }
            let barSimple = bar(simple.smokeWindow), barDash = bar(dashboard.smokeWindow)
            expect("title area: each window has a standard unified toolbar that shows the window's title, is not customisable and holds only the window's own controls — Sources & Settings in the simple window; Simple View before the title, then the period and Read Sources, Import…, Refresh Feeds… in Sources & Settings — and the content no longer repeats the title as a header",
                   barSimple == "unified=true customisable=false shown=2/2 [NSToolbarFlexibleSpaceItem=space, settings=Sources & Settings] title=Contexta Horizon titleShown=true" &&
                   barDash == "unified=true customisable=false shown=6/6 [back=Simple View (before the title), period=3 months/6 months/Custom, NSToolbarFlexibleSpaceItem=space, read=Read Sources, import=Import…, refresh=Refresh Feeds…] title=Contexta Horizon — Sources & Settings titleShown=true" &&
                   !dashTexts.contains { $0.what == "label:Sources & Settings" } && !simpleTexts.contains { $0.what == "label:Contexta Horizon" }, [barSimple, barDash])
            /// A list as it is on screen: its density, its header and its cells.
            func list(_ table: NSTableView) -> String {
                guard table.numberOfRows > 0 else { return "no rows" }
                let cells = (0..<table.numberOfColumns).compactMap { table.view(atColumn: $0, row: 0, makeIfNecessary: true) as? NSTableCellView }
                cells.forEach { $0.layoutSubtreeIfNeeded() }
                let leading = Set(["topic", "title"])
                let colours = cells.allSatisfy { c in c.textField?.textColor == (leading.contains(c.identifier?.rawValue ?? "") ? NSColor.labelColor : NSColor.secondaryLabelColor) }
                let centred = cells.allSatisfy { c in c.textField.map { abs($0.frame.midY - c.bounds.midY) <= 1 } == true }
                let header = table.headerView != nil && table.tableColumns.allSatisfy { type(of: $0.headerCell) == NSTableHeaderCell.self && $0.headerCell.font?.pointSize == small }
                return "style=" + (table.style == .inset ? "inset" : "other") + " rowHeight=\(table.rowHeight) pitch=\(table.rect(ofRow: 0).height) spacing=\(table.intercellSpacing.width)x\(table.intercellSpacing.height) striped=\(table.usesAlternatingRowBackgroundColors) grid=\(table.gridStyleMask.isEmpty ? "none" : "lines") standardHeader11=\(header) cells=\(cells.count) cellFont=\(Set(cells.compactMap { $0.textField?.font?.pointSize }).sorted()) systemFont=\(cells.allSatisfy { $0.textField?.font?.familyName == family }) leadingLabelOthersSecondary=\(colours) centred=\(centred) selection=\(table.selectionHighlightStyle == .regular ? "standard" : "other")"
            }
            let tables = (laidOn(dashboard.smokeWindow).map { everything($0) } ?? []).compactMap { $0 as? NSTableView }
            let lists = tables.map { list($0) }
            func wantedList(_ columns: Int) -> String { "style=inset rowHeight=24.0 pitch=24.0 spacing=17.0x0.0 striped=true grid=none standardHeader11=true cells=\(columns) cellFont=[13.0] systemFont=true leadingLabelOthersSecondary=true centred=true selection=standard" }
            expect("lists: the topics and the evidence are in the density of Finder's list view — inset style, 24-point rows with no gap between them, stripes, no grid, the standard 11-point header, regular 13-point cells centred in their rows, the leading column in the label colour and the others secondary, standard selection",
                   lists == [wantedList(5), wantedList(6)] && NSTableView().rowHeight == 24, lists)
            /// Insets and spacing: the content starts one standard margin from every edge.
            func edges(_ w: NSWindow) -> String {
                guard let root = w.contentView, let stack = laidOn(w) as? NSStackView else { return "no stack" }
                w.layoutIfNeeded()
                // measured where each row is aligned (a button's or a checkbox's frame reaches a little past its visible edge)
                let boxes = stack.arrangedSubviews.filter { !$0.isHidden }.map { v in stack.convert(v.alignmentRect(forFrame: v.frame), to: root) }
                let i = stack.edgeInsets
                return "insets=\(i.top),\(i.left),\(i.bottom),\(i.right) spacing=\(stack.spacing) left=\(boxes.map { $0.minX }.min() ?? -1) right=\((root.bounds.maxX - (boxes.map { $0.maxX }.max() ?? 0)).rounded()) top=\((root.bounds.maxY - (boxes.map { $0.maxY }.max() ?? 0)).rounded()) bottom=\((boxes.map { $0.minY }.min() ?? -1).rounded()) allStartAtMargin=\(boxes.allSatisfy { $0.minX == 20 })"
            }
            let wantedEdges = "insets=20.0,20.0,20.0,20.0 spacing=8.0 left=20.0 right=20.0 top=20.0 bottom=20.0 allStartAtMargin=true"
            expect("spacing: both windows use the same compact measure — content one standard 20-point margin from every edge, 8 points between rows, every row starting at the margin (an idle spinner takes no room)",
                   edges(simple.smokeWindow) == wantedEdges && edges(dashboard.smokeWindow) == wantedEdges, [edges(simple.smokeWindow), edges(dashboard.smokeWindow)])
            /// What is cut off: a button or the period control narrower than its title needs, a label with less room than its text,
            /// anything outside the window, a toolbar item pushed into the overflow menu, a list column narrower than its title.
            func clipped(_ w: NSWindow) -> [String] {
                guard let root = w.contentView, let on = laidOn(w) else { return ["no content"] }
                w.layoutIfNeeded(); root.layoutSubtreeIfNeeded()
                var out: [String] = []
                for t in texts(w) {
                    let size = t.view.frame.size
                    if let c = t.view as? NSControl, c is NSButton || c is NSSegmentedControl || c is NSDatePicker || (c as? NSTextField)?.isEditable == true {
                        let need = c.intrinsicContentSize
                        if (need.width > 0 && size.width + 0.5 < need.width) || size.height + 0.5 < need.height { out.append("\(t.what): has \(size), needs \(need)") }
                    } else if let l = t.view as? NSTextField, !l.stringValue.isEmpty, let cell = l.cell {
                        let need = cell.wraps ? cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: size.width, height: 10_000)) : cell.cellSize
                        if size.width + 0.5 < need.width || size.height + 0.5 < need.height { out.append("\(t.what): has \(size), needs \(need)") }
                    }
                    if t.view.isDescendant(of: on), !root.bounds.insetBy(dx: -0.5, dy: -0.5).contains(t.view.convert(t.view.bounds, to: root)) { out.append("\(t.what): outside the window") }
                }
                if let bar = w.toolbar, bar.visibleItems?.count != bar.items.count { out.append("toolbar: \(bar.items.count - (bar.visibleItems?.count ?? 0)) item(s) pushed into the overflow menu") }
                for table in everything(on).compactMap({ $0 as? NSTableView }) { for c in table.tableColumns where c.width + 0.5 < c.headerCell.cellSize.width { out.append("column \(c.title): \(c.width) wide, its title needs \(c.headerCell.cellSize.width)") } }
                return out
            }
            /// Lists that are wider than the room they have (they scroll sideways rather than squeeze their columns).
            func sideways(_ w: NSWindow) -> [Bool] { (laidOn(w).map { everything($0) } ?? []).compactMap { $0 as? NSTableView }.map { t in t.frame.width > (t.enclosingScrollView?.contentView.bounds.width ?? 0) + 0.5 } }
            let frames = both.map { $0.1.frame }
            let atDefault = both.map { clipped($0.1) }, defaultSizes = both.map { $0.1.contentView?.frame.size ?? .zero }
            let scrollDefault = sideways(dashboard.smokeWindow)
            let room: (NSTableView) -> String = { t in let has: CGFloat = t.enclosingScrollView?.contentView.bounds.width ?? 0; return "\(t.frame.width) wide in \(has)" }
            let columnNotes: [String] = tables.flatMap { t in t.tableColumns.map { c in "\(c.title) \(c.width)≥\(c.headerCell.cellSize.width)" } }
            let roomNotes: [String] = tables.map { room($0) }
            print("        measured at the default sizes \(defaultSizes): lists " + roomNotes.joined(separator: ", ") + "; columns " + columnNotes.joined(separator: ", "))
            expect("at the default sizes (680 × 560 and 1280 × 700) nothing is clipped in either window: every button, the period control and every toolbar item has the room its title needs, every label has room for its text, every list column is at least as wide as its title, and neither list needs to scroll sideways",
                   defaultSizes == [NSSize(width: 680, height: 560), NSSize(width: 1280, height: 700)] && atDefault.allSatisfy { $0.isEmpty } && scrollDefault == [false, false], atDefault.flatMap { $0 } + ["sideways=\(scrollDefault)"])
            for (_, w) in both { w.setContentSize(w.contentMinSize); w.layoutIfNeeded() }
            let atMin = both.map { clipped($0.1) }, reached = both.map { $0.1.contentView?.frame.size == $0.1.contentMinSize }, scrollMin = sideways(dashboard.smokeWindow)
            let scrollers = tables.allSatisfy { $0.enclosingScrollView?.hasHorizontalScroller == true }
            let minWidths: [CGFloat] = tables.map { $0.enclosingScrollView?.frame.width ?? 0 }                       // both lists keep a usable width
            let titleKept: Bool = tables.last?.tableColumns.first { $0.identifier.rawValue == "title" }.map { $0.width >= 140 } == true    // the evidence title is not squeezed away
            _ = picture(simple.smokeWindow, "finder-simple-minimum.png"); _ = picture(dashboard.smokeWindow, "finder-dashboard-minimum.png")
            print("        measured at the smallest sizes \(both.map { $0.1.contentView?.frame.size ?? .zero }): lists \(minWidths) wide, scroll sideways \(scrollMin)")
            expect("at the smallest content sizes the windows allow (520 × 460 and 960 × 560) nothing is clipped either: buttons, labels and toolbar items keep their room, and a list that no longer fits keeps its columns as wide as their titles and scrolls sideways instead",
                   both.map { $0.1.contentMinSize } == [NSSize(width: 520, height: 460), NSSize(width: 960, height: 560)] && reached == [true, true] && atMin.allSatisfy { $0.isEmpty } && scrollers && scrollMin == [true, true] && minWidths.allSatisfy { $0 >= 320 } && titleKept && sideways(simple.smokeWindow).isEmpty, atMin.flatMap { $0 } + ["reached=\(reached) sideways=\(scrollMin)"])
            for (i, pair) in both.enumerated() { pair.1.setFrame(frames[i], display: true); pair.1.layoutIfNeeded() }
            _ = picture(simple.smokeWindow, "finder-simple.png"); _ = picture(dashboard.smokeWindow, "finder-dashboard.png")
            let backToDefault = both.map { clipped($0.1) }
            dashboard.smokeDeselect(); simple.smokeType("")
            expect("back at the default sizes everything fits again, and the measuring left both windows as it found them", backToDefault.allSatisfy { $0.isEmpty } && sideways(dashboard.smokeWindow) == [false, false] && simple.smokeState() == lookSimple && dashboard.smokeState() == lookDash, backToDefault.flatMap { $0 } + simple.smokeState())
            let cal = Calendar.current
            dashboard.smokeApplyCustom(start: now.addingTimeInterval(-30 * 86400), end: now.addingTimeInterval(-9 * 86400))
            ds = dashboard.smokeState()
            let customLabel = "Period: Custom · " + Dates.day(cal.startOfDay(for: now.addingTimeInterval(-30 * 86400))) + " – " + Dates.day(cal.startOfDay(for: now.addingTimeInterval(-9 * 86400))) + " (both days included, 22 days)"
            st = simple.smokeState()
            expect("a custom period applies in the dashboard and the simple screen follows it at once", value(ds, "window") == customLabel && value(ds, "customRow").hasPrefix("shown feedback=Applied: ") && value(ds, "source.mail").hasPrefix("Mail: 0 in this period (2 total)") && value(st, "simple.caption").hasPrefix("Period: Custom · ") && value(st, "simple.preview").hasPrefix("Topic: Harborline · " + String(customLabel.dropFirst("Period: Custom · ".count).prefix(23)) + " (both days included) · titles are signals, not proof of completed work") && value(st, "simple.preview").split(separator: "\n").count == 4 && !value(st, "simple.preview").contains("Mail"), ds + st)
            _ = picture(dashboard.smokeWindow, "window-custom-synthetic.png")
            expect("with the custom period's row on screen (two date fields, Apply and its feedback) nothing is clipped", clipped(dashboard.smokeWindow).isEmpty, clipped(dashboard.smokeWindow))
            for (name, s, e, want) in [("reversed", -5.0, -9.0, "is after the end date"), ("future", -5.0, 3.0, "is in the future"), ("longer than six months", -200.0, -1.0, "The period is longer than 6 months")] {
                dashboard.smokeApplyCustom(start: now.addingTimeInterval(s * 86400), end: now.addingTimeInterval(e * 86400))
                ds = dashboard.smokeState()
                expect("a \(name) period is refused with its reason and changes nothing", value(ds, "customRow").contains(want) && value(ds, "window") == customLabel, ds)
            }
            // the custom period is still in force: the headless lookup, given the same saved period, shows the same text
            simple.smokeType("Follow up on the Harborline quote")
            let customTyped = value(simple.smokeState(), "simple.preview")
            let cliCustom = asideProcess(asideQuery("Follow up on the Harborline quote"), home: temp, ["windowCustom": "YES", "customStart": Dates.day(cal.startOfDay(for: now.addingTimeInterval(-30 * 86400))), "customEnd": Dates.day(cal.startOfDay(for: now.addingTimeInterval(-9 * 86400)))])
            expect("with a custom period in force, the headless lookup returns the same custom-period text as the window", customTyped.hasPrefix("Task: Follow up on the Harborline quote\n" + String(customLabel.dropFirst("Period: Custom · ".count).prefix(23)) + " (both days included) · titles are signals, not proof of completed work") && cliCustom.status == "matched" && Array(cliCustom.handoff.utf8) == Array(customTyped.utf8) && cliCustom.handoff != cliTyped.handoff, [cliCustom.text, customTyped])
            simple.smokeType("")
            // the dashboard → simple hand-off follows the SELECTED TOPIC'S KEY, whatever row it is on
            dashboard.smokeChoosePreset(1)
            ds = dashboard.smokeState()
            expect("the 6-month preset brings two more topics into the dashboard, in its own order", value(ds, "period").hasPrefix("6 months [") && value(ds, "customRow") == "hidden feedback=" && dashboard.smokeTopicKeys == ["harborline", "atlas", "northfield", "zephyr"] && dashboard.smokeSelectedKey == nil, ds + [dashboard.smokeTopicKeys.joined(separator: ",")])
            let northRow = dashboard.smokeSelect(key: "northfield")
            ds = dashboard.smokeState()
            expect("selecting Northfield by its key (row \(northRow.map(String.init) ?? "?")) shows its evidence", northRow == 2 && dashboard.smokeSelectedKey == "northfield" && value(ds, "header").hasPrefix("Evidence — Northfield: 2 records") && value(ds, "copyEnabled") == "true", ds)
            dashboard.smokeUseInSimple()
            st = simple.smokeState()
            expect("\"Open in Simple View\" opens the simple screen with exactly that topic chosen (Northfield, not the one above it), in the new period", simple.smokeWindow.isVisible && value(st, "simple.suggestions") == "Harborline · 4 | Atlas · 2 | Northfield · 2*" && value(st, "simple.preview").hasPrefix("Topic: Northfield · 6 months to " + Dates.day(now) + " · titles are signals, not proof of completed work") && !value(st, "simple.preview").contains("Atlas") && value(st, "simple.caption").hasPrefix("Period: 6 months · "), st)
            _ = picture(simple.smokeWindow, "simple-5-back-from-settings.png")
            let zephyrRow = dashboard.smokeSelect(key: "zephyr")
            dashboard.smokeUseInSimple()
            st = simple.smokeState()
            expect("a topic outside the top three (Zephyr, row \(zephyrRow.map(String.init) ?? "?")) is handed over too: it is shown first and chosen", zephyrRow == 3 && value(st, "simple.suggestions") == "Zephyr · 2* | Harborline · 4 | Atlas · 2" && value(st, "simple.preview").hasPrefix("Topic: Zephyr · 6 months to " + Dates.day(now) + " · titles are signals, not proof of completed work") && value(st, "simple.preview").contains(" · AI · Zephyr launch schedule\n"), st)
            // the order changes under a selected topic: Atlas is row 1 in 3 months, row 0 in a period that holds only Atlas
            dashboard.smokeChoosePreset(0)
            let atlasRow3 = dashboard.smokeSelect(key: "atlas")
            dashboard.smokeApplyCustom(start: now.addingTimeInterval(-45 * 86400), end: now.addingTimeInterval(-28 * 86400))
            ds = dashboard.smokeState()
            expect("when the period changes the rows, the selection stays with the topic: Atlas moves from row 1 to row 0 and is still the selected one", atlasRow3 == 1 && dashboard.smokeTopicKeys == ["atlas"] && dashboard.smokeSelectedKey == "atlas" && value(ds, "header").hasPrefix("Evidence — Atlas: 2 records"), ds + [dashboard.smokeTopicKeys.joined(separator: ",")])
            dashboard.smokeUseInSimple()
            st = simple.smokeState()
            expect("and the hand-off gives Atlas in that custom period", value(st, "simple.suggestions") == "Atlas · 2*" && value(st, "simple.preview").hasPrefix("Topic: Atlas · " + Dates.day(cal.startOfDay(for: now.addingTimeInterval(-45 * 86400))) + " – " + Dates.day(cal.startOfDay(for: now.addingTimeInterval(-28 * 86400))) + " (both days included) · titles are signals, not proof of completed work") && !value(st, "simple.preview").contains("Harborline"), st)
            // the selected topic leaves the view: nothing stale is kept anywhere
            dashboard.smokeApplyCustom(start: now.addingTimeInterval(-13 * 86400), end: now.addingTimeInterval(-7 * 86400))
            dashboard.smokeUseInSimple()                                   // the button is off; pressing it must do nothing
            ds = dashboard.smokeState()
            st = simple.smokeState()
            expect("when the selected topic is no longer in view, the dashboard has no selection (its button is off) and the simple screen drops the stale preview: no topic chosen, Copy off", dashboard.smokeTopicKeys == ["harborline"] && dashboard.smokeSelectedKey == nil && value(ds, "copyEnabled") == "false" && value(st, "simple.suggestions") == "Harborline · 3" && value(st, "simple.preview").isEmpty && value(st, "simple.copyEnabled") == "false", ds + st)
            dashboard.smokeBack()
            st = simple.smokeState()
            expect("\"Simple View\" shows the simple screen again; through the whole run nothing was copied", simple.smokeWindow.isVisible && value(st, "simple.copyCount") == "0", st)
            var pictures = ["loading-simple.png", "loading-dashboard.png", "menu-glyph-in-app.png", "simple-1-start.png", "simple-2-typed.png", "simple-3-picked.png", "simple-4-no-match.png", "simple-5-back-from-settings.png", "window-custom-synthetic.png", URL(fileURLWithPath: out).lastPathComponent,
                            "glass-simple-material.png", "glass-dashboard-material.png", "glass-simple-plain-light.png", "glass-simple-plain-dark.png", "glass-simple-material-dark.png", "glass-dashboard-plain-light.png", "glass-dashboard-plain-dark.png", "glass-dashboard-material-dark.png",
                            "finder-simple.png", "finder-dashboard.png", "finder-simple-minimum.png", "finder-dashboard-minimum.png"]
            let finish: () -> Never = {
                expect("pictures saved: " + pictures.joined(separator: ", "), pictures.allSatisfy { fm.fileExists(atPath: folder.appendingPathComponent($0).path) })
                try? fm.removeItem(at: temp)
                print(failures.isEmpty ? "SMOKE PASS  launch → type → preview → Return → pick another → no match (no copy) → Sources & Settings → custom period → back → switches gate what is read (off, on, races, all off) → one Read Sources button with the Mail question as a sheet (mocked Mail side) → off-main recomputation → fictional example entered and left on an empty home; windows were on screen while the first read was still running, on synthetic data; the clipboard was never written" : "SMOKE FAIL  " + failures.joined(separator: "; "))
                exit(failures.isEmpty ? 0 : 1)
            }
            /// Runs `body` shortly after the next read whose answer the dashboard keeps (stale answers never call back).
            let afterRead: (HorizonController, @escaping () -> Void) -> Void = { d, body in d.onRead = { d.onRead = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { body() } } }
            let full = "files:3 ai:5 mail:2 imports:2 | file:3 ai:6 mail:3"

            // 7. the switches decide what is read. One import file mixing a chat and a mail record is added first (as an import would).
            dashboard.smokeChoosePreset(0)
            var mixed = Importer.Parsed(); mixed.format = "jsonl"
            mixed.rows = [Importer.row(id: "smoke:chat", title: "Harborline imported chat", date: now.addingTimeInterval(-6 * 86400), source: "export", locator: "", kind: .ai, via: "jsonl"),
                          Importer.row(id: "smoke:mail", title: "Harborline imported mail", date: now.addingTimeInterval(-7 * 86400), source: "export", locator: "", kind: .mail, via: "jsonl")]
            let savedMixed = Importer.save(mixed, name: "mixed", places: places, now: now)
            trace.reset(); dashboard.smokeReread()
            afterRead(dashboard) {
                var d = dashboard.smokeState()
                expect("with every switch on, each source is read once: the preindex, both feeds, the manifest, the imports folder and its one file", savedMixed.imported == 2 && dashboard.smokeHeld == full && trace.touched(places.preindex) == 1 && trace.touched(places.ai) == 1 && trace.touched(places.mail) == 1 && trace.touched(places.manifest) == 1 && trace.under(places.imports) == 2 && trace.events.count == 6 && value(d, "source.imports").hasPrefix("Imports: 2 in this period (2 total)"), d + trace.events + [dashboard.smokeHeld])
                // Mail off: gone from memory at once, the mixed imports with it, and nothing is read for that
                let asked0 = dashboard.smokeReads.asked
                trace.reset(); dashboard.smokeToggle(.mail, false)
                d = dashboard.smokeState()
                let s7 = simple.smokeState()
                expect("turning Mail off reads nothing and empties memory of mail and of the imports (which can mix chat and mail) at once; the window says Mail is off and the imports were skipped, not that they are absent", trace.events.isEmpty && dashboard.smokeReads.asked == asked0 && dashboard.smokeHeld == "files:3 ai:5 mail:0 imports:0 | file:3 ai:5 mail:0" && value(d, "source.mail") == "Mail: Off — not used in the results" && value(d, "source.imports").hasPrefix("Imports: Skipped, not opened — an import file can mix AI chat and mail records") && value(s7, "simple.caption").contains("Imports: skipped") && !value(s7, "simple.caption").contains("Mail:"), d + s7 + trace.events + [dashboard.smokeHeld])
                trace.reset(); dashboard.smokeReread()
                afterRead(dashboard) {
                    expect("\"Reread Sources\" with Mail off never reaches for mail.jsonl or the imports folder: only the preindex, ai.jsonl and the manifest", trace.touched(places.mail) == 0 && trace.under(places.imports) == 0 && trace.touched(places.preindex) == 1 && trace.touched(places.ai) == 1 && trace.touched(places.manifest) == 1 && trace.events.count == 3 && dashboard.smokeHeld == "files:3 ai:5 mail:0 imports:0 | file:3 ai:5 mail:0", trace.events + [dashboard.smokeHeld])
                    trace.reset(); dashboard.smokeToggle(.mail, true)
                    afterRead(dashboard) {
                        d = dashboard.smokeState()
                        expect("turning Mail on again starts a read, and mail and both kinds of imported record are back", dashboard.smokeReads.asked == asked0 + 2 && dashboard.smokeHeld == full && trace.touched(places.mail) == 1 && trace.under(places.imports) == 2 && value(d, "source.mail").hasPrefix("Mail: 1 in this period (2 total)") && value(d, "source.imports").hasPrefix("Imports: 2 in this period (2 total)"), d + trace.events + [dashboard.smokeHeld])
                        // a race: a read is under way (asked for with Mail off) when Mail is turned on and Files off
                        let r0 = dashboard.smokeReads
                        dashboard.smokeToggle(.mail, false)
                        trace.reset(); dashboard.smokeReread()            // read A: files, AI chats (no mail, no imports)
                        dashboard.smokeToggle(.mail, true)                // newly on while A runs: read B is started, A's answer will be stale
                        dashboard.smokeToggle(.files, false)              // off while B runs: nothing is read for it, and B's answer is cut down before it is kept
                        let r1 = dashboard.smokeReads
                        expect("switches clicked while a read is under way: turning on starts a newer read, turning off starts none, and what is off is out of memory immediately", r1.asked == r0.asked + 2 && r1.busy && r1.stale == r0.stale && dashboard.smokeHeld == "files:0 ai:5 mail:0 imports:0 | file:0 ai:5 mail:0", ["asked \(r0.asked)→\(r1.asked) stale \(r1.stale) busy \(r1.busy)", dashboard.smokeHeld])
                        afterRead(dashboard) {
                            let r2 = dashboard.smokeReads
                            d = dashboard.smokeState()
                            expect("the older read's answer is dropped unseen, and the newer one — which had read the files before Files was turned off — is kept without them: memory matches the switches (Files off, the rest on)", r2.stale == r0.stale + 1 && r2.asked == r1.asked && !r2.busy && dashboard.smokeHeld == "files:0 ai:5 mail:2 imports:2 | file:0 ai:6 mail:3" && value(d, "source.files") == "Files: Off — not used in the results" && trace.touched(places.mail) == 1, d + ["stale \(r0.stale)→\(r2.stale)", dashboard.smokeHeld] + trace.events)
                            // everything off: nothing in memory, nothing read — not even by "Reread Sources"
                            trace.reset()
                            for k in [SourceKind.ai, .mail, .imports] { dashboard.smokeToggle(k, false) }
                            expect("with every switch off nothing is held and nothing was read to get there", trace.events.isEmpty && dashboard.smokeHeld == "files:0 ai:0 mail:0 imports:0 | file:0 ai:0 mail:0" && dashboard.smokeTopicKeys.isEmpty, trace.events + [dashboard.smokeHeld])
                            dashboard.smokeReread()
                            afterRead(dashboard) {
                                let offRun = asideProcess(asideQuery("Harborline quote"), home: temp, ["source.files": "NO", "source.ai": "NO", "source.mail": "NO", "source.imports": "NO"])
                                d = dashboard.smokeState()
                                expect("\"Reread Sources\" with every switch off opens nothing at all, not even the manifest; the lookup command with the same switches answers \"unavailable\" (all_sources_off)", trace.events.isEmpty && dashboard.smokeHeld == "files:0 ai:0 mail:0 imports:0 | file:0 ai:0 mail:0" && SourceKind.allCases.allSatisfy { value(d, "source." + $0.rawValue).hasSuffix(": Off — not used in the results") } && offRun.status == "unavailable" && offRun.reason == "all_sources_off" && offRun.exit == 3, d + trace.events + [offRun.text])
                                let r3 = dashboard.smokeReads
                                trace.reset()
                                for k in SourceKind.allCases { dashboard.smokeToggle(k, true) }      // four clicks in a row: four reads asked for, only the last one's answer is used
                                afterRead(dashboard) {
                                    let r4 = dashboard.smokeReads
                                    let s8 = simple.smokeState()
                                    expect("turning all four on in quick succession: every earlier answer is dropped as stale, the last one is kept, and everything is back", r4.asked == r3.asked + 4 && r4.stale == r3.stale + 3 && !r4.busy && dashboard.smokeHeld == full && dashboard.smokeTopicKeys == ["harborline", "atlas"] && value(s8, "simple.exampleOffer") == "hidden", ["asked \(r3.asked)→\(r4.asked) stale \(r3.stale)→\(r4.stale)", dashboard.smokeHeld] + s8)
                                    _ = picture(dashboard.smokeWindow, "window-switches-restored.png"); pictures.append("window-switches-restored.png")

                                    let phase8: () -> Void = {
                                    // 8. the fictional example, on an EMPTY home (no WorkIndex at all), in its own pair of windows
                                    simple.smokeWindow.orderOut(nil); dashboard.smokeWindow.orderOut(nil)
                                    let emptyHome = temp.appendingPathComponent("empty-home", isDirectory: true)
                                    let emptyStore = MemoryStore()
                                    let dashboard2 = HorizonController(places: Places(home: emptyHome), preferences: Preferences(store: emptyStore))
                                    let simple2 = SimpleController(dashboard: dashboard2)
                                    dashboard2.onChange = { simple2.refresh() }
                                    dashboard2.onBack = { simple2.show() }
                                    dashboard2.onUseTopic = { key in simple2.show(pick: key) }
                                    afterRead(dashboard2) {
                                        var e = simple2.smokeState()
                                        let emptyHint = "No topics were found in this period with the sources that are on."
                                        expect("on an empty install the empty screen offers one action, \"Try a fictional example\", and nothing else new", value(e, "simple.hint") == emptyHint && value(e, "simple.exampleOffer") == "Try a fictional example" && value(e, "simple.exampleBanner") == "hidden" && value(e, "simple.example") == "false" && value(e, "simple.copyEnabled") == "false" && value(e, "simple.preview").isEmpty && value(e, "simple.title") == "Contexta Horizon", e)
                                        _ = picture(simple2.smokeWindow, "example-0-empty.png")
                                        simple2.smokeType("zzqx nothing here")
                                        simple2.smokeForceTryExample()
                                        e = simple2.smokeState()
                                        let typedOffer = value(e, "simple.exampleOffer"), typedExample = value(e, "simple.example")
                                        simple2.smokeType("")
                                        e = simple2.smokeState()
                                        expect("while a task is typed on the empty screen the offer is hidden and the example cannot be entered; clearing the field brings the offer back", typedOffer == "hidden" && typedExample == "false" && value(e, "simple.exampleOffer") == "Try a fictional example" && value(e, "simple.example") == "false", e + ["while typed: offer=" + typedOffer + " example=" + typedExample])
                                        trace.reset()
                                        simple2.smokeTryExample()
                                        e = simple2.smokeState()
                                        let shownExample = value(e, "simple.preview")
                                        expect("pressing it shows a clearly labelled, made-up Harborline topic: the window title, a banner with \"Exit example\", and the caption all say it is fictional; the offer is gone; Copy is off", value(e, "simple.example") == "true" && value(e, "simple.title") == "Contexta Horizon — fictional example" && value(e, "simple.exampleBanner").hasPrefix("Fictional example — made-up Harborline records. Nothing here is from your Mac") && value(e, "simple.exampleBanner").hasSuffix("[Exit example]") && value(e, "simple.caption").hasPrefix("Fictional example · not your records") && value(e, "simple.exampleOffer") == "hidden" && value(e, "simple.copyEnabled") == "false" && value(e, "simple.status") == "Copy is off in the example." && value(e, "simple.suggestions") == "Harborline · 6*", e)
                                        expect("its preview is made by the real formatter: topic, period, signals with the \"not proof\" caveat, and dated file, chat and mail titles", shownExample == Export.simple(task: "", topic: FictionalExample.make(now: Date()).topics[0], window: HorizonWindow(months: 3, now: Date()), coverage: []) && shownExample.hasPrefix("Topic: Harborline · 3 months · ") && shownExample.contains("\nSignals: 6 records (File 2 · AI 2 · Mail 2) · 6 direct / 0 inferred — title counts are signals, not proof of completed work\n") && shownExample.contains(" · File · Harborline Q3 quote.xlsx\n") && shownExample.contains(" · AI · Harborline quote review notes\n") && shownExample.contains(" · Mail · Re: Harborline quote revision\n") && shownExample.split(separator: "\n").count == 8, [shownExample])
                                        _ = picture(simple2.smokeWindow, "example-1-shown.png")
                                        simple2.smokeType("Follow up on the Harborline quote")
                                        let handled2 = simple2.smokeReturn()
                                        simple2.smokePressCopyWhileDisabled()
                                        e = simple2.smokeState()
                                        expect("a task can be typed in the example (the preview gains the task line), and neither Return nor Copy copies anything", handled2 && value(e, "simple.preview").hasPrefix("Task: Follow up on the Harborline quote\nTopic: Harborline · 3 months · ") && value(e, "simple.copyEnabled") == "false" && value(e, "simple.copyCount") == "0" && value(e, "simple.status") == "Copy is off in the example." && value(e, "simple.example") == "true", e)
                                        _ = picture(simple2.smokeWindow, "example-2-task.png")
                                        simple2.smokeType("zzqx nosuchtopic")
                                        e = simple2.smokeState()
                                        expect("a task with no match inside the example shows no preview and still only the way out", value(e, "simple.preview").isEmpty && value(e, "simple.exampleOffer") == "hidden" && value(e, "simple.exampleBanner").hasSuffix("[Exit example]") && value(e, "simple.empty").contains("The example has one made-up topic, Harborline."), e)
                                        let exampleRun = asideProcess(asideQuery("Follow up on the Harborline quote"), home: emptyHome)
                                        expect("the lookup command, asked while the example is on screen, knows nothing of it: \"unavailable\", an empty handoff, no Harborline", exampleRun.status == "unavailable" && exampleRun.reason == "sources_missing" && exampleRun.handoff.isEmpty && !exampleRun.text.contains("Harborline") && exampleRun.exit == 3, [exampleRun.text])
                                        simple2.smokeExitExample()
                                        e = simple2.smokeState()
                                        expect("\"Exit example\" returns to the empty screen exactly as it was: no example, no banner, the offer back, an empty field, no preview, the ordinary title", value(e, "simple.example") == "false" && value(e, "simple.exampleBanner") == "hidden" && value(e, "simple.exampleOffer") == "Try a fictional example" && value(e, "simple.hint") == emptyHint && value(e, "simple.query").isEmpty && value(e, "simple.preview").isEmpty && value(e, "simple.title") == "Contexta Horizon" && value(e, "simple.copyEnabled") == "false" && value(e, "simple.status").isEmpty, e)
                                        _ = picture(simple2.smokeWindow, "example-3-exited.png")
                                        pictures += ["example-0-empty.png", "example-1-shown.png", "example-2-task.png", "example-3-exited.png"]
                                        expect("entering, using and leaving the example read nothing, wrote nothing and changed no setting: the reader was never called, the empty home still does not exist, the settings store is untouched, nothing was copied, and no read was started", trace.events.isEmpty && !fm.fileExists(atPath: emptyHome.path) && emptyStore.values.isEmpty && value(e, "simple.copyCount") == "0" && dashboard2.smokeReads.asked == 1 && dashboard2.smokeHeld == "files:0 ai:0 mail:0 imports:0 | file:0 ai:0 mail:0", trace.events + ["settings: \(emptyStore.values.count)", "reads: \(dashboard2.smokeReads.asked)", dashboard2.smokeHeld])
                                        finish()
                                    }
                                    simple2.show()
                                    }
                                    // 7b. one "Read Sources" button. Mail only through its sheet; the Mail side is the counting mock.
                                    let importCount: () -> Int = { ((try? FileManager.default.contentsOfDirectory(atPath: places.imports.path)) ?? []).filter { $0.hasSuffix(".jsonl") }.count }
                                    let afterApplied: (HorizonController, @escaping () -> Void) -> Void = { d, body in d.onApplied = { d.onApplied = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { body() } } }
                                    let later: (Double, @escaping () -> Void) -> Void = { seconds, body in DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { body() } }
                                    expect("up to here — launch, reopening, switches, rereads, the races — nothing was ever asked of the Mail side", mock.counts == (0, 0, 0, 0) && dashboard.smokeMail.asks == 0, ["\(mock.counts)"])
                                    // three quick presses during a slow read, Mail not running
                                    dashboard.onBackgroundRead = { Thread.sleep(forTimeInterval: 0.5) }
                                    let rA = dashboard.smokeReads, jA = dashboard.smokeJoinedPresses
                                    trace.reset()
                                    afterRead(dashboard) {
                                        dashboard.onBackgroundRead = nil
                                        var dm = dashboard.smokeState()
                                        expect("\"Read Sources\" pressed three times in a row is one read (the later presses join it); with the Mail app not running the local sources are read alone, the status line says why Mail is not part of it, no question is put, and neither macOS nor Mail is asked anything", dashboard.smokeReads.asked == rA.asked + 1 && dashboard.smokeJoinedPresses == jA + 2 && trace.touched(places.preindex) == 1 && trace.touched(places.ai) == 1 && trace.touched(places.mail) == 1 && trace.under(places.imports) == 2 && value(dm, "status").hasPrefix("Mail not included: Mail is not running, and Horizon never opens it · Sources read: ") && mock.counts.permission == 0 && mock.counts.run == 0 && dashboard.smokeMail.asks == 0 && !dashboard.smokeMail.sheetUp && dashboard.smokeHeld == full, dm + ["reads \(rA.asked)→\(dashboard.smokeReads.asked) joined \(dashboard.smokeJoinedPresses - jA)", "\(mock.counts)"])
                                        // Mail switched off: Mail is not even asked whether it runs
                                        mock.set(running: true)
                                        dashboard.smokeToggle(.mail, false)
                                        let cB = mock.counts
                                        afterRead(dashboard) {
                                            dm = dashboard.smokeState()
                                            expect("with the Mail switch off, \"Read Sources\" reads the local sources that are on and leaves Mail out without even asking whether it is running", mock.counts == cB && dashboard.smokeMail.asks == 0 && value(dm, "status").hasPrefix("Mail not included: Imports, AI chats and Mail are not all switched on · Sources read: ") && dashboard.smokeHeld == "files:3 ai:5 mail:0 imports:0 | file:3 ai:5 mail:0", dm + ["\(mock.counts)"])
                                            afterRead(dashboard) {
                                                // all on, Mail running: the question — as a sheet — and a second press while it is up
                                                afterRead(dashboard) {
                                                    let up = dashboard.smokeMail, sheetText = dashboard.smokeSheetText
                                                    dashboard.smokeReadSources()
                                                    let attached = dashboard.smokeWindow.attachedSheet != nil
                                                    if let w = dashboard.smokeSheetWindow { _ = picture(w, "mail-question-sheet.png"); pictures.append("mail-question-sheet.png") }
                                                    expect("with Imports, AI chats and Mail on and the Mail app running, \"Read Sources\" reads the local sources and puts one question as a sheet on the window — \"Local Sources Only\" first, \"Collect from Mail\" second; pressing the button again while it is up puts no second question; nothing has been asked of macOS or Mail yet", up.sheetUp && up.asks == 1 && up.collecting && attached && dashboard.smokeMail.asks == 1 && sheetText == "Also collect recent subjects and dates from Mail? [Local Sources Only | Collect from Mail]" && mock.counts.permission == 0 && mock.counts.run == 0 && dashboard.smokeHeld == full, [sheetText, "\(up)", "\(mock.counts)"])
                                                    later(0.3) {
                                                        dashboard.smokeAnswerMailSheet(collect: false)
                                                        later(0.4) {
                                                            dm = dashboard.smokeState()
                                                            expect("\"Local Sources Only\" closes the sheet and leaves it at the local read: the status line says so, and nothing was asked of macOS or Mail", !dashboard.smokeMail.sheetUp && !dashboard.smokeMail.collecting && value(dm, "status").hasPrefix("Mail not included: you chose local sources only") && mock.counts.permission == 0 && mock.counts.run == 0 && dashboard.smokeHeld == full && importCount() == 1, dm + ["\(mock.counts)"])
                                                            // yes, but macOS refuses
                                                            mock.set(permission: -1743)
                                                            afterRead(dashboard) {
                                                                dashboard.smokeAnswerMailSheet(collect: true)
                                                                later(0.6) {
                                                                    dm = dashboard.smokeState()
                                                                    expect("\"Collect from Mail\" when macOS refuses: \"Permission denied\" is shown as it is, the script is not run, nothing is saved, and the local read stands; macOS was asked off the main thread", value(dm, "status").hasPrefix("Permission denied — macOS did not allow Horizon to ask Mail") && mock.counts.permission == 1 && mock.counts.run == 0 && mock.counts.onMain == 0 && !dashboard.smokeMail.collecting && importCount() == 1 && dashboard.smokeHeld == full, dm + ["\(mock.counts)"])
                                                                    // yes, allowed: two messages come back
                                                                    mock.set(permission: 0, reply: MailMock.reply([("I", "<mock-1@mail.example>", now.addingTimeInterval(-2 * 86400), "Harborline delivery note"), ("S", "<mock-2@mail.example>", now.addingTimeInterval(-3 * 86400), "Atlas reply sent")]))
                                                                    afterRead(dashboard) {
                                                                        afterRead(dashboard) {
                                                                            dm = dashboard.smokeState()
                                                                            expect("\"Collect from Mail\" when allowed: the script is run once, off the main thread; the two subjects and dates are saved as a new import file, the sources are read again, and the records are in view; the status line reports what was read and saved", mock.counts.run == 1 && mock.counts.onMain == 0 && importCount() == 2 && dashboard.smokeHeld == "files:3 ai:5 mail:2 imports:4 | file:3 ai:6 mail:5" && value(dm, "status").hasPrefix("Read from Mail: Inbox 1 (of 1), Sent 1 (of 1) · Saved: 2 new · Sources read: ") && value(dm, "status").components(separatedBy: "Sources read: ").count == 2 && value(dm, "source.imports").contains("2 collected from Mail") && !dashboard.smokeMail.collecting, dm + ["\(mock.counts)", dashboard.smokeHeld])
                                                                            _ = picture(dashboard.smokeWindow, "window-read-sources.png"); pictures.append("window-read-sources.png")
                                                                            // yes, but the Mail switch is turned off while Mail is still being asked: nothing is kept
                                                                            mock.set(reply: MailMock.reply([("I", "<mock-3@mail.example>", now.addingTimeInterval(-86400), "Harborline late arrival")]), delay: 0.7)
                                                                            afterRead(dashboard) {
                                                                                dashboard.smokeAnswerMailSheet(collect: true)
                                                                                later(0.25) {
                                                                                    dashboard.smokeToggle(.mail, false)
                                                                                    later(1.1) {
                                                                                        dm = dashboard.smokeState()
                                                                                        expect("a switch turned off while Mail is still answering wins: what comes back is not saved and not shown, and the status line says it was not kept", mock.counts.run == 2 && importCount() == 2 && value(dm, "status").hasPrefix("Collected from Mail but not kept: Imports, AI chats and Mail are no longer all switched on") && !dashboard.smokeMail.collecting && dashboard.smokeHeld == "files:3 ai:5 mail:0 imports:0 | file:3 ai:5 mail:0", dm + ["\(mock.counts)", dashboard.smokeHeld])
                                                                                        afterRead(dashboard) {
                                                                                            // passive reads and reopening never come near Mail
                                                                                            let cP = mock.counts, aP = dashboard.smokeMail.asks
                                                                                            afterRead(dashboard) {
                                                                                                simple.show(); dashboard.show()
                                                                                                expect("a passive read (a switch, an import, the refresh tool, reopening a window) asks nothing of the Mail side and puts no question", mock.counts == cP && dashboard.smokeMail.asks == aP && dashboard.smokeHeld == "files:3 ai:5 mail:2 imports:4 | file:3 ai:6 mail:5", ["\(cP) → \(mock.counts)"])
                                                                                                // 7c. a large snapshot is worked out off the main thread (forced here): nothing old stays on screen meanwhile
                                                                                                dashboard.inlineLimit = 0
                                                                                                simple.smokeType("Follow up on the Harborline quote")
                                                                                                _ = dashboard.smokeSelect(key: "harborline")
                                                                                                let was = simple.smokeState(), c0 = dashboard.smokeComputes
                                                                                                afterApplied(dashboard) {
                                                                                                    let done = dashboard.smokeComputes, sx = simple.smokeState()
                                                                                                    dm = dashboard.smokeState()
                                                                                                    expect("the earlier of the two computations is dropped as stale and the later one is shown: Mail off and the narrower period, with no mail line and no imported record", done.stale == c0.stale + 1 && done.asked == c0.asked + 2 && !done.working && dashboard.smokeTopicKeys == ["harborline"] && value(sx, "simple.loading") == "false" && value(sx, "simple.preview").hasPrefix("Task: Follow up on the Harborline quote\n") && !value(sx, "simple.preview").contains(" · Mail · ") && !value(sx, "simple.preview").contains("imported") && value(sx, "simple.preview").contains("Imports: skipped") && value(dm, "source.mail") == "Mail: Off — not used in the results", dm + sx + ["\(c0) → \(done)"])
                                                                                                    dashboard.inlineLimit = 400
                                                                                                    simple.smokeType(""); dashboard.smokeChoosePreset(0)
                                                                                                    afterRead(dashboard) {
                                                                                                        expect("back to everything on and three months for what follows", dashboard.smokeHeld == "files:3 ai:5 mail:2 imports:4 | file:3 ai:6 mail:5" && dashboard.smokeTopicKeys == ["harborline", "atlas"] && !dashboard.smokeComputes.working, [dashboard.smokeHeld, dashboard.smokeTopicKeys.joined(separator: ",")])
                                                                                                        phase8()
                                                                                                    }
                                                                                                    dashboard.smokeToggle(.mail, true)
                                                                                                }
                                                                                                dashboard.smokeToggle(.mail, false)                                  // the sources narrow …
                                                                                                let mid = dashboard.smokeState(), midSimple = simple.smokeState(), midKeys = dashboard.smokeTopicKeys, midSelected = dashboard.smokeSelectedKey
                                                                                                dashboard.smokeApplyCustom(start: now.addingTimeInterval(-13 * 86400), end: now.addingTimeInterval(-7 * 86400))   // … and the period, before the first result is in
                                                                                                expect("the moment a switch is turned off and the topics have to be worked out again off the main thread, nothing of the old result stays: no topic, no selection, no coverage line but \"Working out topics…\" or \"Off\", no preview and Copy off in the simple view, which shows it is working — where a moment before a preview with mail lines was on screen", value(was, "simple.preview").contains(" · Mail · ") && value(was, "simple.copyEnabled") == "true" && midKeys.isEmpty && midSelected == nil && value(mid, "topics") == "0" && value(mid, "copyEnabled") == "false" && value(mid, "source.files") == "Files: Working out topics…" && value(mid, "source.mail") == "Mail: Off — not used in the results" && value(mid, "spinner") == "true" && value(midSimple, "simple.preview").isEmpty && value(midSimple, "simple.copyEnabled") == "false" && value(midSimple, "simple.loading") == "true" && value(midSimple, "simple.spinner") == "true" && value(midSimple, "simple.suggestions").isEmpty && dashboard.smokeComputes.working && dashboard.smokeComputes.asked == c0.asked + 2, mid + midSimple)
                                                                                            }
                                                                                            dashboard.smokeReread()
                                                                                        }
                                                                                        dashboard.smokeToggle(.mail, true)
                                                                                    }
                                                                                }
                                                                            }
                                                                            dashboard.smokeReadSources()
                                                                        }
                                                                        dashboard.smokeAnswerMailSheet(collect: true)
                                                                    }
                                                                    dashboard.smokeReadSources()
                                                                }
                                                            }
                                                            dashboard.smokeReadSources()
                                                        }
                                                    }
                                                }
                                                dashboard.smokeReadSources()
                                            }
                                            dashboard.smokeToggle(.mail, true)
                                        }
                                        dashboard.smokeReadSources()
                                    }
                                    dashboard.smokeReadSources(); dashboard.smokeReadSources(); dashboard.smokeReadSources()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 120) { print("SMOKE FAIL  timed out"); try? fm.removeItem(at: temp); exit(1) }
    // 0. while the (slowed) first read runs: the windows are already there, say they are reading, take typing, and reopen without a second read
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
        dashboard.onBackgroundRead = nil
        var s0 = simple.smokeState()
        expect("while the sources are still being read the simple view is already on screen and says so — a spinner and \"Reading your sources…\" — which is not the empty screen: no example is offered, and nothing is claimed to be missing", simple.smokeWindow.isVisible && value(s0, "simple.loading") == "true" && value(s0, "simple.spinner") == "true" && value(s0, "simple.hint") == "Reading your sources…" && value(s0, "simple.empty").hasPrefix("Still reading.") && value(s0, "simple.exampleOffer") == "hidden" && value(s0, "simple.suggestions").isEmpty && dashboard.smokeReads == (1, 0, true), s0)
        simple.smokeType("Follow up on the Harborline quote")          // typing while it reads
        simple.show(); simple.show()                                   // reopened (Finder, the menu-bar icon) …
        dashboard.show()                                               // … and Sources & Settings opened, all during the read
        s0 = simple.smokeState()
        let d0 = dashboard.smokeState()
        expect("typing works while it reads, and reopening the simple view and opening Sources & Settings put both on screen at once without starting a second read; the dashboard shows a spinner, \"Reading sources…\" and \"Reading…\" for each source that is on", value(s0, "simple.query") == "Follow up on the Harborline quote" && value(s0, "simple.loading") == "true" && simple.smokeWindow.isVisible && dashboard.smokeWindow.isVisible && dashboard.smokeReads == (1, 0, true) && value(d0, "spinner") == "true" && value(d0, "status") == "Reading sources…" && value(d0, "source.files") == "Files: Reading…" && value(d0, "source.imports") == "Imports: Reading…" && value(d0, "topics") == "0", s0 + d0)
        _ = picture(simple.smokeWindow, "loading-simple.png"); _ = picture(dashboard.smokeWindow, "loading-dashboard.png")
        // the menu-bar glyph as the app makes it (a template image), drawn large on a light and a dark bar
        let glyph = ThreadGlyph.menuImage()
        let sheet = NSImage(size: NSSize(width: 360, height: 100), flipped: false) { _ in
            NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 180, height: 100).fill(); NSColor(white: 0.16, alpha: 1).setFill(); NSRect(x: 180, y: 0, width: 180, height: 100).fill()
            for (x, dark) in [(CGFloat(18), false), (CGFloat(198), true)] {
                let big = NSRect(x: x, y: 14, width: 72, height: 72), small = NSRect(x: x + 100, y: 41, width: 18, height: 18)
                for r in [big, small] {
                    // as the menu bar does with a template image: its shape, in the bar's own colour
                    let tinted = NSImage(size: r.size, flipped: false) { inner in glyph.draw(in: inner); (dark ? NSColor.white : NSColor.black).set(); inner.fill(using: .sourceIn); return true }
                    tinted.draw(in: r)
                }
            }
            return true
        }
        let glyphSaved = sheet.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }.map { (try? $0.write(to: folder.appendingPathComponent("menu-glyph-in-app.png"))) != nil } ?? false
        expect("the menu-bar glyph the app makes is an 18-point template image (the continued-thread mark)", glyph.isTemplate && glyph.size == NSSize(width: 18, height: 18) && glyphSaved)
        simple.smokeType(""); dashboard.smokeWindow.orderOut(nil); simple.show()      // as at an ordinary launch, for the walk that follows
    }
    simple.show()
    app.run()
    exit(1)
}
