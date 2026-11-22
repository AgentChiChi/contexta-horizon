// Contexta Horizon — the menu-bar app.
// The everyday screen is the simple one (Simple.swift): "What do you want to continue?" → a suggested topic → the exact short
// handoff shown inline → one Copy button, which is the only place the clipboard is written. A click on the menu-bar
// icon, or opening the app, shows that screen; a right-click shows a small menu with Quit.
// This file holds the app delegate and the dashboard ("Sources & Settings"): the period, the source switches, coverage, the
// evidence tables, "Read Sources" (which can include Mail, after a yes on its sheet), imports and the refresh tool —
// everything opt-in, reached from one link. Reading, computing topics and asking Mail all happen off the main thread:
// both windows open at once and show that they are still reading. Both windows share one background (WindowBackdrop, below):
// a standard macOS material behind the window, or a plain one when "Reduce transparency" is on.
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
    private let customFeedback = Style.label("", Style.caption, .secondaryLabelColor)
    private let customRow = NSStackView()
    private let readButton = NSButton(title: "Read Sources", target: nil, action: nil)
    private let importButton = NSButton(title: "Import…", target: nil, action: nil)
    private let toolButton = NSButton(title: "Refresh Feeds…", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let copyButton = NSButton(title: "Open in Simple View", target: nil, action: nil)
    private let backButton = NSButton(title: "Simple View", target: nil, action: nil)
    private var toolbar: WindowToolbar?
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private var coverages: [SourceCoverage] = []
    private let windowLabel = Style.label("", Style.caption, .secondaryLabelColor)
    private let statusLabel = Style.label("", Style.caption, .secondaryLabelColor)
    private let toolLabel = Style.label("", Style.caption, .secondaryLabelColor)
    private let evidenceHeader = Style.label("Evidence — choose a topic on the left", Style.body)
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

    private func build() {
        window.title = "Contexta Horizon — Sources & Settings"
        window.contentMinSize = NSSize(width: 960, height: 560)          // of the content, below the toolbar
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

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
        let startLabel = Style.label("Start", Style.body), endLabel = Style.label("End", Style.body)
        for v in [startLabel, startPicker, endLabel, endPicker, applyButton, customFeedback] as [NSView] { customRow.addArrangedSubview(v) }
        customRow.orientation = .horizontal; customRow.spacing = 8; customRow.alignment = .centerY
        customRow.isHidden = !preferences.usesCustom
        fillPickers()
        months.setAccessibilityLabel("Period")
        for (b, sel) in [(readButton, #selector(readSources(_:))), (importButton, #selector(importExport)), (toolButton, #selector(runTool)), (copyButton, #selector(useInSimple)), (backButton, #selector(goBack))] { b.target = self; b.action = sel; b.bezelStyle = .rounded }
        readButton.keyEquivalent = "\r"                                 // the primary action of this window
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false; spinner.isHidden = true
        spinner.setAccessibilityLabel("Reading sources")
        quitButton.target = NSApp; quitButton.action = #selector(NSApplication.terminate(_:)); quitButton.bezelStyle = .rounded
        backButton.toolTip = "Back to the “What do you want to continue?” screen"
        readButton.toolTip = "Reads again, now, the local sources that are switched on. If Imports, AI chats and Mail are all on and the Mail app is already running, it then asks whether to also collect recent subjects and dates from Mail (no bodies or addresses; Mail is never opened for you)"
        importButton.toolTip = "Imports an export file from this Mac: a ChatGPT or Claude conversations.json, an Apple Mail or Gmail Takeout .mbox, or a normalized .jsonl (saved as a new file; records already imported are skipped)"
        copyButton.toolTip = "Opens the selected topic in the simple view. Copying happens only there, with its Copy button."
        copyButton.isEnabled = false
        // The title area is a standard toolbar, as in a Finder window: the way back before the title, the period and the three actions after it.
        backButton.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: nil); backButton.imagePosition = .imageLeading
        backButton.setAccessibilityLabel("Back to Simple View"); months.toolTip = "The period that is shown"
        let bar = WindowToolbar(name: "HorizonSettings", entries: [.init("back", "Simple View", backButton, navigational: true), .init("period", "Period", months), .space,
                                                                    .init("read", "Read Sources", readButton), .init("import", "Import", importButton), .init("refresh", "Refresh Feeds", toolButton)])
        bar.install(in: window); toolbar = bar

        let sources = NSStackView(); sources.orientation = .vertical; sources.alignment = .leading; sources.spacing = 4
        for kind in SourceKind.allCases {
            let check = NSButton(checkboxWithTitle: kind.label, target: self, action: #selector(sourceToggled(_:)))
            check.state = preferences.isOn(kind) ? .on : .off
            check.tag = SourceKind.allCases.firstIndex(of: kind) ?? 0
            check.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let text = Style.label("Not read yet", Style.caption, .secondaryLabelColor)
            let row = NSStackView(views: [check, text]); row.orientation = .horizontal; row.alignment = .firstBaseline; row.spacing = 6
            sources.addArrangedSubview(row)
            sourceChecks[kind] = check; sourceLabels[kind] = text
        }

        configure(topicTable, columns: [("topic", "Topic", 110), ("types", "Types", 112), ("count", "Records", 56), ("signal", "Direct / Inferred", 96), ("last", "Latest", 80)])
        configure(evidenceTable, columns: [("date", "Record date", 124), ("type", "Type", 40), ("signal", "Signal", 58), ("title", "Title", 140), ("source", "Source", 84), ("imported", "Origin · imported", 104)])
        topicTable.setAccessibilityLabel("Topics"); evidenceTable.setAccessibilityLabel("Evidence")
        let left = scroll(topicTable), right = scroll(evidenceTable)
        let copyNote = Style.label("Copying happens only in the simple view. No always-on model · nothing is injected · title counts are signals, not proof of completed work.", Style.caption, .secondaryLabelColor)
        let copySpacer = NSView(); copySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let copyRow = NSStackView(views: [copyButton, copyNote, copySpacer, quitButton]); copyRow.orientation = .horizontal; copyRow.spacing = 8
        let rightStack = NSStackView(views: [evidenceHeader, right, copyRow]); rightStack.orientation = .vertical; rightStack.alignment = .leading; rightStack.spacing = 6
        right.widthAnchor.constraint(equalTo: rightStack.widthAnchor).isActive = true
        copyRow.widthAnchor.constraint(equalTo: rightStack.widthAnchor).isActive = true
        split.isVertical = true; split.dividerStyle = .thin
        split.addArrangedSubview(left); split.addArrangedSubview(rightStack)
        let leftWidth = left.widthAnchor.constraint(equalToConstant: topicsWidth); leftWidth.priority = NSLayoutConstraint.Priority(490); leftWidth.isActive = true   // gives way when the window is made narrower
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        // in a narrow window the two lists share the squeeze (each scrolls sideways) rather than the evidence taking all of it
        let rightWidth = rightStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 440); rightWidth.priority = NSLayoutConstraint.Priority(760); rightWidth.isActive = true

        let statusRow = NSStackView(views: [spinner, statusLabel]); statusRow.orientation = .horizontal; statusRow.spacing = 6; statusRow.alignment = .centerY
        let root = NSStackView(views: [customRow, windowLabel, sources, toolLabel, split, statusRow])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = Style.spacing
        root.edgeInsets = NSEdgeInsets(top: Style.margin, left: Style.margin, bottom: Style.margin, right: Style.margin)
        root.translatesAutoresizingMaskIntoConstraints = false
        let content = WindowBackdrop()                                  // the shared soft background; everything else is laid over it
        content.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                     root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                                     split.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -2 * Style.margin)])
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = content
        statusLabel.stringValue = "Local only — reads files on this Mac and uses no network."
        updateTool()
    }

    private func configure(_ table: NSTableView, columns: [(String, String, CGFloat)]) {
        for (id, title, width) in columns { table.addTableColumn(Style.column(id, title, width: width, flexible: id == "title")) }   // only the evidence title takes up spare room
        table.dataSource = self; table.delegate = self
        Style.list(table)
    }
    /// The width the topics list is given: its five columns as they are (each at least as wide as its title), with the
    /// list's own margins, its border and — where scroll bars are always shown — the scroll bar.
    private var topicsWidth: CGFloat {
        topicTable.tile()
        let first = topicTable.rect(ofColumn: 0), last = topicTable.rect(ofColumn: topicTable.numberOfColumns - 1)
        let bar = NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        return ceil(last.maxX + first.minX) + 2 + bar
    }
    private static let leading: Set<String> = ["topic", "title"]
    private func scroll(_ table: NSTableView) -> NSScrollView {
        let s = NSScrollView(); s.documentView = table; s.hasVerticalScroller = true; s.hasHorizontalScroller = true; s.borderType = .lineBorder; s.autohidesScrollers = true
        s.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return s
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !placedDivider { placedDivider = true; window.layoutIfNeeded(); split.setPosition(topicsWidth, ofDividerAt: 0) }   // room for all five topic columns
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
    func smokeDeselect() { topicTable.deselectAll(nil) }
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
        let turning = isWorking || (collecting && mailSheet == nil)
        spinner.isHidden = !turning                                     // out of the row while idle, so the status line starts at the margin
        if turning { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
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
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? Style.cell(id, primary: HorizonController.leading.contains(id.rawValue))
        cell.textField?.stringValue = text
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

/// The shared look of both windows: this Mac's own regular and small control metrics, the ones a Finder window in list
/// view is made of. Nothing here names a font or reads anyone's Finder settings: every size is asked of AppKit.
enum Style {
    /// Regular text — list cells, the preview, the task field, buttons: the system's regular size (13 on current macOS).
    static var body: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
    /// Secondary captions: the system's small size (11).
    static var caption: NSFont { .systemFont(ofSize: NSFont.smallSystemFontSize) }
    /// The one compact headline of a window: the system's third title size (15), semibold.
    static var headline: NSFont { .systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold) }
    /// The standard margin between a window's edge and its content, and the space between rows of content.
    static let margin: CGFloat = 20
    static let spacing: CGFloat = 8
    /// A list row as AppKit makes it by default on current macOS, and as Finder's list view has it: 24 points, cells 17 apart.
    static let rowHeight: CGFloat = 24
    static let cellSpacing = NSSize(width: 17, height: 0)

    static func label(_ text: String, _ font: NSFont, _ color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = font; l.textColor = color; l.isSelectable = false
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    /// A list in the density of Finder's list view: 24-point rows, striped, rounded selection, no grid, the standard header.
    static func list(_ table: NSTableView) {
        table.style = .inset
        table.rowSizeStyle = .custom
        table.rowHeight = rowHeight
        table.intercellSpacing = cellSpacing
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = []
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    }

    /// A column that is never narrower than its own title; only a `flexible` one takes up spare room, and it never
    /// gives up the width it was made with (a list that does not fit scrolls sideways instead).
    static func column(_ id: String, _ title: String, width: CGFloat, flexible: Bool = false) -> NSTableColumn {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        c.title = title
        c.minWidth = max(flexible ? width : 36, ceil(c.headerCell.cellSize.width))
        c.width = max(width, c.minWidth)
        c.resizingMask = flexible ? [.autoresizingMask, .userResizingMask] : .userResizingMask
        return c
    }

    /// A list cell: one line of regular text, centred in its row; the leading column in the label colour, the others secondary.
    static func cell(_ id: NSUserInterfaceItemIdentifier, primary: Bool) -> NSTableCellView {
        let cell = NSTableCellView(), text = NSTextField(labelWithString: "")
        text.font = body; text.textColor = primary ? .labelColor : .secondaryLabelColor; text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.identifier = id; cell.addSubview(text); cell.textField = text
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
}

/// The title area of both windows is a standard toolbar, as in a Finder window: the title, the window's own few
/// controls as ordinary toolbar items, nothing customisable and nothing that imitates Finder's navigation. The window
/// keeps its standard titled style; the content (and the material behind it) still starts below the toolbar.
final class WindowToolbar: NSObject, NSToolbarDelegate {
    struct Entry {
        let id: NSToolbarItem.Identifier, label: String, view: NSView?, navigational: Bool
        init(_ id: String, _ label: String, _ view: NSView, navigational: Bool = false) { self.id = NSToolbarItem.Identifier(id); self.label = label; self.view = view; self.navigational = navigational }
        private init() { id = .flexibleSpace; label = ""; view = nil; navigational = false }
        static let space = Entry()
    }
    private let entries: [Entry]
    let toolbar: NSToolbar

    init(name: String, entries: [Entry]) {
        self.entries = entries
        toolbar = NSToolbar(identifier: name)
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
    }

    /// The window keeps the content size it was made with: the toolbar is added above the content, not taken out of it.
    func install(in window: NSWindow) {
        let content = window.contentRect(forFrameRect: window.frame).size
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.setContentSize(content)
        window.center()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { entries.map { $0.id } }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { entries.map { $0.id } }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let entry = entries.first(where: { $0.id == id }), let view = entry.view else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = entry.label; item.paletteLabel = entry.label; item.toolTip = view.toolTip
        item.view = view
        item.isNavigational = entry.navigational                        // before the title, where a Finder window has Back
        item.visibilityPriority = .high
        return item
    }
}

/// The background both windows share: a standard macOS material (a real NSVisualEffectView, blended behind the window),
/// through which whatever is behind the window shows softly, blurred and tinted by macOS. Only this background is a
/// material. The window keeps its standard title bar and buttons and is always at full strength (alpha 1), and
/// everything on it (text, buttons, the preview, the tables) is laid OVER the material, not inside it, so it is drawn
/// at full strength and the preview and the tables keep their own solid surfaces. The material covers the whole
/// content area, so no part of the window is simply clear. The material follows light and dark, and goes plain while
/// the window is not the active one, as macOS materials do.
/// The window itself is kept an ordinary opaque window in its standard colour, in both states. That is measured, not
/// assumed (tests/glass-shot.swift, over a striped test backdrop): in an opaque window the material does show what is
/// behind the window, and the title bar stays solid; declared not opaque with a clear background, the same window's
/// title bar turns clear and shows what is behind it unblurred.
/// When "Reduce transparency" is on (System Settings › Accessibility › Display) the material is taken away and a
/// plain plate in the window's own colour is shown instead; a change of that setting while the app runs is followed
/// at once. The setting is only ever read. Nothing of the screen is looked at or captured: macOS draws the material.
final class WindowBackdrop: NSView {
    static let material = NSVisualEffectView.Material.sidebar
    /// Whether macOS asks for less transparency. Only read; the tests put their own answer here instead of touching the setting.
    static var reduceTransparency: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    let effect = NSVisualEffectView()
    let plate = SolidPlate()
    private var watch: NSObjectProtocol?

    /// The plain background: the window's own colour, which is a different one in light and in dark.
    final class SolidPlate: NSView {
        override var isOpaque: Bool { true }
        override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
    }

    init() {
        super.init(frame: .zero)
        effect.material = WindowBackdrop.material
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        for under in [plate, effect] as [NSView] {                       // both fill the window, under whatever is added later
            under.translatesAutoresizingMaskIntoConstraints = false
            addSubview(under)
            NSLayoutConstraint.activate([under.leadingAnchor.constraint(equalTo: leadingAnchor), under.trailingAnchor.constraint(equalTo: trailingAnchor), under.topAnchor.constraint(equalTo: topAnchor), under.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
        watch = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            if Thread.isMainThread { self?.apply() } else { DispatchQueue.main.async { self?.apply() } }
        }
        apply()
    }
    required init?(coder: NSCoder) { return nil }
    deinit { if let watch = watch { NSWorkspace.shared.notificationCenter.removeObserver(watch) } }

    /// True while the material is in use; false while the plain plate is.
    var showsThrough: Bool { !effect.isHidden }

    /// One of the two is shown, never both: the material, or (with "Reduce transparency" on) the plain plate. The
    /// window stays what it is in both: at full strength, opaque, in its standard colour (see above for why).
    func apply() {
        let plain = WindowBackdrop.reduceTransparency()
        effect.isHidden = plain
        plate.isHidden = !plain
        guard let window = window else { return }
        window.alphaValue = 1
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
    }

    /// Put into a window (or taken out of one): the window is set up for what is shown now.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
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
