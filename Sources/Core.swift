// Contexta Horizon — the core, without any window: reading the sources (as data, with limits), the 3 / 6 month
// calendar windows, work topics with cross-source evidence, honest coverage, the short handoff text, imports of local
// exports (ChatGPT and Claude conversations.json, Apple Mail and Gmail Takeout .mbox, normalised .jsonl), and the
// checks around the optional user-installed refresh tool.
// Foundation only. No network, no clipboard, no model, and no process except RefreshTool.run (called only after the
// person confirms in the window). Titles are counted as signals; nothing here claims that work was finished.

import Foundation

// MARK: - Places

/// Everything lives under ~/WorkIndex (HORIZON_HOME may point the whole app at another folder, for testing).
struct Places {
    let workIndex: URL
    init(home: URL) { workIndex = home.appendingPathComponent("WorkIndex", isDirectory: true) }
    static func standard() -> Places {
        if let custom = ProcessInfo.processInfo.environment["HORIZON_HOME"], !custom.isEmpty { return Places(home: URL(fileURLWithPath: custom, isDirectory: true)) }
        return Places(home: FileManager.default.homeDirectoryForCurrentUser)
    }
    var preindex: URL { workIndex.appendingPathComponent("preindex-v1/index.jsonl") }
    var horizon: URL { workIndex.appendingPathComponent("horizon-v1", isDirectory: true) }
    var ai: URL { horizon.appendingPathComponent("ai.jsonl") }
    var mail: URL { horizon.appendingPathComponent("mail.jsonl") }
    var manifest: URL { horizon.appendingPathComponent("manifest.json") }
    var imports: URL { horizon.appendingPathComponent("imports", isDirectory: true) }
    /// The one program Horizon may start, at this fixed place, with no arguments, after the person confirms.
    var refreshTool: URL { workIndex.appendingPathComponent("horizon-tools/refresh.command") }
}

// MARK: - Model

enum SourceKind: String, CaseIterable {
    case files, ai, mail, imports
    var label: String {
        switch self { case .files: return "Files"; case .ai: return "AI chats"; case .mail: return "Mail"; case .imports: return "Imports" }
    }
}

/// What kind of record a piece of evidence is (imports are AI or mail records brought in by the person).
enum RecordType: String, CaseIterable {
    case file, ai, mail
    var label: String { switch self { case .file: return "File"; case .ai: return "AI"; case .mail: return "Mail" } }
    var letter: String { switch self { case .file: return "F"; case .ai: return "A"; case .mail: return "M" } }
    /// The switch that governs this type wherever the record came from.
    var governing: SourceKind { switch self { case .file: return .files; case .ai: return .ai; case .mail: return .mail } }
}

struct Evidence {
    let origin: SourceKind
    let type: RecordType
    let id: String
    let title: String
    let date: Date
    let dayOnly: Bool
    let source: String
    let topics: [String]
    let locator: String
    let importedAt: Date?
    /// How it got here: "feed" (the collected feeds), or for imports "chatgpt", "claude", "mbox", "jsonl" (snapshots
    /// of an export file) or "macmail" (asked of the running Mail app on a click).
    let via: String
    /// The title is a machine-generated label (the collector sets "derivedTitle": true), not the person's own words.
    /// Such a title is never a direct mention and never matched against topics: the record is linked only through its
    /// own topic list, and shown as inferred. Absent means false.
    var derivedTitle = false

    /// A snapshot is a copy of an export at the time it was imported; it does not follow later changes.
    var isSnapshot: Bool { origin == .imports && via != "macmail" }
    var provenance: String { origin != .imports ? "Feed" : (via == "macmail" ? "From Mail" : "Snapshot") }
    /// On only when its own source is on AND the switch for its type is on: with Mail off, imported mail is off too.
    func isOn(_ enabled: Set<SourceKind>) -> Bool { enabled.contains(origin) && enabled.contains(type.governing) }
}

// MARK: - Sanitising input

enum Clean {
    static let maxLineBytes = 64 * 1024
    static let maxFileBytes = 32 * 1024 * 1024
    static let maxRows = 200_000
    static let maxTitle = 200, maxTopic = 80, maxTopics = 24, maxSource = 80, maxLocator = 1024, maxID = 300

    /// One line of text: control characters and line breaks become spaces, runs of space collapse, length is limited.
    static func text(_ value: Any?, max: Int) -> String? {
        guard let s = value as? String else { return nil }
        var out = String.UnicodeScalarView()
        var lastSpace = false
        for u in s.unicodeScalars {
            let isControl = u.properties.generalCategory == .control || u.properties.generalCategory == .format && u.value != 0x200D
            let isSpace = isControl || CharacterSet.whitespacesAndNewlines.contains(u)
            if isSpace { if !lastSpace && !out.isEmpty { out.append(" ") }; lastSpace = true } else { out.append(u); lastSpace = false }
        }
        var t = String(out).trimmingCharacters(in: .whitespaces)
        if t.count > max { t = String(t.prefix(max - 1)) + "…" }
        return t.isEmpty ? nil : t
    }

    static func topics(_ value: Any?) -> [String] {
        guard let list = value as? [Any] else { return [] }
        var seen = Set<String>(), out: [String] = []
        for item in list.prefix(64) {
            guard let t = text(item, max: maxTopic) else { continue }
            let k = Topic.key(t)
            if k.isEmpty || seen.contains(k) { continue }
            seen.insert(k); out.append(t)
            if out.count >= maxTopics { break }
        }
        return out
    }
}

/// "1 record", "2 records".
func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)" + (n == 1 ? "" : "s") }

/// What may appear in text that leaves the app: no e-mail addresses, links, absolute paths, raw header names or long
/// identifiers.
enum Redact {
    private static let rules: [(String, String)] = [
        (#"(?i)\b(message-id|in-reply-to|references|return-path|received|delivered-to|x-[a-z0-9\-]+):\s*\S*"#, "[header]"),
        (#"<[^<>\s]*@[^<>\s]*>"#, "[ID]"),
        (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "[email]"),
        (#"(?i)\b(?:[a-z][a-z0-9+.\-]{1,20}://|mailto:|message:|file:)\S+"#, "[link]"),
        (#"(?<![\w.])~?(?:/[^\s/]+){2,}/?"#, "[path]"),
        (#"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#, "[ID]"),
        (#"\b(?=[A-Za-z0-9]*\d)(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{24,}\b"#, "[ID]")
    ]
    static func label(_ s: String, max: Int = 90) -> String {
        var t = s
        for (pattern, with) in rules { t = t.replacingOccurrences(of: pattern, with: with, options: .regularExpression) }
        return Clean.text(t, max: max) ?? ""
    }
}

/// A short, stable stand-in for an identifier that should not be stored as it is (a Message-ID, a conversation ID).
enum Hash {
    static func hex(_ s: String) -> String {
        func fnv(_ seed: UInt64) -> UInt64 { var h = seed; for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }; return h }
        return String(format: "%016llx%016llx", fnv(0xcbf29ce484222325), fnv(0x84222325cbf29ce4))
    }
}

// MARK: - Dates

enum Dates {
    private static let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private static let localNoZone: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f }()

    /// An ISO 8601 date-time (with or without zone; no zone = this Mac's time) or a bare YYYY-MM-DD (a local day).
    static func parse(_ value: Any?, calendar: Calendar = .current) -> (date: Date, dayOnly: Bool)? {
        guard let s = value as? String, s.count <= 40 else { return nil }
        if s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            let p = s.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
            var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
            guard let d = calendar.date(from: c), calendar.component(.day, from: d) == p[2] else { return nil }   // rejects 2026-02-30
            return (d, true)
        }
        if let d = isoFrac.date(from: s) ?? iso.date(from: s) { return (d, false) }
        if s.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            let f = localNoZone; f.timeZone = calendar.timeZone
            if let d = f.date(from: s) { return (d, false) }
        }
        return nil
    }

    static func day(_ d: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func minute(_ d: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
    static func isoString(_ d: Date) -> String { iso.string(from: d) }
}

/// The period the view covers. Either a preset — from the start of the day N calendar months before now (Foundation
/// clamps the day to the end of a shorter month: 31 May − 3 months = 28/29 Feb) up to now — or a custom period of whole
/// days, both the start day and the end day included. Anything dated after now is "future" and never in a period.
struct HorizonWindow {
    let months: Int                        // 3 or 6 for a preset, 0 for a custom period
    let start: Date                        // 00:00 of the first day
    let end: Date                          // the last moment included: now for a preset or a period ending today, else the end of the last day
    let endDay: Date                       // 00:00 of the last day
    let today: Date
    let now: Date
    let calendar: Calendar
    var isCustom: Bool { months == 0 }

    init(months: Int, now: Date, calendar: Calendar = .current) {
        self.months = months == 6 ? 6 : 3
        let back = calendar.date(byAdding: .month, value: -self.months, to: now) ?? now
        start = calendar.startOfDay(for: back)
        end = now
        today = calendar.startOfDay(for: now)
        endDay = today
        self.now = now
        self.calendar = calendar
    }

    /// A custom period: every day from `customStart` to `customEnd`, both included. The caller validates the days
    /// first (CustomPeriod.validate); whatever is passed, nothing after now is ever included.
    init(customStart: Date, customEnd: Date, now: Date, calendar: Calendar = .current) {
        months = 0
        start = calendar.startOfDay(for: customStart)
        today = calendar.startOfDay(for: now)
        endDay = calendar.startOfDay(for: customEnd)
        let lastMoment = (calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay).addingTimeInterval(-0.001)
        end = min(now, lastMoment)
        self.now = now
        self.calendar = calendar
    }

    func contains(_ e: Evidence) -> Bool { e.dayOnly ? (e.date >= start && e.date <= endDay && e.date <= today) : (e.date >= start && e.date <= end) }
    /// Dated after now (whatever the period is): counted apart, never included.
    func isFuture(_ e: Evidence) -> Bool { e.dayOnly ? e.date > today : e.date > now }
    var days: Int { (calendar.dateComponents([.day], from: start, to: endDay).day ?? 0) + 1 }
    var label: String {
        isCustom ? "Custom · \(Dates.day(start, calendar)) – \(Dates.day(endDay, calendar)) (both days included, \(plural(days, "day")))"
                 : "\(months) months · \(Dates.day(start, calendar)) – \(Dates.minute(end, calendar)) (up to now)"
    }
    var dayLabel: String { (isCustom ? "Custom" : "\(months) months") + " · \(Dates.day(start, calendar)) – \(Dates.day(endDay, calendar))" + (isCustom ? " (both days included)" : "") }
}

/// Checking a custom period before it is used. Both days are included; the period may be a single day; it may not
/// be reversed, reach past today, or span more than six calendar months.
enum CustomPeriod {
    enum Check: Equatable {
        case ok(start: Date, end: Date, days: Int)
        case refused(String)
        var message: String {
            switch self {
            case .ok(let s, let e, let days): return "Applied: \(Dates.day(s)) – \(Dates.day(e)) (both days included, \(plural(days, "day")))"
            case .refused(let why): return why
            }
        }
        var isOK: Bool { if case .ok = self { return true }; return false }
    }
    static let maxMonths = 6

    /// The earliest start day allowed for an end day: six calendar months before it (clamped to a shorter month's end).
    static func earliestStart(for end: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .month, value: -maxMonths, to: calendar.startOfDay(for: end)) ?? end)
    }

    static func validate(start: Date, end: Date, now: Date, calendar: Calendar = .current) -> Check {
        let s = calendar.startOfDay(for: start), e = calendar.startOfDay(for: end), today = calendar.startOfDay(for: now)
        func d(_ x: Date) -> String { Dates.day(x, calendar) }
        if s > e { return .refused("The start date (\(d(s))) is after the end date (\(d(e))). Choose a start date on or before the end date.") }
        if e > today { return .refused("The end date (\(d(e))) is in the future. You can choose dates up to today (\(d(today))).") }
        let earliest = earliestStart(for: e, calendar: calendar)
        if s < earliest { return .refused("The period is longer than 6 months. With an end date of \(d(e)), the start date must be \(d(earliest)) or later.") }
        return .ok(start: s, end: e, days: (calendar.dateComponents([.day], from: s, to: e).day ?? 0) + 1)
    }
}

// MARK: - Topics

enum Topic {
    /// Comparison key: NFKC, lower case, "_" "-" and runs of space as one space.
    static func key(_ s: String) -> String {
        let n = s.precomposedStringWithCompatibilityMapping.lowercased()
        return n.replacingOccurrences(of: #"[\s_\-]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    /// Words that say nothing about the work itself: generic and generated labels, file formats and kinds, and the
    /// names of the months. Years, months and bare numbers are caught by pattern; source names are passed in.
    static let lowSignal: Set<String> = ["unknown", "none", "not found", "n/a", "misc", "other", "others", "etc", "inbox", "sent", "notes", "note", "draft", "final", "review", "needs review", "temp", "tmp", "untitled",
        "new folder", "documents", "document", "downloads", "desktop", "my drive", "shared drives", "work", "files", "file", "mail", "email", "ai", "chat", "general", "import", "imported", "export", "snapshot",
        "spreadsheet", "presentation", "design", "pdf", "doc", "docx", "xls", "xlsx", "xlsm", "csv", "tsv", "ppt", "pptx", "key", "pages", "numbers", "txt", "md", "rtf", "hwp", "hwpx", "odt", "ods", "odp",
        "psd", "sketch", "fig", "svg", "eps", "json", "jsonl", "mbox", "gdoc", "gsheet", "gslides", "google doc", "google sheet", "google slides",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "imports", "ai chats", "feed", "from mail", "auto title",
        // Korean equivalents stay: existing indexes, feeds and imports made with earlier builds carry them
        "기타", "새 폴더", "문서", "다운로드", "바탕화면", "내 드라이브", "업무", "자료", "메모", "메일", "대화", "일반", "파일", "스냅샷", "가져온 자료", "ai 대화", "검토 필요", "알 수 없음", "피드", "제목 없음"]
    private static let datePattern = #"^(\d{1,4}|\d{4} \d{1,2}( \d{1,2})?|\d{1,2}월|\d{4}년( \d{1,2}월)?|q[1-4]( \d{4})?|\d{4} q[1-4]|fy ?\d{2,4})$"#
    static func isLowSignal(_ k: String, sources: Set<String> = []) -> Bool {
        k.isEmpty || lowSignal.contains(k) || sources.contains(k) || k.range(of: datePattern, options: .regularExpression) != nil
    }
    /// From preindex tags: "topic:", "project:", "product:" and "folder:" values and plain (manual) tags. Source, kind,
    /// workflow stage, extension, month and year say what a file is, not what work it belongs to.
    static func fromTags(_ tags: [String]) -> [String] {
        var out: [String] = []
        for t in tags {
            if let colon = t.firstIndex(of: ":") {
                let prefix = t[..<colon].lowercased(), value = String(t[t.index(after: colon)...])
                if ["topic", "project", "product", "folder"].contains(prefix) { out.append(value.replacingOccurrences(of: "-", with: " ")) }
            } else { out.append(t) }
        }
        return out.filter { !isLowSignal(key($0)) }
    }
    /// Does a title name the topic itself (a direct signal)? Latin keys must match whole words; others any substring.
    static func named(in title: String, key k: String) -> Bool {
        let tk = key(title)
        if k.unicodeScalars.allSatisfy({ $0.isASCII }) {
            guard k.count >= 3 else { return false }
            let pattern = "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: k) + "($|[^a-z0-9])"
            return tk.range(of: pattern, options: .regularExpression) != nil
        }
        return k.count >= 2 && tk.contains(k)
    }
}

/// One line of evidence under a topic. Records of the same type with the same title on the same day (the user turns of
/// one conversation, say) are shown once, with how many there were.
struct TopicItem { let evidence: Evidence; let direct: Bool; let count: Int }

struct TopicSummary {
    let key: String
    let display: String
    let items: [TopicItem]                 // newest first
    let types: [RecordType]
    var multiType: Bool { types.count >= 2 }
    var direct: Int { items.filter { $0.direct }.count }
    var inferred: Int { items.count - direct }
    var records: Int { items.reduce(0) { $0 + $1.count } }
    var last: Date { items.first?.evidence.date ?? .distantPast }
    var typesLabel: String { types.map { $0.label }.joined(separator: ", ") + (multiType ? " (several types)" : " (one type)") }
    func count(of type: RecordType) -> Int { items.filter { $0.evidence.type == type }.count }
}

enum Analysis {
    /// Subject-line words that say nothing about the work (used only by the title fallback below).
    static let subjectNoise: Set<String> = ["meeting", "meetings", "update", "updates", "question", "questions", "request", "reminder", "invitation", "invite", "schedule", "agenda",
        "summary", "report", "feedback", "hello", "thanks", "thank", "you", "your", "our", "new", "next", "week", "weekly", "monthly", "call", "info", "information", "follow", "following",
        "regarding", "check", "quick", "need", "needed", "can", "will", "are", "was", "has", "have", "not", "all", "any", "but", "get", "let", "now", "out", "see", "via", "per", "team",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "회의", "요청", "문의", "안내", "확인", "공유", "일정", "보고", "답장", "전달"]

    /// Topics from titles alone, for when no record in view has a topic list: a word becomes a topic when it appears
    /// in at least two DIFFERENT titles (reply and forward prefixes ignored, so a thread counts once). Dates, formats,
    /// source names, fillers and common subject-line words are left out; machine-generated titles are not used.
    /// Returns key → how the word was written and how often, like the vocabulary taken from topic lists.
    static func titleVocabulary(_ pool: [Evidence], sources: Set<String>) -> [String: [String: Int]] {
        var titlesWith: [String: Set<String>] = [:], written: [String: [String: Int]] = [:]
        for e in pool where !e.derivedTitle {
            let bare = e.title.replacingOccurrences(of: #"^\s*((re|fw|fwd|답장|전달)\s*:\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
            let titleKey = Topic.key(bare)
            for word in bare.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init) {
                let k = Topic.key(word)
                let latin = k.unicodeScalars.allSatisfy { $0.isASCII }
                if k.count < (latin ? 3 : 2) || Topic.isLowSignal(k, sources: sources) || Search.filler.contains(k) || subjectNoise.contains(k) { continue }
                titlesWith[k, default: []].insert(titleKey)
                written[k, default: [:]][word, default: 0] += 1
            }
        }
        var out: [String: [String: Int]] = [:]
        for (k, titles) in titlesWith.sorted(by: { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }).prefix(40) where titles.count >= 2 { out[k] = written[k] }
        return out
    }

    /// The records that count: their source is on, their type's switch is on, and they are in the window.
    static func pool(_ all: [Evidence], window: HorizonWindow, enabled: Set<SourceKind>) -> [Evidence] {
        all.filter { $0.isOn(enabled) && window.contains($0) }
    }

    /// Work topics in the window. The vocabulary is taken only from records that count (nothing older or switched off
    /// can lend a topic). A topic is listed when a title names it, or when at least two records carry it. Several
    /// record types come first, then direct mentions, then volume. Dates, formats, source names and generated labels
    /// are never topics.
    static func topics(_ all: [Evidence], window: HorizonWindow, enabled: Set<SourceKind>, limit: Int = 60) -> [TopicSummary] {
        let pool = Analysis.pool(all, window: window, enabled: enabled)
        var sources = Set(pool.map { Topic.key($0.source) })
        for k in SourceKind.allCases { sources.insert(Topic.key(k.label)) }
        var display: [String: [String: Int]] = [:]
        for e in pool { for t in e.topics { let k = Topic.key(t); if !Topic.isLowSignal(k, sources: sources) { display[k, default: [:]][t, default: 0] += 1 } } }
        // Nothing in view carries a topic list (for example an install with only an imported .mbox): fall back to the
        // words that recur across titles, so the view is not empty. Never used when any record brings a topic.
        if display.isEmpty { display = titleVocabulary(pool, sources: sources) }
        let known = Array(display.keys)
        var items: [String: [TopicItem]] = [:]
        for e in pool {
            let own = Set(e.topics.map(Topic.key)).filter { display[$0] != nil }
            var keys = own
            // a machine-generated title says nothing by itself: no title matching, and never a direct mention
            if !e.derivedTitle { for k in known where !own.contains(k) && Topic.named(in: e.title, key: k) { keys.insert(k) } }
            for k in keys { items[k, default: []].append(TopicItem(evidence: e, direct: !e.derivedTitle && Topic.named(in: e.title, key: k), count: 1)) }
        }
        var out: [TopicSummary] = []
        for (k, list) in items {
            // one line per (type, title, day)
            var merged: [String: TopicItem] = [:]
            for it in list {
                let g = it.evidence.type.rawValue + "|" + Topic.key(it.evidence.title) + "|" + Dates.day(it.evidence.date, window.calendar)
                if let have = merged[g] { merged[g] = TopicItem(evidence: have.evidence.date >= it.evidence.date ? have.evidence : it.evidence, direct: have.direct || it.direct, count: have.count + 1) } else { merged[g] = it }
            }
            let lines = Array(merged.values)
            guard lines.contains(where: { $0.direct }) || lines.count >= 2 else { continue }
            let sorted = lines.sorted { $0.evidence.date > $1.evidence.date || ($0.evidence.date == $1.evidence.date && $0.evidence.title < $1.evidence.title) }
            let types = RecordType.allCases.filter { t in lines.contains { $0.evidence.type == t } }
            // the name as people wrote it: a form with capitals or non-Latin letters before a lower-case tag form, then the most used
            func written(_ s: String) -> Bool { s != s.lowercased() || !s.unicodeScalars.allSatisfy { $0.isASCII } }
            let name = display[k]?.max { a, b in
                if written(a.key) != written(b.key) { return written(b.key) }
                return a.value < b.value || (a.value == b.value && a.key > b.key)
            }?.key ?? k
            out.append(TopicSummary(key: k, display: name, items: sorted, types: types))
        }
        out.sort { a, b in
            if a.types.count != b.types.count { return a.types.count > b.types.count }
            if a.direct != b.direct { return a.direct > b.direct }
            if a.items.count != b.items.count { return a.items.count > b.items.count }
            if a.last != b.last { return a.last > b.last }
            return a.key < b.key
        }
        return Array(out.prefix(limit))
    }
}

// MARK: - Reading sources

struct Manifest {
    struct Entry { let collectedAt: Date?; let coverage: String?; let partial: Bool }
    var entries: [SourceKind: Entry] = [:]
    var problem: String?

    static func read(_ url: URL) -> Manifest {
        var m = Manifest()
        let f = Reader.regularFile(url, max: 1024 * 1024)
        guard let data = f.data else { m.problem = f.problem; return m }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { m.problem = "manifest.json could not be read"; return m }
        for (name, kind) in [("files", SourceKind.files), ("ai", .ai), ("mail", .mail)] {
            guard let e = root[name] as? [String: Any] else { continue }
            let collected = Dates.parse(e["collectedAt"])?.date
            var coverage: String?, partial = false
            if let s = e["coverage"] as? String { coverage = Clean.text(s, max: 160); partial = s.lowercased().contains("partial") || s.contains("부분") }
            else if let o = e["coverage"] as? [String: Any] {
                partial = (o["complete"] as? Bool) == false || (o["partial"] as? Bool) == true
                let parts = o.keys.sorted().prefix(6).compactMap { k -> String? in
                    let v = o[k]
                    let isBool = (v as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
                    let text = (v as? String) ?? (isBool ? ((v as? Bool) == true ? "true" : "false") : (v as? NSNumber).map { $0.stringValue })
                    return text.flatMap { Clean.text(k + ": " + $0, max: 60) }
                }
                coverage = parts.isEmpty ? nil : parts.joined(separator: ", ")
            }
            m.entries[kind] = Entry(collectedAt: collected, coverage: coverage, partial: partial)
        }
        return m
    }
}

enum Reader {
    /// A regular file only (not a link, not a folder), at most `max` bytes. Larger files are read up to the limit and
    /// reported as cut.
    static func regularFile(_ url: URL, max: Int) -> (data: Data?, problem: String?, missing: Bool, cut: Bool, modified: Date?) {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return (nil, errno == ENOENT ? "file not found" : "cannot be read (permission)", errno == ENOENT, false, nil) }
        let type = st.st_mode & S_IFMT
        if type == S_IFLNK { return (nil, "it is a link, so it is not read", false, false, nil) }
        guard type == S_IFREG else { return (nil, "it is not a file", false, false, nil) }
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        guard let h = FileHandle(forReadingAtPath: url.path) else { return (nil, "cannot be read (permission)", false, false, modified) }
        defer { h.closeFile() }
        let data = h.readData(ofLength: max)
        return (data, nil, false, Int(st.st_size) > max, modified)
    }

    struct Loaded {
        var rows: [Evidence] = []
        var lines = 0
        var skipped = 0
        var cut = false
        var missing = false
        var problem: String?
        var modified: Date?
    }

    /// JSON lines, each parsed on its own; a line that is too long, not JSON or not the expected shape is skipped and
    /// counted. Nothing here can stop the app.
    static func jsonl(_ data: Data, row: ([String: Any]) -> Evidence?) -> (rows: [Evidence], lines: Int, skipped: Int, cut: Bool) {
        var rows: [Evidence] = [], lines = 0, skipped = 0, cut = false
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let slice = data[start..<end]
            start = end < data.endIndex ? data.index(after: end) : end
            if slice.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
            lines += 1
            if rows.count >= Clean.maxRows { cut = true; break }
            guard slice.count <= Clean.maxLineBytes, let obj = (try? JSONSerialization.jsonObject(with: Data(slice))) as? [String: Any], let r = row(obj) else { skipped += 1; continue }
            rows.append(r)
        }
        return (rows, lines, skipped, cut)
    }

    static func load(_ url: URL, row: ([String: Any]) -> Evidence?) -> Loaded {
        var out = Loaded()
        let f = regularFile(url, max: Clean.maxFileBytes)
        out.missing = f.missing; out.problem = f.problem; out.modified = f.modified; out.cut = f.cut
        guard let data = f.data else { return out }
        var usable = data
        if f.cut, let lastNewline = data.lastIndex(of: 0x0A) { usable = data[data.startIndex...lastNewline] }   // a half line at the cut is not read
        let r = jsonl(usable, row: row)
        out.rows = r.rows; out.lines = r.lines; out.skipped = r.skipped; out.cut = out.cut || r.cut
        return out
    }

    /// Only a JSON true counts; a missing flag, false, a number or a string is false.
    static func flag(_ value: Any?) -> Bool {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    /// A preindex row: { name, path, source, modified, tags: [string], review }.
    static func fileRow(_ o: [String: Any]) -> Evidence? {
        guard let name = Clean.text(o["name"], max: Clean.maxTitle), let path = Clean.text(o["path"], max: Clean.maxLocator),
              let source = Clean.text(o["source"], max: Clean.maxSource), let d = Dates.parse(o["modified"]),
              let tags = o["tags"] as? [Any], o["review"] is Bool else { return nil }
        let clean = tags.prefix(16).compactMap { Clean.text($0, max: 120) }
        return Evidence(origin: .files, type: .file, id: path, title: name, date: d.date, dayOnly: d.dayOnly, source: source,
                        topics: Clean.topics(Topic.fromTags(clean)), locator: path, importedAt: nil, via: "feed")
    }

    /// An AI or mail evidence row: { id, title, date, topics: [string], source, locator } (+ importedAt, kind, via in imports).
    static func evidenceRow(_ origin: SourceKind, _ type: RecordType) -> ([String: Any]) -> Evidence? {
        return { o in
            guard let id = Clean.text(o["id"], max: Clean.maxID), let title = Clean.text(o["title"], max: Clean.maxTitle),
                  let d = Dates.parse(o["date"]), o["topics"] is [Any], let source = Clean.text(o["source"], max: Clean.maxSource) else { return nil }
            var t = type
            if origin == .imports { if let k = o["kind"] as? String, let rt = RecordType(rawValue: k), rt != .file { t = rt } }
            let importedAt = origin == .imports ? Dates.parse(o["importedAt"])?.date : nil
            let via = origin == .imports ? (Clean.text(o["via"], max: 16) ?? "jsonl") : "feed"
            return Evidence(origin: origin, type: t, id: id, title: title, date: d.date, dayOnly: d.dayOnly, source: source,
                            topics: Clean.topics(o["topics"]), locator: Clean.text(o["locator"], max: Clean.maxLocator) ?? "", importedAt: importedAt, via: via,
                            derivedTitle: flag(o["derivedTitle"]))
        }
    }

    /// The import files, oldest first; a record whose id was already seen in an earlier file is not read twice.
    static func imports(_ places: Places) -> (loaded: Loaded, files: Int) {
        var out = Loaded(), files = 0
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: places.imports.path, isDirectory: &isDir), isDir.boolValue else { out.missing = true; return (out, 0) }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: places.imports.path)) ?? []).filter { $0.hasSuffix(".jsonl") && !$0.hasPrefix(".") }.sorted().prefix(500)
        var seen = Set<String>()
        for n in names {
            let l = load(places.imports.appendingPathComponent(n), row: evidenceRow(.imports, .mail))
            if l.problem != nil { out.skipped += 1; continue }
            for r in l.rows where seen.insert(r.id).inserted { out.rows.append(r) }
            out.lines += l.lines; out.skipped += l.skipped; out.cut = out.cut || l.cut
            files += 1
        }
        return (out, files)
    }
}

// MARK: - Coverage

struct SourceCoverage {
    let kind: SourceKind
    let enabled: Bool
    let loaded: Reader.Loaded
    let files: Int                         // imports: how many import files
    let inWindow: Int                      // rows in the window that count
    let typeOff: Int                       // rows in the window left out because their type's switch is off
    let future: Int
    let snapshots: Int                     // imports: rows from export files
    let mailCollected: Int                 // imports: rows asked of the Mail app
    let lastImport: Date?
    let collectedAt: Date?
    let manifestCoverage: String?
    let manifestPartial: Bool
    let stale: Bool

    static let staleAfter: TimeInterval = 7 * 86400

    /// One honest line: off / missing / unreadable / empty / no hits in this window / N in the window, how the data got
    /// here (a collected feed, or snapshots of exports), when it was collected, and whether it was read only in part.
    var summary: String {
        if !enabled { return "Off — not used in the results" }
        var parts: [String] = []
        if loaded.missing { return kind == .imports ? "Nothing imported yet" : "No data — the file does not exist (not the same as 0 records)" }
        if let p = loaded.problem { return "Not read — " + p }
        if loaded.rows.isEmpty { parts.append(loaded.lines == 0 ? "Empty — no rows" : "No usable rows") }
        else { parts.append("\(inWindow) in this period (\(loaded.rows.count) total)") }
        if typeOff > 0 { parts.append("\(typeOff) left out because their type is off") }
        if future > 0 { parts.append("\(future) future-dated left out") }
        if loaded.skipped > 0 || loaded.cut { parts.append("Read in part" + (loaded.skipped > 0 ? " — \(plural(loaded.skipped, "bad line")) skipped" : "") + (loaded.cut ? " — cut at the size limit" : "")) }
        if kind == .imports {
            parts.append("\(plural(snapshots, "snapshot record")) (as they were when imported; later changes are not reflected)" + (mailCollected > 0 ? " · \(mailCollected) collected from Mail" : ""))
            if let l = lastImport { parts.append("Last import: " + Dates.minute(l)) }
            parts.append(plural(files, "file"))
        } else {
            if let c = collectedAt { parts.append("Feed collected: " + Dates.minute(c) + (stale ? " (stale)" : "")) }
            else { parts.append("Feed — collection time unknown" + (loaded.modified.map { " · file modified: " + Dates.minute($0) } ?? "")) }
        }
        if let m = manifestCoverage { parts.append("Coverage: " + m) }
        if manifestPartial { parts.append("Marked as partially collected") }
        return parts.joined(separator: " · ")
    }
}

/// Everything read in one refresh.
struct Snapshot {
    var evidence: [Evidence] = []
    var coverage: [SourceKind: Reader.Loaded] = [:]
    var importFiles = 0
    var manifest = Manifest()
    var readAt = Date()

    static func read(_ places: Places, now: Date = Date()) -> Snapshot {
        var s = Snapshot(); s.readAt = now
        s.manifest = Manifest.read(places.manifest)
        let files = Reader.load(places.preindex, row: Reader.fileRow)
        let ai = Reader.load(places.ai, row: Reader.evidenceRow(.ai, .ai))
        let mail = Reader.load(places.mail, row: Reader.evidenceRow(.mail, .mail))
        let imports = Reader.imports(places)
        s.importFiles = imports.files
        s.coverage = [.files: files, .ai: ai, .mail: mail, .imports: imports.loaded]
        s.evidence = files.rows + ai.rows + mail.rows + imports.loaded.rows
        return s
    }

    func coverage(for kind: SourceKind, window: HorizonWindow, enabled: Set<SourceKind>) -> SourceCoverage {
        let l = coverage[kind] ?? Reader.Loaded()
        let entry = manifest.entries[kind]
        let collected = entry?.collectedAt
        let inside = l.rows.filter { window.contains($0) }
        return SourceCoverage(kind: kind, enabled: enabled.contains(kind), loaded: l, files: importFiles,
                              inWindow: inside.filter { $0.isOn(enabled) }.count, typeOff: enabled.contains(kind) ? inside.filter { !$0.isOn(enabled) }.count : 0,
                              future: l.rows.filter { window.isFuture($0) }.count,
                              snapshots: l.rows.filter { $0.isSnapshot }.count, mailCollected: l.rows.filter { $0.via == "macmail" }.count,
                              lastImport: l.rows.compactMap { $0.importedAt }.max(),
                              collectedAt: collected, manifestCoverage: entry?.coverage, manifestPartial: entry?.partial ?? false,
                              stale: collected.map { readAt.timeIntervalSince($0) > SourceCoverage.staleAfter } ?? false)
    }
}

// MARK: - Finding a topic for what the person types (local, deterministic; no model)

enum Search {
    struct Match { let topic: TopicSummary; let score: Int }

    /// Words that carry no topic: fillers people type around a task.
    static let filler: Set<String> = ["이어서", "이어", "이어가기", "계속", "관련", "대한", "대해", "정리", "작업", "하기", "해줘", "해주세요", "그리고", "다시", "좀", "오늘", "내일", "어제",
        "the", "and", "for", "with", "about", "continue", "continuing", "work", "task", "from", "that", "this", "please", "re", "fw", "fwd",
        "email", "path", "link", "header", "이메일", "경로", "링크", "헤더"]              // the redaction marks (Korean ones from earlier builds too)
    private static let particles = ["으로", "에서", "에게", "까지", "부터", "을", "를", "이", "가", "은", "는", "의", "에", "로", "와", "과", "도", "만"]

    /// The words of a query worth matching: normalised, punctuation dropped, fillers, dates, formats and too-short
    /// fragments left out (Latin words need 3 letters, others 2). A Korean word is also tried without its particle.
    static func tokens(_ query: String) -> [String] {
        let cleaned = Topic.key(query).replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        var out: [String] = []
        for raw in cleaned.split(separator: " ").map(String.init) {
            var forms = [raw]
            if !raw.unicodeScalars.allSatisfy({ $0.isASCII }), let p = particles.first(where: { raw.hasSuffix($0) && raw.count - $0.count >= 2 }) { forms.append(String(raw.dropLast(p.count))) }
            for t in forms {
                let latin = t.unicodeScalars.allSatisfy { $0.isASCII }
                if t.count < (latin ? 3 : 2) || filler.contains(t) || Topic.isLowSignal(t) || out.contains(t) { continue }
                out.append(t)
            }
        }
        return Array(out.prefix(12))
    }

    private static func words(_ key: String) -> [String] {
        key.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression).split(separator: " ").map(String.init)
    }

    /// Ranks the topics already found (so the enabled sources and the period are respected) against what was typed:
    /// the topic's name as a phrase in the query (100), a query word equal to a word of the name (40) or beginning
    /// one (20, for typing as you go), and query words found in the topic's evidence titles (8 each, a little more
    /// when several titles have it). Machine-generated titles are not searched. A topic with no hit is not returned:
    /// there is no "closest guess". Equal scores keep the dashboard's order.
    static func rank(_ query: String, topics: [TopicSummary], limit: Int = 3) -> [Match] {
        let toks = tokens(query)
        guard !toks.isEmpty else { return [] }
        let phrase = toks.joined(separator: " ")
        var out: [(Match, Int)] = []
        for (index, t) in topics.enumerated() {
            let nameWords = words(t.key)
            var score = 0
            if Topic.named(in: phrase, key: t.key) || Topic.named(in: Topic.key(query), key: t.key) { score += 100 }
            for tok in toks {
                if nameWords.contains(tok) { score += 40 } else if nameWords.contains(where: { $0.hasPrefix(tok) }) { score += 20 }
                let titles = t.items.filter { !$0.evidence.derivedTitle && Topic.named(in: $0.evidence.title, key: tok) }.count
                if titles > 0 { score += 8 + min(titles, 5) }
            }
            if score > 0 { out.append((Match(topic: t, score: score), index)) }
        }
        out.sort { $0.0.score != $1.0.score ? $0.0.score > $1.0.score : $0.1 < $1.1 }
        return out.prefix(limit).map { $0.0 }
    }
}

// MARK: - Handoff text (shown inline; copied only when the person presses Copy)

enum Export {
    static let maxCitations = 6
    static let tiny = 3

    /// Which lines are cited: about two per record type that has any, then the rest of the six from whatever is
    /// left. Within a type: titles that share more words with the task first (the topic's own name does not count,
    /// since every title has it), then direct mentions, then newest.
    static func citations(_ topic: TopicSummary, prefer: [String] = []) -> [(label: String, item: TopicItem)] {
        let nameWords = Set(topic.key.split(separator: " ").map(String.init))
        let words = prefer.filter { !nameWords.contains($0) }
        func fits(_ it: TopicItem) -> Int { it.evidence.derivedTitle ? 0 : words.filter { Topic.named(in: it.evidence.title, key: $0) }.count }
        func ranked(_ list: [TopicItem]) -> [TopicItem] { list.sorted { (fits($0), $0.direct ? 1 : 0, $0.evidence.date) > (fits($1), $1.direct ? 1 : 0, $1.evidence.date) } }
        var chosen: [TopicItem] = [], rest: [TopicItem] = []
        for t in topic.types { let r = ranked(topic.items.filter { $0.evidence.type == t }); chosen += r.prefix(2); rest += r.dropFirst(2) }
        chosen += ranked(rest).prefix(max(0, maxCitations - chosen.count))
        chosen = Array(chosen.prefix(maxCitations))
        var n: [RecordType: Int] = [:], out: [(String, TopicItem)] = []
        for t in RecordType.allCases { for it in ranked(chosen.filter { $0.evidence.type == t }) { n[t, default: 0] += 1; out.append(("[" + t.letter + String(n[t]!) + "]", it)) } }
        return out
    }

    /// What deserves a word of caution about the sources that are on: stale or partial feeds, missing ones, and
    /// snapshots among the imports. nil when there is nothing to say.
    static func caption(_ coverage: [SourceCoverage]) -> String? {
        var notes: [String] = []
        for c in coverage where c.enabled {
            var flags: [String] = []
            if c.loaded.missing && c.kind != .imports { flags.append("no data") }
            if c.loaded.problem != nil && !c.loaded.missing { flags.append("not read") }
            if c.stale { flags.append("stale") }
            if c.manifestPartial || c.loaded.skipped > 0 || c.loaded.cut { flags.append("partial") }
            if c.kind == .imports && c.snapshots > 0 { flags.append("snapshot") }
            if c.kind != .imports && !c.loaded.missing && c.loaded.problem == nil && c.collectedAt == nil { flags.append("collection time unknown") }
            if !flags.isEmpty { notes.append(c.kind.label + ": " + flags.joined(separator: ", ")) }
        }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }

    /// The short handoff for one topic, exactly as shown in the window. With the person's task (identifiers redacted)
    /// when they typed one. Citations are "[F1] date · type · title", marked (inferred) when the title does not name the
    /// topic or is machine-generated. No paths, addresses, links, IDs or bodies. It states signals, never outcomes.
    /// A topic with three lines or fewer gets one header line instead of a preamble longer than its list.
    static func simple(task: String, topic: TopicSummary, window: HorizonWindow, coverage: [SourceCoverage]) -> String {
        let taskLine = Redact.label(task, max: 140)
        let cited = citations(topic, prefer: Search.tokens(taskLine))             // only the words that are shown: nothing that was redacted
        let note = caption(coverage)
        var lines: [String] = []
        if !taskLine.isEmpty { lines.append("Task: " + taskLine) }
        let name = Redact.label(topic.display, max: 60)
        if topic.items.count <= tiny {
            lines.append("Topic: \(name) · \(window.dayLabel) · \(plural(topic.items.count, "record")) — titles are signals, not proof of completed work" + (note.map { " · Source caution: " + Redact.label($0, max: 120) } ?? ""))
        } else {
            let byType = topic.types.map { "\($0.label) \(topic.count(of: $0))" }.joined(separator: " · ")
            lines.append("Topic: \(name) · \(window.dayLabel)")
            lines.append("Signals: \(plural(topic.items.count, "record")) (\(byType)) · \(topic.direct) direct / \(topic.inferred) inferred — title counts are signals, not proof of completed work")
        }
        for c in cited {
            lines.append(c.label + " " + Dates.day(c.item.evidence.date, window.calendar) + " · " + c.item.evidence.type.label + " · " + Redact.label(c.item.evidence.title) + (c.item.direct ? "" : " (inferred)"))
        }
        if topic.items.count > cited.count { lines.append("\(topic.items.count - cited.count) more not shown") }
        if topic.items.count > tiny, let n = note { lines.append("Source caution: " + Redact.label(n, max: 160)) }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Imports (local exports the person chooses; saved as NEW files, never over an existing one)

enum Importer {
    struct Parsed { var rows: [[String: Any]] = []; var skipped = 0; var format = ""; var problem: String? }
    struct Result { let imported: Int; let duplicates: Int; let skipped: Int; let file: URL?; let problem: String? }

    static func row(id: String, title: String, date: Date, source: String, locator: String, kind: RecordType, via: String, topics: [String] = []) -> [String: Any] {
        ["id": id, "title": title, "date": Dates.isoString(date), "topics": topics, "source": source, "locator": locator, "kind": kind.rawValue, "via": via]
    }

    /// What kind of export a chosen file is, by what it is (not by trusting its name alone).
    static func parse(_ url: URL, jsonlKind: RecordType = .mail) -> Parsed {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return Parsed(problem: "file not found") }
        if isDir.boolValue {                                                    // Apple Mail exports "Name.mbox" as a folder holding a file "mbox"
            let inner = url.appendingPathComponent("mbox")
            guard Reader.regularFile(inner, max: 1).data != nil else { return Parsed(problem: "this folder has no mbox file in it") }
            return mbox(inner, name: url.deletingPathExtension().lastPathComponent)
        }
        switch url.pathExtension.lowercased() {
        case "json": return chatExport(url)
        case "jsonl": return jsonl(url, defaultKind: jsonlKind)
        default: return mbox(url, name: url.deletingPathExtension().lastPathComponent)
        }
    }

    /// The official ChatGPT and Claude data exports (conversations.json). Only the person's own turns are taken, each
    /// with its own time and the conversation's title. No message text of any kind is read into a row: not the
    /// person's, not the assistant's, not a tool's. Conversation and message IDs are stored as hashes.
    static func chatExport(_ url: URL, maxBytes: Int = 768 * 1024 * 1024) -> Parsed {
        var out = Parsed()
        let f = Reader.regularFile(url, max: maxBytes)
        guard let data = f.data else { out.problem = f.problem; return out }
        if f.cut { out.problem = "the file is too large (over 768 MB)"; return out }
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { out.problem = "this is not a conversations.json export"; return out }
        for item in list {
            guard let conv = item as? [String: Any] else { out.skipped += 1; continue }
            if let mapping = conv["mapping"] as? [String: Any] {                       // ChatGPT
                out.format = "chatgpt"
                let title = Clean.text(conv["title"], max: Clean.maxTitle) ?? "(untitled)"
                let convId = (conv["conversation_id"] as? String) ?? (conv["id"] as? String) ?? title
                let convTime = (conv["create_time"] as? NSNumber)?.doubleValue
                for nodeId in mapping.keys.sorted() {
                    guard let node = mapping[nodeId] as? [String: Any], let msg = node["message"] as? [String: Any],
                          let author = msg["author"] as? [String: Any], (author["role"] as? String) == "user" else { continue }
                    if let content = msg["content"] as? [String: Any], let ct = content["content_type"] as? String, ct != "text", ct != "multimodal_text" { continue }   // settings and context blocks are not turns
                    guard let seconds = (msg["create_time"] as? NSNumber)?.doubleValue ?? convTime, seconds > 0 else { out.skipped += 1; continue }
                    let turn = (msg["id"] as? String) ?? nodeId
                    out.rows.append(row(id: "chatgpt:" + Hash.hex(convId + "\n" + turn), title: title, date: Date(timeIntervalSince1970: seconds), source: "ChatGPT export",
                                        locator: "chatgpt-export:" + Hash.hex(convId).prefix(12), kind: .ai, via: "chatgpt"))
                }
            } else if let messages = conv["chat_messages"] as? [Any] {                  // Claude
                out.format = "claude"
                let title = Clean.text(conv["name"], max: Clean.maxTitle) ?? "(untitled)"
                let convId = (conv["uuid"] as? String) ?? title
                for (i, m) in messages.enumerated() {
                    guard let msg = m as? [String: Any], (msg["sender"] as? String) == "human" else { continue }
                    guard let date = Dates.parse(msg["created_at"])?.date else { out.skipped += 1; continue }
                    let turn = (msg["uuid"] as? String) ?? String(i)
                    out.rows.append(row(id: "claude:" + Hash.hex(convId + "\n" + turn), title: title, date: date, source: "Claude export",
                                        locator: "claude-export:" + Hash.hex(convId).prefix(12), kind: .ai, via: "claude"))
                }
            } else { out.skipped += 1 }
            if out.rows.count >= Clean.maxRows { break }
        }
        if out.format.isEmpty { out.problem = "this is not a ChatGPT or Claude conversations.json" }
        return out
    }

    /// Reads a .mbox file's headers only: Subject, Date, Message-ID and, in a Gmail Takeout file, X-Gmail-Labels (to
    /// tell Sent from Inbox). Bodies are passed over. Addresses are never kept; the Message-ID is stored as a hash.
    static func mbox(_ url: URL, name: String, maxBytes: Int = 1024 * 1024 * 1024, maxMessages: Int = 50_000) -> Parsed {
        var out = Parsed(); out.format = "mbox"
        guard let h = FileHandle(forReadingAtPath: url.path) else { out.problem = "cannot be read"; return out }
        defer { h.closeFile() }
        var index = 0, inHeaders = false, headers: [String] = [], read = 0, pending = Data()
        let boxName = Clean.text(name, max: 40) ?? "mbox"
        func finish() {
            guard !headers.isEmpty else { return }
            index += 1
            var fields: [String: String] = [:], unfolded: [String] = []
            for l in headers { if (l.hasPrefix(" ") || l.hasPrefix("\t")), !unfolded.isEmpty { unfolded[unfolded.count - 1] += " " + l.trimmingCharacters(in: .whitespaces) } else { unfolded.append(l) } }
            for l in unfolded { if let c = l.firstIndex(of: ":") { let k = l[..<c].lowercased(); if fields[k] == nil { fields[k] = String(l[l.index(after: c)...]).trimmingCharacters(in: .whitespaces) } } }
            headers = []
            guard let subject = Clean.text(decodeWords(fields["subject"] ?? ""), max: Clean.maxTitle), let date = mailDate(fields["date"] ?? "") else { out.skipped += 1; return }
            let labels = (fields["x-gmail-labels"] ?? "").lowercased()
            let gmail = fields["x-gmail-labels"] != nil
            let box = labels.contains("sent") || labels.contains("보낸") ? "Sent" : (gmail ? "Inbox" : boxName)       // Gmail labels may be localised
            let key = fields["message-id"].map { Hash.hex($0) } ?? Hash.hex(subject + "\n" + Dates.isoString(date))
            out.rows.append(row(id: "mbox:" + key, title: subject, date: date, source: (gmail ? "Gmail Takeout " : "Mail export ") + box, locator: "mbox-export:" + key.prefix(12), kind: .mail, via: "mbox"))
        }
        func line(_ raw: Data) {
            let l = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if l.hasPrefix("From ") && !inHeaders { finish(); inHeaders = true; return }
            if inHeaders { if l.isEmpty { inHeaders = false; finish() } else if headers.count < 400 { headers.append(String(l.prefix(4000))) } }
        }
        while read < maxBytes && out.rows.count < maxMessages {
            let chunk = h.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            read += chunk.count
            pending.append(chunk)
            while let nl = pending.firstIndex(of: 0x0A) { line(pending[pending.startIndex..<nl]); pending = Data(pending[pending.index(after: nl)...]) }
            if pending.count > 1 << 20 { pending = Data() }        // a body line this long is passed over
        }
        if !pending.isEmpty { line(pending) }
        if inHeaders { finish() }
        return out
    }

    /// RFC 2047 encoded words (=?charset?B|Q?…?=), as in mail subjects.
    static func decodeWords(_ s: String) -> String {
        guard s.contains("=?") else { return s }
        let joined = s.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
        let rx = try! NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#)
        var out = joined
        let ns = joined as NSString
        for m in rx.matches(in: joined, range: NSRange(location: 0, length: ns.length)).reversed() {
            let charset = ns.substring(with: m.range(at: 1)), mode = ns.substring(with: m.range(at: 2)).uppercased(), body = ns.substring(with: m.range(at: 3))
            var bytes: Data?
            if mode == "B" { var b = body; while b.count % 4 != 0 { b += "=" }; bytes = Data(base64Encoded: b) }
            else {
                var d = Data(); let chars = Array(body.replacingOccurrences(of: "_", with: " ").utf8); var i = 0
                while i < chars.count { if chars[i] == 61, i + 2 < chars.count, let v = UInt8(String(bytes: chars[(i + 1)...(i + 2)], encoding: .ascii) ?? "", radix: 16) { d.append(v); i += 3 } else { d.append(chars[i]); i += 1 } }
                bytes = d
            }
            let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            let enc = cf == kCFStringEncodingInvalidId ? String.Encoding.utf8 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            if let b = bytes, let text = String(data: b, encoding: enc) { out = (out as NSString).replacingCharacters(in: m.range, with: text) }
        }
        return out
    }

    static func mailDate(_ s: String) -> Date? {
        let t = s.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "EEE, d MMM yyyy HH:mm:ss zzz"] { f.dateFormat = fmt; if let d = f.date(from: t) { return d } }
        return Dates.parse(t)?.date
    }

    /// Normalised JSON lines export: rows { id, title, date, topics, source, locator, kind? } are checked like a feed.
    static func jsonl(_ url: URL, defaultKind: RecordType) -> Parsed {
        var out = Parsed(); out.format = "jsonl"
        let f = Reader.regularFile(url, max: Clean.maxFileBytes)
        guard let data = f.data else { out.problem = f.problem; return out }
        var rows: [[String: Any]] = []
        let r = Reader.jsonl(data) { o in
            guard let e = Reader.evidenceRow(.mail, .mail)(o) else { return nil }
            let kind = (o["kind"] as? String).flatMap { RecordType(rawValue: $0) }.flatMap { $0 == .file ? nil : $0 } ?? defaultKind
            var row: [String: Any] = ["id": e.id, "title": e.title, "date": e.dayOnly ? Dates.day(e.date) : Dates.isoString(e.date), "topics": e.topics, "source": e.source, "locator": e.locator, "kind": kind.rawValue, "via": "jsonl"]
            if e.derivedTitle { row["derivedTitle"] = true }                       // the flag travels with an imported row
            rows.append(row)
            return e
        }
        out.rows = rows; out.skipped = r.skipped
        return out
    }

    /// The ids already in imports/, so that importing the same export again adds nothing.
    static func existingIDs(_ places: Places) -> Set<String> { Set(Reader.imports(places).loaded.rows.map { $0.id }) }

    /// Saves the rows that are not there yet as a NEW file in imports/ (0600 in a 0700 folder), each with the import
    /// time. The file is written under a temporary name, synced, and then given its final name with link(), which
    /// fails rather than replace an existing file; no other source file is opened for writing at all.
    static func save(_ parsed: Parsed, name: String, places: Places, now: Date = Date()) -> Result {
        if let p = parsed.problem { return Result(imported: 0, duplicates: 0, skipped: parsed.skipped, file: nil, problem: p) }
        let have = existingIDs(places)
        var seen = Set<String>(), fresh: [[String: Any]] = []
        for r in parsed.rows { guard let id = r["id"] as? String else { continue }; if have.contains(id) || !seen.insert(id).inserted { continue }; fresh.append(r) }
        let duplicates = parsed.rows.count - fresh.count
        guard !fresh.isEmpty else {
            return Result(imported: 0, duplicates: duplicates, skipped: parsed.skipped, file: nil, problem: parsed.rows.isEmpty ? "there is nothing in it that can be imported" : nil)
        }
        let fm = FileManager.default
        do { try fm.createDirectory(at: places.imports, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) } catch { return Result(imported: 0, duplicates: duplicates, skipped: parsed.skipped, file: nil, problem: "the imports folder could not be created") }
        let stamp = Dates.isoString(now).replacingOccurrences(of: ":", with: "")
        let base = Topic.key(name).replacingOccurrences(of: #"[^a-z0-9가-힣]+"#, with: "-", options: .regularExpression).prefix(40)
        let unique = UUID().uuidString.prefix(6)
        let target = places.imports.appendingPathComponent("import-\(stamp)-\(unique)-\(parsed.format)-\(base).jsonl")
        let temporary = places.imports.appendingPathComponent(".writing-\(unique).tmp")
        let at = Dates.isoString(now)
        var text = ""
        for var r in fresh { r["importedAt"] = at; if let d = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) { text += String(decoding: d, as: UTF8.self) + "\n" } }
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return Result(imported: 0, duplicates: duplicates, skipped: parsed.skipped, file: nil, problem: "a new file could not be created") }
        let bytes = Array(text.utf8)
        let written = bytes.withUnsafeBytes { write(fd, $0.baseAddress, bytes.count) }
        fsync(fd); close(fd)
        defer { unlink(temporary.path) }
        guard written == bytes.count else { return Result(imported: 0, duplicates: duplicates, skipped: parsed.skipped, file: nil, problem: "writing failed") }
        guard link(temporary.path, target.path) == 0 else { return Result(imported: 0, duplicates: duplicates, skipped: parsed.skipped, file: nil, problem: "a file with that name exists, so nothing was written") }
        return Result(imported: fresh.count, duplicates: duplicates, skipped: parsed.skipped, file: target, problem: nil)
    }
}

// MARK: - The optional refresh tool (a fixed, user-installed program; never a path from data)

enum RefreshTool {
    /// Usable only if it is a regular file (not a link) owned by this user, executable, not writable by group or
    /// others, in a folder owned by this user that is not writable by group or others.
    static func check(_ url: URL) -> (ok: Bool, reason: String) {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return (false, "no tool installed (~/WorkIndex/horizon-tools/refresh.command)") }
        if st.st_mode & S_IFMT == S_IFLNK { return (false, "the tool is a link, so it is not run") }
        guard st.st_mode & S_IFMT == S_IFREG else { return (false, "the tool is not a file") }
        guard st.st_uid == getuid() else { return (false, "the tool is not owned by you") }
        guard st.st_mode & 0o022 == 0 else { return (false, "other users can change the tool, so it is not run") }
        guard st.st_mode & 0o100 != 0 else { return (false, "the tool is not executable") }
        var dir = stat()
        guard lstat(url.deletingLastPathComponent().path, &dir) == 0, dir.st_mode & S_IFMT == S_IFDIR, dir.st_uid == getuid(), dir.st_mode & 0o022 == 0 else { return (false, "the tool's folder is not safe (owner or permissions)") }
        return (true, "ready — runs with no arguments, after you confirm each time (your own tool that recollects the file and AI feeds)")
    }

    /// Runs the tool with no arguments and no shell, waits at most `timeout`, then calls back with its exit status.
    /// Called only after the person confirmed in the window; the path is the fixed one from Places.
    static func run(_ url: URL, timeout: TimeInterval = 600, done: @escaping (Int32?, String) -> Void) {
        let check = check(url)
        guard check.ok else { done(nil, check.reason); return }
        let p = Process()
        p.executableURL = url
        p.arguments = []
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.currentDirectoryURL = url.deletingLastPathComponent()
        let finished = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in finished.signal() }
        do { try p.run() } catch { done(nil, "it could not be started"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            if finished.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); done(nil, "stopped after timing out"); return }
            done(p.terminationStatus, p.terminationStatus == 0 ? "finished" : "ended with an error (\(p.terminationStatus))")
        }
    }
}

// MARK: - Settings (window length and source switches; persisted)

protocol SettingsStore: AnyObject {
    func integer(_ key: String) -> Int?
    func set(_ value: Int, _ key: String)
    func bool(_ key: String) -> Bool?
    func set(_ value: Bool, _ key: String)
    func string(_ key: String) -> String?
    func set(_ value: String, _ key: String)
}
final class DefaultsStore: SettingsStore {
    private let d = UserDefaults.standard
    func integer(_ key: String) -> Int? { d.object(forKey: key) == nil ? nil : d.integer(forKey: key) }
    func set(_ value: Int, _ key: String) { d.set(value, forKey: key) }
    func bool(_ key: String) -> Bool? { d.object(forKey: key) == nil ? nil : d.bool(forKey: key) }
    func set(_ value: Bool, _ key: String) { d.set(value, forKey: key) }
    func string(_ key: String) -> String? { d.string(forKey: key) }
    func set(_ value: String, _ key: String) { d.set(value, forKey: key) }
}
final class MemoryStore: SettingsStore {
    var values: [String: Any] = [:]
    func integer(_ key: String) -> Int? { values[key] as? Int }
    func set(_ value: Int, _ key: String) { values[key] = value }
    func bool(_ key: String) -> Bool? { values[key] as? Bool }
    func set(_ value: Bool, _ key: String) { values[key] = value }
    func string(_ key: String) -> String? { values[key] as? String }
    func set(_ value: String, _ key: String) { values[key] = value }
}
struct Preferences {
    let store: SettingsStore
    var months: Int { get { store.integer("windowMonths") == 6 ? 6 : 3 } nonmutating set { store.set(newValue == 6 ? 6 : 3, "windowMonths") } }
    func isOn(_ k: SourceKind) -> Bool { store.bool("source." + k.rawValue) ?? true }
    func set(_ k: SourceKind, _ on: Bool) { store.set(on, "source." + k.rawValue) }
    var enabled: Set<SourceKind> { Set(SourceKind.allCases.filter(isOn)) }

    /// The third choice beside 3 and 6 months: a custom period, kept as two days (YYYY-MM-DD).
    var usesCustom: Bool { get { store.bool("windowCustom") ?? false } nonmutating set { store.set(newValue, "windowCustom") } }
    func customDays(calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard let a = Dates.parse(store.string("customStart"), calendar: calendar), let b = Dates.parse(store.string("customEnd"), calendar: calendar), a.dayOnly, b.dayOnly else { return nil }
        return (a.date, b.date)
    }
    func setCustom(start: Date, end: Date, calendar: Calendar = .current) {
        store.set(Dates.day(start, calendar), "customStart"); store.set(Dates.day(end, calendar), "customEnd"); usesCustom = true
    }
    /// The period in force now. A stored custom period is checked again each time; if it is missing or no longer
    /// acceptable, the 3 or 6 month preset is used and the reason is returned so the window can say so.
    func window(now: Date, calendar: Calendar = .current) -> (window: HorizonWindow, note: String?) {
        guard usesCustom else { return (HorizonWindow(months: months, now: now, calendar: calendar), nil) }
        guard let c = customDays(calendar: calendar) else { return (HorizonWindow(months: months, now: now, calendar: calendar), "The saved custom period could not be read; showing \(months) months.") }
        switch CustomPeriod.validate(start: c.start, end: c.end, now: now, calendar: calendar) {
        case .ok(let s, let e, _): return (HorizonWindow(customStart: s, customEnd: e, now: now, calendar: calendar), nil)
        case .refused(let why): return (HorizonWindow(months: months, now: now, calendar: calendar), "The saved custom period cannot be used; showing \(months) months — " + why)
        }
    }
}
