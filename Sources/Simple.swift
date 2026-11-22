// Contexta Horizon — the everyday screen.
//   "What do you want to continue?"  →  type a task, or press a suggested topic  →  the exact short handoff, shown inline  →  Copy
// It uses what the dashboard already computed (the same period and source switches), finds topics with a local,
// deterministic match (Search.rank — no model), and shows the text that would be copied before anything is copied.
// The Copy button's action below is the only place in the app that writes the clipboard. Return in the field only
// settles on the suggested topic; it never copies. Everything else (period, sources, imports, refresh) is behind the
// one "Sources & Settings" link.

import AppKit

final class SimpleController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private let dashboard: HorizonController
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    private let field = NSTextField()
    private let hint = SimpleController.label("", size: 12, color: .secondaryLabelColor)
    private let suggestionRow = NSStackView()
    private let preview = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 240))
    private let emptyNote = SimpleController.label("", size: 13, color: .tertiaryLabelColor)
    private let caption = SimpleController.label("", size: 11, color: .secondaryLabelColor)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let status = SimpleController.label("", size: 12, color: .secondaryLabelColor)
    private let advanced = NSButton(title: "Sources & Settings", target: nil, action: nil)

    private var candidates: [TopicSummary] = []
    private var pickedKey: String?
    /// Exactly what the preview shows and what Copy would copy; empty when there is nothing to copy.
    private var shownText = ""
    private(set) var copyCount = 0

    init(dashboard: HorizonController) {
        self.dashboard = dashboard
        super.init()
        build()
    }

    private static func label(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color; l.isSelectable = false
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func build() {
        window.title = "Contexta Horizon"
        window.minSize = NSSize(width: 520, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let title = SimpleController.label("What do you want to continue?", size: 22, color: .labelColor, weight: .semibold)
        field.placeholderString = "For example: follow up on the Harborline quote"
        field.font = .systemFont(ofSize: 15)
        field.delegate = self
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.setAccessibilityLabel("Task to continue")
        field.heightAnchor.constraint(equalToConstant: 30).isActive = true

        suggestionRow.orientation = .horizontal; suggestionRow.spacing = 8; suggestionRow.alignment = .centerY
        suggestionRow.setAccessibilityLabel("Suggested topics")

        preview.isEditable = false; preview.isSelectable = true; preview.isRichText = false
        preview.font = .systemFont(ofSize: 12.5)
        preview.textContainerInset = NSSize(width: 10, height: 10)
        preview.autoresizingMask = [.width]
        preview.drawsBackground = false
        preview.setAccessibilityLabel("Text that will be copied")
        let scroller = NSScrollView(); scroller.documentView = preview; scroller.hasVerticalScroller = true; scroller.drawsBackground = false
        let box = NSBox(); box.boxType = .custom; box.cornerRadius = 8; box.borderWidth = 1; box.borderColor = .separatorColor; box.fillColor = .textBackgroundColor
        box.contentViewMargins = .zero; box.titlePosition = .noTitle
        scroller.translatesAutoresizingMaskIntoConstraints = false; emptyNote.translatesAutoresizingMaskIntoConstraints = false
        let inner = NSView(); inner.addSubview(scroller); inner.addSubview(emptyNote)
        emptyNote.alignment = .center
        NSLayoutConstraint.activate([scroller.leadingAnchor.constraint(equalTo: inner.leadingAnchor), scroller.trailingAnchor.constraint(equalTo: inner.trailingAnchor), scroller.topAnchor.constraint(equalTo: inner.topAnchor), scroller.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
                                     emptyNote.centerYAnchor.constraint(equalTo: inner.centerYAnchor), emptyNote.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 28), emptyNote.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -28)])
        box.contentView = inner
        box.heightAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true

        copyButton.target = self; copyButton.action = #selector(copyShown); copyButton.bezelStyle = .rounded; copyButton.controlSize = .large
        copyButton.bezelColor = .controlAccentColor
        copyButton.toolTip = "Copies exactly the text shown above to the clipboard. Nothing is copied until you press this."
        copyButton.isEnabled = false
        advanced.target = self; advanced.action = #selector(openAdvanced); advanced.isBordered = false
        advanced.attributedTitle = NSAttributedString(string: "Sources & Settings", attributes: [.foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: 12)])
        advanced.toolTip = "Period, source switches, imports and refresh. You rarely need this."
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bottom = NSStackView(views: [copyButton, status, spacer, advanced]); bottom.orientation = .horizontal; bottom.spacing = 10; bottom.alignment = .centerY

        let stack = NSStackView(views: [title, field, hint, suggestionRow, box, caption, bottom])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.setCustomSpacing(14, after: title); stack.setCustomSpacing(6, after: field); stack.setCustomSpacing(12, after: suggestionRow); stack.setCustomSpacing(6, after: box); stack.setCustomSpacing(14, after: caption)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 26, bottom: 20, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(); content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor), stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        for v in [field, box, bottom, hint, caption] as [NSView] { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52).isActive = true }
        box.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = content
        refresh()
    }

    /// Shows the screen with the keyboard in the field. `pick` chooses a topic (from the dashboard's "Open in simple view").
    func show(pick: String? = nil) {
        if let key = pick { pickedKey = key; field.stringValue = "" }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(field)
        dashboard.ensureLoaded()
        refresh()
    }

    // MARK: what is shown

    /// Works out the suggestions and the one topic whose handoff is shown, from what is typed and what was picked.
    /// With nothing typed and nothing picked, or with no match, there is no preview and Copy is off.
    func refresh() {
        let topics = dashboard.currentTopics
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var chosen: TopicSummary?
        candidates = []
        if !dashboard.isLoaded {
            hint.stringValue = "Reading your sources…"
            emptyNote.stringValue = ""
        } else if topics.isEmpty {
            hint.stringValue = "No topics were found in this period with the sources that are on."
            emptyNote.stringValue = "There are no topics to show yet.\nOpen Sources & Settings to check the period and sources, or to import data."
        } else if query.isEmpty {
            candidates = Array(topics.prefix(3))
            chosen = candidates.first { $0.key == pickedKey } ?? topics.first { $0.key == pickedKey }
            if let c = chosen, !candidates.contains(where: { $0.key == c.key }) { candidates = [c] + candidates.prefix(2) }
            hint.stringValue = chosen == nil ? "Suggested topics — press one, or type what you want to continue" : "Suggested topics"
            emptyNote.stringValue = "Choose a topic or type a task.\nThe exact text that will be copied appears here."
        } else {
            candidates = Search.rank(query, topics: topics).map { $0.topic }
            if candidates.isEmpty {
                hint.stringValue = "No matching topic was found."
                emptyNote.stringValue = "No topic matches “" + Redact.label(query, max: 40) + "”.\nTry other words, or check the period and sources in Sources & Settings."
            } else {
                chosen = candidates.first { $0.key == pickedKey } ?? candidates[0]
                hint.stringValue = candidates.count == 1 ? "Matching topic" : "\(candidates.count) matching topics — press another to switch"
            }
        }
        suggestionRow.arrangedSubviews.forEach { suggestionRow.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, t) in candidates.enumerated() {
            let b = NSButton(title: t.display + " · \(t.items.count)", target: self, action: #selector(pick(_:)))
            b.bezelStyle = .rounded; b.tag = i
            let isChosen = t.key == chosen?.key
            b.bezelColor = isChosen ? .controlAccentColor : nil
            if isChosen { b.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected"); b.imagePosition = .imageLeading }   // visible even when the window is not in front
            b.setAccessibilityLabel(t.display + ", " + plural(t.items.count, "record") + (isChosen ? ", selected" : ""))
            b.toolTip = plural(t.items.count, "record") + " · " + t.typesLabel + " · \(t.direct) direct / \(t.inferred) inferred"
            suggestionRow.addArrangedSubview(b)
        }
        suggestionRow.isHidden = candidates.isEmpty
        shownText = chosen.map { Export.simple(task: query, topic: $0, window: dashboard.currentWindow, coverage: dashboard.currentCoverage) } ?? ""
        preview.string = shownText
        emptyNote.isHidden = !shownText.isEmpty
        copyButton.isEnabled = !shownText.isEmpty
        status.stringValue = ""
        let note = Export.caption(dashboard.currentCoverage)
        caption.stringValue = !dashboard.isLoaded ? "" : "Period: " + dashboard.currentWindow.dayLabel + (note.map { " · Source caution: " + $0 } ?? "") + " · Titles and dates only"
    }

    // MARK: actions

    func controlTextDidChange(_ obj: Notification) { refresh() }

    /// Return in the field settles on the topic that is shown. It never copies.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        refresh()
        if !shownText.isEmpty { status.stringValue = "Topic chosen. Press Copy to copy it." }
        return true
    }

    @objc private func pick(_ sender: NSButton) {
        guard sender.tag < candidates.count else { return }
        pickedKey = candidates[sender.tag].key
        refresh()
    }

    @objc private func openAdvanced() { dashboard.show() }

    /// The only place the clipboard is written: this button, with exactly the text the preview is showing.
    @objc private func copyShown() {
        guard copyButton.isEnabled, !shownText.isEmpty, preview.string == shownText else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(shownText, forType: .string)
        copyCount += 1
        status.stringValue = "Copied — exactly the text shown above"
    }

    // MARK: for the synthetic window smoke test (each does what the control does)

    var smokeWindow: NSWindow { window }
    func smokeType(_ text: String) { field.stringValue = text; refresh() }
    func smokeReturn() -> Bool { control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))) }
    func smokePick(_ index: Int) { if let b = suggestionRow.arrangedSubviews[safe: index] as? NSButton { pick(b) } }
    /// Presses Copy only when it is disabled, to show that nothing happens (an enabled press would write the real clipboard).
    func smokePressCopyWhileDisabled() { if !copyButton.isEnabled { copyShown() } }
    func smokeOpenAdvanced() { openAdvanced() }
    func smokeState() -> [String] {
        ["simple.title=" + window.title, "simple.fieldFocused=\(window.firstResponder === field.currentEditor() || window.firstResponder === field)", "simple.query=" + field.stringValue, "simple.hint=" + hint.stringValue,
         "simple.suggestions=" + suggestionRow.arrangedSubviews.compactMap { ($0 as? NSButton).map { $0.title + ($0.bezelColor != nil ? "*" : "") } }.joined(separator: " | "),
         "simple.copyEnabled=\(copyButton.isEnabled)", "simple.copyCount=\(copyCount)", "simple.status=" + status.stringValue, "simple.caption=" + caption.stringValue,
         "simple.empty=" + (emptyNote.isHidden ? "" : emptyNote.stringValue.replacingOccurrences(of: "\n", with: " ")), "simple.preview=" + preview.string]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
