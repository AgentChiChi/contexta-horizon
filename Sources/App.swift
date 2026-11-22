// Contexta Horizon — the menu-bar app.
// The everyday screen is the simple one (Simple.swift): "What do you want to continue?" → a suggested topic → the exact short
// handoff shown inline → one Copy button, which is the only place the clipboard is written. A click on the menu-bar
// icon, or opening the app, shows that screen; a right-click shows a small menu with Quit.
// This file holds the app delegate and the dashboard ("Sources & Settings"): the period, the source switches, coverage, the
// evidence tables, "Read Sources" (which can include Mail, after a yes on its sheet), imports and the refresh tool —
// everything opt-in, reached from one link. Reading, computing topics and asking Mail all happen off the main thread:
// both windows open at once and show that they are still reading.
// There is no always-on model, no key or file watcher, nothing injected or sent, and no network code.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var dashboard: HorizonController?
    private var simple: SimpleController?
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let own = Bundle.main.bundleIdentifier {
            let me = ProcessInfo.processInfo.processIdentifier
            if NSRunningApplication.runningApplications(withBundleIdentifier: own).contains(where: { $0.processIdentifier != me }) { NSApp.terminate(nil); return }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = ThreadGlyph.menuImage()                      // the continued-thread mark, as a template image (Glyph.swift)
            button.title = ""
            button.toolTip = "Contexta Horizon — What do you want to continue? (Right-click for the menu)"
            button.setAccessibilityLabel("Contexta Horizon, work context")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])        // left: the simple screen; right: the menu
        }
        menu.addItem(withTitle: "Open Work Context", action: #selector(openSimple), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Sources & Settings…", action: #selector(openDashboard), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Contexta Horizon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = item

        let dashboard = HorizonController(places: Places.standard(), preferences: Preferences(store: DefaultsStore()))
        let simple = SimpleController(dashboard: dashboard)
        dashboard.onChange = { [weak simple] in simple?.refresh() }
        dashboard.onBack = { [weak simple] in simple?.show() }
        dashboard.onUseTopic = { [weak simple] key in simple?.show(pick: key) }
        self.dashboard = dashboard; self.simple = simple
        simple.show()                                                   // opened from Finder: the simple screen
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { simple?.show(); return false }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else { simple?.show() }
    }
    @objc private func openSimple() { simple?.show() }
    @objc private func openDashboard() { dashboard?.show() }
}

final class HorizonController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let places: Places
    private let preferences: Preferences
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 700), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    private var snapshot: Snapshot?
    private var horizon = HorizonWindow(months: 3, now: Date())
    private var topics: [TopicSummary] = []
    private var selected: TopicSummary?
    private var busy = false
    private var reads = 0                               // the number of the latest read asked for
    private var readingFor: Set<SourceKind>?            // the switches the read under way was asked for
    private var staleReads = 0                          // answers that arrived after a later request and were dropped
    private var afterRead: String?                      // an import's or collection's result, kept in the status line after the read that follows
    private var computes = 0                            // the number of the latest topic computation asked for
    private var computing = false                       // a computation is running off the main thread
    private var staleComputes = 0
    private var collecting = false                      // the Mail question is on screen, or a collection is under way
    private var mailSheet: NSAlert?
    private var mailAsks = 0                            // how often the Mail question was put (for the tests)
    /// Topics for more records than this are worked out off the main thread (with progress shown); fewer are instant.
    /// Kept low: working them out on the main thread is only for snapshots small enough not to be felt.
    var inlineLimit = 400
    private var joinedPresses = 0                       // presses of "Read Sources" that joined a read already under way
    /// The Mac's side of a Mail collection. The app uses the live one; the tests put a mock here.
    var mailSide = MailAdapter.Side.live
    /// For the tests only: run on the background queue just before a read (to make one slow), and after topics were applied.
    var onBackgroundRead: (() -> Void)?
    var onApplied: (() -> Void)?
    /// Called after each read (used by the synthetic window smoke test).
    var onRead: (() -> Void)?
    /// Called whenever the topics, the period or the coverage changed (the simple screen follows).
    var onChange: (() -> Void)?
    /// "Back to simple view" and "Open in simple view": back to the everyday screen, optionally with a topic chosen here.
    var onBack: (() -> Void)?
    var onUseTopic: ((String) -> Void)?

    // What the simple screen shows is exactly what this dashboard computed (same period, same switches).
    var isLoaded: Bool { snapshot != nil }
    /// Reading or computing right now (both windows show progress while this is true).
    var isWorking: Bool { busy || computing }
    var isComputing: Bool { computing }
    var currentTopics: [TopicSummary] { topics }
    var currentWindow: HorizonWindow { horizon }
    var currentCoverage: [SourceCoverage] { coverages }
    /// Starts the first read if there is none yet — and none under way: reopening a window while it is still reading
    /// does not start another.
    func ensureLoaded() { if snapshot == nil && !busy { reread(nil) } }

    private let months = NSSegmentedControl(labels: ["3 months", "6 months", "Custom"], trackingMode: .selectOne, target: nil, action: nil)
    private let startPicker = NSDatePicker(), endPicker = NSDatePicker()
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let customFeedback = HorizonController.label("", size: 12, soft: true)
    private let customRow = NSStackView()
    private let readButton = NSButton(title: "Read Sources", target: nil, action: nil)
    private let importButton = NSButton(title: "Import…", target: nil, action: nil)
    private let toolButton = NSButton(title: "Refresh Feeds…", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let copyButton = NSButton(title: "Open in Simple View", target: nil, action: nil)
    private let backButton = NSButton(title: "‹ Simple View", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private var coverages: [SourceCoverage] = []
    private let windowLabel = HorizonController.label("", size: 12, soft: true)
    private let statusLabel = HorizonController.label("", size: 12, soft: true)
    private let toolLabel = HorizonController.label("", size: 11, soft: true)
    private let evidenceHeader = HorizonController.label("Evidence — choose a topic on the left", size: 13, soft: false)
    private var sourceChecks: [SourceKind: NSButton] = [:]
    private var sourceLabels: [SourceKind: NSTextField] = [:]
    private let topicTable = NSTableView()
    private let evidenceTable = NSTableView()
    private let split = NSSplitView()
    private var placedDivider = false

    init(places: Places, preferences: Preferences) {
        self.places = places
        self.preferences = preferences
        super.init()
        build()
    }

    private static func label(_ text: String, size: CGFloat, soft: Bool) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size)
        l.textColor = soft ? .secondaryLabelColor : .labelColor
        l.isSelectable = false
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func build() {
        window.title = "Contexta Horizon — Sources & Settings"
        window.minSize = NSSize(width: 960, height: 540)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let title = HorizonController.label("Sources & Settings", size: 17, soft: false)
        months.selectedSegment = preferences.usesCustom ? 2 : (preferences.months == 6 ? 1 : 0)
        months.target = self; months.action = #selector(monthsChanged)
        // Custom: two whole days, both included
        for picker in [startPicker, endPicker] {
            picker.datePickerStyle = .textFieldAndStepper; picker.datePickerElements = .yearMonthDay
            picker.locale = Locale(identifier: "ko_KR"); picker.calendar = Calendar.current
        }
        startPicker.setAccessibilityLabel("Start date"); endPicker.setAccessibilityLabel("End date")
        applyButton.target = self; applyButton.action = #selector(applyCustom); applyButton.bezelStyle = .rounded
        applyButton.toolTip = "Applies the period from the start date through the end date, both included (up to 6 months, no later than today)"
        let startLabel = HorizonController.label("Start", size: 12, soft: false), endLabel = HorizonController.label("End", size: 12, soft: false)
        for v in [startLabel, startPicker, endLabel, endPicker, applyButton, customFeedback] as [NSView] { customRow.addArrangedSubview(v) }
        customRow.orientation = .horizontal; customRow.spacing = 8; customRow.alignment = .centerY
        customRow.isHidden = !preferences.usesCustom
        fillPickers()
        months.setAccessibilityLabel("Period")
        for (b, sel) in [(readButton, #selector(readSources(_:))), (importButton, #selector(importExport)), (toolButton, #selector(runTool)), (copyButton, #selector(useInSimple)), (backButton, #selector(goBack))] { b.target = self; b.action = sel; b.bezelStyle = .rounded }
        readButton.keyEquivalent = "\r"                                 // the primary action of this window
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        spinner.setAccessibilityLabel("Reading sources")
        quitButton.target = NSApp; quitButton.action = #selector(NSApplication.terminate(_:)); quitButton.bezelStyle = .rounded
        backButton.toolTip = "Back to the “What do you want to continue?” screen"
        readButton.toolTip = "Reads again, now, the local sources that are switched on. If Imports, AI chats and Mail are all on and the Mail app is already running, it then asks whether to also collect recent subjects and dates from Mail (no bodies or addresses; Mail is never opened for you)"
        importButton.toolTip = "Imports an export file from this Mac: a ChatGPT or Claude conversations.json, an Apple Mail or Gmail Takeout .mbox, or a normalized .jsonl (saved as a new file; records already imported are skipped)"
        copyButton.toolTip = "Opens the selected topic in the simple view. Copying happens only there, with its Copy button."
        copyButton.isEnabled = false
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [backButton, title, months, spacer, spinner, readButton, importButton, toolButton])
        top.orientation = .horizontal; top.spacing = 10; top.alignment = .centerY

        let sources = NSStackView(); sources.orientation = .vertical; sources.alignment = .leading; sources.spacing = 4
        for kind in SourceKind.allCases {
            let check = NSButton(checkboxWithTitle: kind.label, target: self, action: #selector(sourceToggled(_:)))
            check.state = preferences.isOn(kind) ? .on : .off
            check.tag = SourceKind.allCases.firstIndex(of: kind) ?? 0
            check.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let text = HorizonController.label("Not read yet", size: 12, soft: true)
            let row = NSStackView(views: [check, text]); row.orientation = .horizontal; row.alignment = .firstBaseline; row.spacing = 6
            sources.addArrangedSubview(row)
            sourceChecks[kind] = check; sourceLabels[kind] = text
        }

        configure(topicTable, columns: [("topic", "Topic", 110), ("types", "Types", 150), ("count", "Records", 52), ("signal", "Direct / Inferred", 96), ("last", "Latest", 88)])
        configure(evidenceTable, columns: [("date", "Record date", 118), ("type", "Type", 40), ("signal", "Signal", 56), ("title", "Title", 200), ("source", "Source", 110), ("imported", "Origin · imported", 160)])
        topicTable.setAccessibilityLabel("Topics"); evidenceTable.setAccessibilityLabel("Evidence")
        let left = scroll(topicTable), right = scroll(evidenceTable)
        let copyNote = HorizonController.label("Copying happens only in the simple view. No always-on model · nothing is injected · title counts are signals, not proof of completed work.", size: 11, soft: true)
        let copySpacer = NSView(); copySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let copyRow = NSStackView(views: [copyButton, copyNote, copySpacer, quitButton]); copyRow.orientation = .horizontal; copyRow.spacing = 8
        let rightStack = NSStackView(views: [evidenceHeader, right, copyRow]); rightStack.orientation = .vertical; rightStack.alignment = .leading; rightStack.spacing = 6
        right.widthAnchor.constraint(equalTo: rightStack.widthAnchor).isActive = true
        copyRow.widthAnchor.constraint(equalTo: rightStack.widthAnchor).isActive = true
        split.isVertical = true; split.dividerStyle = .thin
        split.addArrangedSubview(left); split.addArrangedSubview(rightStack)
        let leftWidth = left.widthAnchor.constraint(equalToConstant: 520); leftWidth.priority = .defaultHigh; leftWidth.isActive = true
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        let root = NSStackView(views: [top, customRow, windowLabel, sources, toolLabel, split, statusLabel])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                     root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                                     top.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32), split.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32)])
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = content
        statusLabel.stringValue = "Local only — reads files on this Mac and uses no network."
        updateTool()
    }

    private func configure(_ table: NSTableView, columns: [(String, String, CGFloat)]) {
        for (id, title, width) in columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; c.minWidth = 36
            table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.rowHeight = 22
    }
    private func scroll(_ table: NSTableView) -> NSScrollView {
        let s = NSScrollView(); s.documentView = table; s.hasVerticalScroller = true; s.hasHorizontalScroller = true; s.borderType = .bezelBorder
        s.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return s
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !placedDivider { placedDivider = true; window.layoutIfNeeded(); split.setPosition(520, ofDividerAt: 0) }   // room for all five topic columns
        ensureLoaded()
    }

    // MARK: actions (each one starts from a click)

    @objc private func monthsChanged() {
        if months.selectedSegment == 2 {
            // Custom: show the two days (the last ones used, or the current 3-month span) and apply them
            customRow.isHidden = false
            fillPickers()
            applyCustom()
        } else {
            preferences.usesCustom = false
            preferences.months = months.selectedSegment == 1 ? 6 : 3
            customRow.isHidden = true
            customFeedback.stringValue = ""
            recompute()
        }
    }

    /// The pickers show the stored custom days, or the 3-month preset's days when none were chosen yet.
    private func fillPickers() {
        let now = Date(), preset = HorizonWindow(months: 3, now: now)
        let stored = preferences.customDays()
        startPicker.dateValue = stored?.start ?? preset.start
        endPicker.dateValue = stored?.end ?? preset.today
        startPicker.maxDate = now; endPicker.maxDate = now
    }

    /// Apply: the two days are checked (not reversed, not in the future, at most six calendar months). A refused
    /// period changes nothing and says why; an accepted one is saved and used for topics, coverage and the handoff.
    @objc private func applyCustom() {
        let check = CustomPeriod.validate(start: startPicker.dateValue, end: endPicker.dateValue, now: Date())
        customFeedback.stringValue = check.message
        customFeedback.textColor = check.isOK ? .secondaryLabelColor : .systemRed
        guard case .ok(let s, let e, _) = check else {
            if !preferences.usesCustom || preferences.customDays() == nil { months.selectedSegment = preferences.months == 6 ? 1 : 0 }   // nothing valid to show yet: stay on the preset
            return
        }
        preferences.setCustom(start: s, end: e)
        months.selectedSegment = 2
        recompute()
    }

    /// A switch decides what is read, not only what is shown. Turned off: what it excludes leaves the snapshot in
    /// memory at once and nothing is read. Turned on: what is newly allowed has to be read, so a read is started —
    /// unless the read already under way was asked for with these switches.
    @objc private func sourceToggled(_ sender: NSButton) {
        let kind = SourceKind.allCases[sender.tag]
        preferences.set(kind, sender.state == .on)
        let enabled = preferences.enabled
        snapshot = snapshot?.restricted(to: enabled)
        let have = busy ? readingFor : snapshot?.readFor
        if let have = have, !enabled.isSubset(of: have) { reread(nil) } else { recompute() }
    }

    /// Reads what the switches allow at this moment (Snapshot.read opens nothing else). Each request gets a number;
    /// when its answer arrives and a later request exists, the answer is stale and dropped unseen. A switch turned
    /// off while reading is applied to the answer before it is kept, so nothing excluded is ever cached.
    @objc func reread(_ sender: Any?) {
        reads += 1
        let request = reads, places = self.places, enabled = preferences.enabled
        busy = true; readingFor = enabled; statusLabel.stringValue = "Reading sources…"
        if snapshot == nil { for k in SourceKind.allCases { sourceLabels[k]?.stringValue = preferences.isOn(k) ? "Reading…" : "Off — not used in the results" } }
        progress()
        onChange?()                                                    // the simple view shows that reading is going on
        let before = onBackgroundRead
        DispatchQueue.global(qos: .userInitiated).async {
            before?()
            let snap = Snapshot.read(places, enabled: enabled)
            DispatchQueue.main.async {
                guard request == self.reads else { self.staleReads += 1; return }
                self.busy = false; self.readingFor = nil; self.progress()
                self.snapshot = snap.restricted(to: self.preferences.enabled)
                self.statusLabel.stringValue = (self.afterRead.map { $0 + " · " } ?? "") + "Sources read: " + Dates.minute(snap.readAt) + (snap.manifest.problem.map { " · manifest: " + $0 } ?? "")
                self.afterRead = nil
                self.recompute()
                self.updateTool()
                self.onRead?()
            }
        }
    }

    /// What an import or a Mail collection reported, with a word when a switch keeps the new records out of view.
    /// Importing and collecting are the person's own actions and are never held back by a switch.
    private func keepForStatus(_ message: String) {
        let hidden = [SourceKind.imports, .ai, .mail].filter { !preferences.isOn($0) }.map { $0.label }      // imports are read only while all three are on
        afterRead = message + (hidden.isEmpty ? "" : " (not shown while " + hidden.joined(separator: " and ") + (hidden.count == 1 ? " is" : " are") + " switched off)")
        statusLabel.stringValue = afterRead ?? message
    }

    /// For the synthetic window smoke test: what the window shows now, and selecting a topic row as a click would.
    var smokeWindow: NSWindow { window }
    /// Chooses Custom and applies two days as the Apply button does; or chooses a preset segment as a click does.
    func smokeApplyCustom(start: Date, end: Date) { months.selectedSegment = 2; customRow.isHidden = false; startPicker.maxDate = nil; endPicker.maxDate = nil; startPicker.dateValue = start; endPicker.dateValue = end; applyCustom() }
    func smokeChoosePreset(_ segment: Int) { months.selectedSegment = segment; monthsChanged() }
    func smokeUseInSimple() { useInSimple() }
    /// Clicks a source switch as a person would; presses "Reread Sources"; and what the reads came to.
    func smokeToggle(_ kind: SourceKind, _ on: Bool) { if let c = sourceChecks[kind] { c.state = on ? .on : .off; sourceToggled(c) } }
    func smokeReread() { reread(nil) }
    /// Presses "Read Sources" as a click would; answers the Mail sheet as a click on one of its buttons would; and what the Mail side came to.
    func smokeReadSources() { readSources(nil) }
    func smokeAnswerMailSheet(collect: Bool) { if let sheet = mailSheet { window.endSheet(sheet.window, returnCode: collect ? .alertSecondButtonReturn : .alertFirstButtonReturn) } }
    var smokeMail: (asks: Int, sheetUp: Bool, collecting: Bool) { (mailAsks, mailSheet != nil, collecting) }
    var smokeSheetWindow: NSWindow? { mailSheet?.window }
    var smokeSheetText: String { mailSheet.map { $0.messageText + " [" + $0.buttons.map { $0.title }.joined(separator: " | ") + "]" } ?? "" }
    var smokeComputes: (asked: Int, stale: Int, working: Bool) { (computes, staleComputes, computing) }
    var smokeJoinedPresses: Int { joinedPresses }
    var smokeReads: (asked: Int, stale: Int, busy: Bool) { (reads, staleReads, busy) }
    /// What is held in memory right now, by where it came from and by record type (nothing excluded may be here).
    var smokeHeld: String { guard let s = snapshot else { return "none" }; return SourceKind.allCases.map { k in "\(k.rawValue):\(s.evidence.filter { $0.origin == k }.count)" }.joined(separator: " ") + " | " + RecordType.allCases.map { t in "\(t.rawValue):\(s.evidence.filter { $0.type == t }.count)" }.joined(separator: " ") }
    func smokeBack() { goBack() }
    /// Selects a topic row by the topic's key, as a click on that row would (never by a fixed row number: the order
    /// changes with the period and the switches). Answers the row it was found at, or nil when it is not in view.
    @discardableResult
    func smokeSelect(key: String) -> Int? {
        guard let row = topics.firstIndex(where: { $0.key == key }) else { return nil }
        topicTable.selectRowIndexes([row], byExtendingSelection: false)
        return row
    }
    var smokeSelectedKey: String? { selected?.key }
    var smokeTopicKeys: [String] { topics.map { $0.key } }
    func smokeState() -> [String] {
        var out = ["title=" + window.title, "period=" + (months.label(forSegment: months.selectedSegment) ?? "") + " [" + (0..<months.segmentCount).map { months.label(forSegment: $0) ?? "" }.joined(separator: ",") + "]",
                   "customRow=" + (customRow.isHidden ? "hidden" : "shown") + " feedback=" + customFeedback.stringValue,
                   "window=" + windowLabel.stringValue, "topics=\(topicTable.numberOfRows)", "evidence=\(evidenceTable.numberOfRows)", "copyEnabled=\(copyButton.isEnabled)",
                   "buttons=" + [readButton, importButton, toolButton, copyButton].map { $0.title }.joined(separator: ","), "status=" + statusLabel.stringValue, "spinner=\(isWorking || (collecting && mailSheet == nil))", "preview=" + (selected.map { Export.simple(task: "", topic: $0, window: horizon, coverage: coverages) } ?? ""), "tool=" + toolLabel.stringValue, "header=" + evidenceHeader.stringValue]
        for k in SourceKind.allCases { out.append("source." + k.rawValue + "=" + (sourceChecks[k]?.title ?? "") + ": " + (sourceLabels[k]?.stringValue ?? "")) }
        return out
    }

    @objc private func importExport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = true     // Apple Mail exports "Name.mbox" as a folder
        panel.message = "Choose an export to import: a ChatGPT or Claude conversations.json, an Apple Mail or Gmail Takeout .mbox, or a normalized .jsonl. Only titles and dates are read; no message text is stored."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var kind = RecordType.mail
        if url.pathExtension.lowercased() == "jsonl" {
            let ask = NSAlert(); ask.messageText = "What kind of records does this .jsonl hold?"; ask.informativeText = "If a row has its own “kind”, that value is used."
            ask.addButton(withTitle: "Mail"); ask.addButton(withTitle: "AI Chats"); ask.addButton(withTitle: "Cancel")
            let answer = ask.runModal()
            if answer == .alertThirdButtonReturn { return }
            kind = answer == .alertSecondButtonReturn ? .ai : .mail
        }
        statusLabel.stringValue = "Importing…"
        let places = self.places
        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = Importer.parse(url, jsonlKind: kind)
            let result = Importer.save(parsed, name: url.deletingPathExtension().lastPathComponent, places: places)
            DispatchQueue.main.async {
                self.statusLabel.stringValue = HorizonController.describe(result, what: "Imported as a snapshot")
                if result.problem == nil { self.keepForStatus(self.statusLabel.stringValue); self.reread(nil) }
            }
        }
    }

    private static func describe(_ r: Importer.Result, what: String) -> String {
        if let p = r.problem { return "Not imported — " + p }
        if r.imported == 0 { return "Nothing new to import — \(plural(r.duplicates, "record")) already imported were not added again" }
        return "\(what): \(r.imported) new" + (r.duplicates > 0 ? " · \(r.duplicates) already there, skipped" : "") + (r.skipped > 0 ? " · \(r.skipped) could not be read" : "")
    }

    /// "Read Sources", the window's primary button — the one explicit request to read. It reads again the local sources
    /// the switches allow, at once. Mail can be part of it only when Imports, AI chats and Mail are all on and the
    /// Mail app is already running: then a sheet asks, and only a yes there goes on to Mail. In every other case the
    /// local read stands on its own and the status line says why Mail was not part of it. Opening or reopening a
    /// window, a switch, an import and the refresh tool read too, but never come here: they can never reach Mail.
    @objc private func readSources(_ sender: Any?) {
        // A press while a read for these switches is already under way joins that read: it does not start another.
        if busy, let underway = readingFor, preferences.enabled.isSubset(of: underway) { joinedPresses += 1 } else { reread(nil) }
        switch MailAdapter.step(enabled: preferences.enabled, underway: collecting, isRunning: mailSide.isRunning) {
        case .skip(let why): afterRead = "Mail not included: " + why
        case .ask: askAboutMail()
        }
    }

    /// The question, as a sheet on this window (it stops nothing else: the read goes on and the simple view stays usable).
    private func askAboutMail() {
        collecting = true; mailAsks += 1
        let sheet = NSAlert()
        sheet.messageText = "Also collect recent subjects and dates from Mail?"
        sheet.informativeText = "Your local sources are being read now. The Mail app is running, so Horizon can also ask it for the subjects and dates of the newest \(MailAdapter.cap) messages in Inbox and in Sent. No bodies, addresses or account details are read, and nothing is sent. The first time, macOS asks whether to allow this. What is collected is saved on this Mac as a new import file."
        sheet.addButton(withTitle: "Local Sources Only")              // the default: Return leaves Mail alone
        sheet.addButton(withTitle: "Collect from Mail")
        mailSheet = sheet
        sheet.beginSheetModal(for: window) { [weak self] answer in
            self?.mailSheet = nil
            self?.mailAnswered(collect: answer == .alertSecondButtonReturn)
        }
    }

    /// After the sheet. A yes asks Mail — entirely off the main thread (is it still running, does macOS allow it, the
    /// fixed script in the helper process). What comes back is saved only if the switches still allow it at that moment.
    private func mailAnswered(collect: Bool) {
        guard collect else { collecting = false; say("Mail not included: you chose local sources only"); return }
        statusLabel.stringValue = "Asking Mail…"; progress()
        let side = mailSide, places = self.places
        DispatchQueue.global(qos: .userInitiated).async {
            let got = MailAdapter.collect(isRunning: side.isRunning, permission: side.permission, run: side.run)
            DispatchQueue.main.async {
                guard MailAdapter.mayKeep(self.preferences.enabled) else {
                    self.collecting = false; self.say(got.rows.isEmpty ? got.outcome.message : "Collected from Mail but not kept: Imports, AI chats and Mail are no longer all switched on"); return
                }
                guard !got.rows.isEmpty else { self.collecting = false; self.say(got.outcome.message); return }
                DispatchQueue.global(qos: .userInitiated).async {
                    var parsed = Importer.Parsed(); parsed.rows = got.rows; parsed.format = "macmail"
                    let result = Importer.save(parsed, name: "mac-mail", places: places)
                    DispatchQueue.main.async {
                        self.collecting = false
                        let message = got.outcome.message + " · " + HorizonController.describe(result, what: "Saved")
                        if result.file != nil { self.keepForStatus(message); self.reread(nil) } else { self.say(message) }
                    }
                }
            }
        }
    }

    /// A word in the status line now, kept in front of "Sources read: …" if a read is still to finish.
    private func say(_ message: String) {
        if busy { afterRead = message }
        statusLabel.stringValue = busy ? message + " · Reading sources…" : message + (snapshot.map { " · Sources read: " + Dates.minute($0.readAt) } ?? "")
        progress()
    }

    /// The spinner in this window, and the simple view's, follow what is going on.
    private func progress() {
        if isWorking || (collecting && mailSheet == nil) { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    @objc private func runTool() {
        let tool = places.refreshTool
        let check = RefreshTool.check(tool)
        guard check.ok else { updateTool(); return }
        let confirm = NSAlert()
        confirm.messageText = "Run your refresh tool?"
        confirm.informativeText = "\(tool.path)\n\nThis program, which you installed yourself, is run with no arguments. When it finishes, the sources are read again. Horizon never runs any other program."
        confirm.addButton(withTitle: "Cancel"); confirm.addButton(withTitle: "Run")
        guard confirm.runModal() == .alertSecondButtonReturn else { statusLabel.stringValue = "The tool was not run."; return }
        toolButton.isEnabled = false; statusLabel.stringValue = "Refreshing… (refresh.command)"
        RefreshTool.run(tool) { status, message in
            DispatchQueue.main.async {
                self.statusLabel.stringValue = "Refresh: " + message
                self.updateTool()
                if status != nil { self.reread(nil) }
            }
        }
    }

    /// The dashboard copies nothing: the selected topic is handed to the simple screen, where the one Copy button is.
    @objc private func useInSimple() { if let t = selected { onUseTopic?(t.key) } }
    @objc private func goBack() { onBack?() }

    // MARK: state → view

    private func updateTool() {
        let check = RefreshTool.check(places.refreshTool)
        toolButton.isEnabled = check.ok
        toolLabel.stringValue = "Refresh tool: " + check.reason
    }

    /// What the windows show for a snapshot, a period and the switches. A pure computation: it runs on any thread.
    private struct Computed { let window: HorizonWindow; let note: String?; let coverage: [SourceCoverage]; let topics: [TopicSummary] }
    private static func compute(_ snap: Snapshot, _ resolved: (window: HorizonWindow, note: String?), _ enabled: Set<SourceKind>) -> Computed {
        Computed(window: resolved.window, note: resolved.note, coverage: SourceKind.allCases.map { snap.coverage(for: $0, window: resolved.window, enabled: enabled) },
                 topics: Analysis.topics(snap.evidence, window: resolved.window, enabled: enabled))
    }

    /// Works out the topics again after a read, a switch or a change of period. A small snapshot is done on the spot.
    /// A large one is worked out off the main thread while the windows stay usable and show progress; each request has
    /// a number, and a result that arrives after a later request (the period or a switch changed meanwhile) is dropped.
    private func recompute() {
        guard let snap = snapshot else { return }
        computes += 1
        let request = computes, resolved = preferences.window(now: Date()), enabled = preferences.enabled
        if snap.evidence.count <= inlineLimit { computing = false; apply(HorizonController.compute(snap, resolved, enabled)); return }
        // Until the new result is in, nothing of the old one stays on screen: after a switch was turned off or the
        // period narrowed, the old topics, coverage and copy text could show what is no longer allowed.
        computing = true
        horizon = resolved.window
        windowLabel.stringValue = "Period: " + horizon.label + (resolved.note.map { " — " + $0 } ?? "")
        topics = []; coverages = []; selected = nil
        for k in SourceKind.allCases { sourceLabels[k]?.stringValue = enabled.contains(k) ? "Working out topics…" : "Off — not used in the results" }
        topicTable.reloadData(); topicTable.deselectAll(nil)
        showSelection()
        progress(); onChange?()
        DispatchQueue.global(qos: .userInitiated).async {
            let done = HorizonController.compute(snap, resolved, enabled)
            DispatchQueue.main.async {
                guard request == self.computes else { self.staleComputes += 1; return }
                self.computing = false
                self.apply(done)
            }
        }
    }

    private func apply(_ c: Computed) {
        let keep = selected?.key
        horizon = c.window
        windowLabel.stringValue = "Period: " + horizon.label + (c.note.map { " — " + $0 } ?? "")
        if !horizon.isCustom && months.selectedSegment == 2 && c.note != nil { months.selectedSegment = preferences.months == 6 ? 1 : 0 }
        coverages = c.coverage
        for c in coverages { sourceLabels[c.kind]?.stringValue = c.summary }
        topics = c.topics
        topicTable.reloadData()
        if let k = keep, let i = topics.firstIndex(where: { $0.key == k }) { topicTable.selectRowIndexes([i], byExtendingSelection: false); selected = topics[i] } else { selected = nil; topicTable.deselectAll(nil) }
        showSelection()
        progress()
        onChange?()
        onApplied?()
    }

    private func showSelection() {
        copyButton.isEnabled = selected != nil
        if let t = selected {
            evidenceHeader.stringValue = "Evidence — \(t.display): \(plural(t.items.count, "record")) · \(t.typesLabel) · \(t.direct) direct / \(t.inferred) inferred (signals only, not completed outcomes)"
        } else {
            evidenceHeader.stringValue = topics.isEmpty ? "Evidence — no topics were found in this period with the sources that are on" : "Evidence — choose a topic on the left"
        }
        evidenceTable.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === topicTable ? topics.count : (selected?.items.count ?? 0) }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        var text = ""
        if tableView === topicTable, row < topics.count {
            let t = topics[row]
            switch id.rawValue {
            case "topic": text = t.display
            case "types": text = t.typesLabel
            case "count": text = String(t.items.count)
            case "signal": text = "\(t.direct) / \(t.inferred)"
            default: text = Dates.day(t.last)
            }
        } else if let t = selected, row < t.items.count {
            let item = t.items[row], e = item.evidence
            switch id.rawValue {
            case "date": text = e.dayOnly ? Dates.day(e.date) : Dates.minute(e.date)
            case "type": text = e.type.label
            case "source": text = e.source
            case "title": text = e.title + (item.count > 1 ? " (×\(item.count))" : "")
            case "signal": text = item.direct ? "Direct" : "Inferred"
            default: text = e.provenance + (e.derivedTitle ? " · auto title" : "") + (e.importedAt.map { " · " + Dates.minute($0) } ?? "")
            }
        }
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: ""); f.identifier = id; f.lineBreakMode = .byTruncatingTail; f.font = .systemFont(ofSize: 12); return f
        }()
        cell.stringValue = text
        cell.toolTip = text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === topicTable else { return }
        let row = topicTable.selectedRow
        selected = row >= 0 && row < topics.count ? topics[row] : nil
        showSelection()
    }
}

@main
struct HorizonMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--aside-lookup") { exit(AsideLookup.run()) }          // headless: answered before anything of AppKit exists
        if CommandLine.arguments.contains("--self-test") { exit(runSelfTest()) }
        if let i = CommandLine.arguments.firstIndex(of: "--check-sample"), i + 1 < CommandLine.arguments.count { exit(runSampleCheck(CommandLine.arguments[i + 1])) }
        if let i = CommandLine.arguments.firstIndex(of: "--smoke-window"), i + 1 < CommandLine.arguments.count { runWindowSmoke(savingTo: CommandLine.arguments[i + 1]) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
