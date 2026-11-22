// Contexta Horizon — the screenshot tool of the tests. NOT part of the app: build.sh does not compile this file, and
// the app contains no screen capture of any kind (static check C20). tests/glass-shot.sh builds a separate test
// program from the app's sources plus this file.
//
// What it does: puts a striped, fully opaque test backdrop on screen, puts each of the two Horizon windows (with
// made-up records from a temporary folder) directly above it, and photographs the area INSIDE the backdrop as macOS
// composites it — the Horizon window and what is below it. Below it there is only the opaque backdrop, and windows of
// other apps above it are left out, so the picture holds nothing of the desktop or of any other app; if another
// window is found between the two, no picture is taken. It then measures the picture: over the material the
// background must carry the colours of the stripes behind the window, while the preview and the tables, and the plain
// background shown for "Reduce transparency", must not. The app's reading of that setting is replaced; the setting
// itself, and every other system setting, is left alone. A program started from a shell cannot make itself the
// active app, so the material is told to look as it does in an active window (in the app it follows the window).

import AppKit

final class GlassStripes: NSView {
    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .white, .black]
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width / CGFloat(GlassStripes.colors.count)
        for (i, c) in GlassStripes.colors.enumerated() { c.setFill(); NSRect(x: CGFloat(i) * w, y: 0, width: w + 1, height: bounds.height).fill() }
    }
}

@main
struct GlassShot {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count > 1 else { print("usage: GlassShot <folder for the pictures>"); exit(2) }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = fm.temporaryDirectory.appendingPathComponent("horizon-glass-" + UUID().uuidString, isDirectory: true)
        let places = Places(home: temp)
        func put(_ url: URL, _ lines: [[String: Any]]) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = lines.map { String(decoding: (try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])) ?? Data(), as: UTF8.self) }.joined(separator: "\n") + "\n"
            try? Data(text.utf8).write(to: url)
        }
        let now = Date()
        func ago(_ d: Double) -> String { Dates.isoString(now.addingTimeInterval(-d * 86400)) }
        put(places.preindex, [["name": "Harborline Q3 quote.xlsx", "path": "/Users/mina/Work/Harborline/Harborline Q3 quote.xlsx", "source": "Google Drive", "modified": ago(12), "tags": ["source:google-drive", "topic:harborline", "folder:harborline"], "review": false],
                              ["name": "Atlas layout A.sketch", "path": "/Users/mina/Work/Atlas/Atlas layout A.sketch", "source": "Mac", "modified": ago(30), "tags": ["source:mac", "topic:atlas", "folder:atlas"], "review": false]])
        put(places.ai, [["id": "a1", "title": "Harborline quote review notes", "date": ago(10), "topics": ["Harborline"], "source": "Claude", "locator": "claude:a1"],
                        ["id": "a2", "title": "Atlas screen layout ideas", "date": ago(40), "topics": ["Atlas"], "source": "Claude", "locator": "claude:a2"]])
        put(places.mail, [["id": "m1", "title": "RE: Harborline quote reply", "date": ago(8), "topics": [], "source": "Mail", "locator": "message:m1"]])

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let dashboard = HorizonController(places: places, preferences: Preferences(store: MemoryStore()))
        let simple = SimpleController(dashboard: dashboard)
        dashboard.onChange = { simple.refresh() }
        dashboard.mailSide = MailMock().side                              // the Mail app is never involved
        let systemReduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let liveReduce = WindowBackdrop.reduceTransparency
        let announce = { NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil) }

        var failures: [String] = []
        func expect(_ name: String, _ ok: Bool, _ detail: String = "") { print((ok ? "ok    " : "FAIL  ") + name + (detail.isEmpty ? "" : "\n        " + detail)); if !ok { failures.append(name) } }
        let finish: () -> Never = {
            WindowBackdrop.reduceTransparency = liveReduce
            try? fm.removeItem(at: temp)
            expect("macOS's own \"Reduce transparency\" is what it was (\(systemReduce)); the tool only replaced the app's reading of it", NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency == systemReduce)
            print(failures.isEmpty ? "GLASS-SHOT PASS" : "GLASS-SHOT FAIL  " + failures.joined(separator: " | "))
            exit(failures.isEmpty ? 0 : 1)
        }
        guard let screen = NSScreen.screens.first else { print("GLASS-SHOT SKIPPED  no screen"); exit(3) }
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { print("GLASS-SHOT SKIPPED  this macOS has no way for a program to photograph its own windows as composited"); exit(3) }
        let capture = unsafeBitCast(symbol, to: Capture.self)

        let margin: CGFloat = 90
        let backdrop = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.contentView = GlassStripes(); backdrop.isOpaque = true; backdrop.backgroundColor = .black; backdrop.hasShadow = false; backdrop.isReleasedWhenClosed = false

        /// The window above the backdrop, photographed as composited; nil when anything else is between the two.
        func shoot(_ window: NSWindow, _ name: String) -> NSBitmapImageRep? {
            let order = NSWindow.windowNumbers(options: [.allApplications]) ?? []
            guard let top = order.firstIndex(of: NSNumber(value: window.windowNumber)), top + 1 < order.count, order[top + 1].intValue == backdrop.windowNumber,
                  backdrop.isOpaque, backdrop.frame.insetBy(dx: margin - 1, dy: margin - 1).contains(window.frame) else {
                expect("\(name): the Horizon window is directly above the opaque backdrop and inside it (otherwise no picture is taken)", false); return nil
            }
            let r = backdrop.frame.insetBy(dx: 4, dy: 4)
            let cg = CGRect(x: r.minX, y: screen.frame.maxY - r.maxY, width: r.width, height: r.height)
            // this window and what is on screen below it — within the backdrop that is the backdrop alone
            guard let image = capture(cg, (1 << 3) | (1 << 2), UInt32(window.windowNumber), 0)?.takeRetainedValue() else { expect("\(name): picture taken", false); return nil }
            let rep = NSBitmapImageRep(cgImage: image)
            _ = try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name + ".png"))
            return rep
        }
        /// The colours along a horizontal line (in screen points), as 0…255 red, green, blue.
        func line(_ rep: NSBitmapImageRep, y: CGFloat, from x0: CGFloat, to x1: CGFloat, count: Int = 9) -> [[Int]] {
            let r = backdrop.frame.insetBy(dx: 4, dy: 4), scale = CGFloat(rep.pixelsWide) / r.width
            return (0..<count).map { i in
                let x = x0 + (x1 - x0) * CGFloat(i) / CGFloat(count - 1)
                let c = rep.colorAt(x: Int((x - r.minX) * scale), y: Int((r.maxY - y) * scale))?.usingColorSpace(.sRGB)
                return [c?.redComponent, c?.greenComponent, c?.blueComponent].map { Int((($0 ?? -1) * 255).rounded()) }
            }
        }
        /// How far apart the colours along a line are: the largest difference in any one of red, green, blue.
        func spread(_ colors: [[Int]]) -> Int { (0..<3).map { ch in (colors.map { $0[ch] }.max() ?? 0) - (colors.map { $0[ch] }.min() ?? 0) }.max() ?? 0 }
        func text(_ colors: [[Int]]) -> String { colors.map { String(format: "%02X%02X%02X", $0[0], $0[1], $0[2]) }.joined(separator: " ") }
        func everything(_ v: NSView) -> [NSView] { v.subviews.flatMap { [$0] + everything($0) } }

        /// One window in three states: material (light), material (dark), plain. `surface` finds its solid inset surface.
        func run(_ window: NSWindow, _ file: String, surface: (NSView) -> NSView?, then next: @escaping () -> Void) {
            guard let b = window.contentView as? WindowBackdrop, let inset = surface(b) else { expect("\(file): the window has the shared background and its surface", false); next(); return }
            let visible = screen.visibleFrame
            let size = NSSize(width: min(window.frame.width, visible.width - 2 * margin - 20), height: min(window.frame.height, visible.height - 2 * margin - 20))
            let outer = NSRect(x: visible.minX + 10, y: visible.maxY - 10 - size.height - 2 * margin, width: size.width + 2 * margin, height: size.height + 2 * margin)
            backdrop.setFrame(outer, display: true)
            window.setFrame(outer.insetBy(dx: margin, dy: margin), display: true)
            backdrop.orderFrontRegardless()
            window.order(.above, relativeTo: backdrop.windowNumber)
            // the last one is not how the app is: the same window declared not opaque with a clear background, photographed only to record what that does
            let states: [(String, Bool, NSAppearance.Name, Bool)] = [("material-light", false, .aqua, false), ("material-dark", false, .darkAqua, false), ("plain-light", true, .aqua, false), ("plain-dark", true, .darkAqua, false), ("variant-clear-window-light", false, .aqua, true)]
            func step(_ i: Int) {
                guard i < states.count else { window.appearance = nil; b.effect.state = .followsWindowActiveState; WindowBackdrop.reduceTransparency = { false }; announce(); window.orderOut(nil); next(); return }
                let (name, plain, look, variant) = states[i]
                WindowBackdrop.reduceTransparency = { plain }; announce()
                if variant { window.isOpaque = false; window.backgroundColor = .clear; window.invalidateShadow() }
                window.appearance = NSAppearance(named: look)
                b.effect.state = .active
                window.order(.above, relativeTo: backdrop.windowNumber)
                window.displayIfNeeded()
                // The picture is taken 0.9 s after the change. macOS can take longer to redraw the material of a window that is
                // behind another app's (this tool cannot make itself the active app), so a material state is photographed again,
                // every 0.5 s for up to 5 s, until the material is in the picture; how long it took is printed. If it never is, the step fails.
                func take(_ waited: Double) {
                    guard let rep = shoot(window, "composite-\(file)-\(name)") else { step(i + 1); return }
                    let f = window.frame
                    let ground = line(rep, y: f.minY + 5, from: f.minX + 40, to: f.maxX - 40)
                    if !plain, spread(ground) < 12, waited < 5 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { take(waited + 0.5) }; return }
                    defer { step(i + 1) }
                    let s = window.convertToScreen(inset.convert(inset.bounds, to: nil))
                    let solid = line(rep, y: s.minY + 34, from: s.minX + 14, to: s.maxX - 34)
                    let stripes = line(rep, y: f.minY - margin / 2, from: f.minX + 40, to: f.maxX - 40)
                    let bar = line(rep, y: f.maxY - 3, from: f.minX + 60, to: f.maxX - 60)                    // the title area (now a toolbar), along its top edge above its items
                    let state = "opaque=\(window.isOpaque) clear=\(window.backgroundColor == NSColor.clear) alpha=\(window.alphaValue) material=\(b.showsThrough) · photographed \(waited) s after the change"
                    let numbers = "window \(state)\n        behind the window:  \(text(stripes))  spread \(spread(stripes))\n        background:         \(text(ground))  spread \(spread(ground))\n        inset surface:      \(text(solid))  spread \(spread(solid))\n        title bar:          \(text(bar))  spread \(spread(bar))"
                    let standard = window.isOpaque && window.backgroundColor == NSColor.windowBackgroundColor && window.alphaValue == 1
                    if variant {
                        print("note  \(file), \(name) (NOT how the app is — recorded for comparison): the same window declared not opaque with a clear background. Title bar spread \(spread(bar))" + (spread(bar) > 2 ? ": what is behind shows through the title bar, unblurred" : ": the title bar stays solid") + "\n        " + numbers)
                    } else if plain {
                        expect("\(file), \(name): with \"Reduce transparency\" the background is one plain colour — nothing behind the window shows — and the title bar and the inset surface are solid; the window is opaque in its standard colour", spread(stripes) > 150 && spread(ground) <= 2 && spread(solid) <= 2 && spread(bar) <= 2 && standard, numbers)
                    } else {
                        expect("\(file), \(name): in an opaque window in its standard colour, what is behind the window shows softly through the background (its colour varies with the stripes behind, far less than they do), while the title bar and the inset surface stay solid", spread(stripes) > 150 && spread(ground) >= 12 && spread(ground) < spread(stripes) / 2 && spread(solid) <= 2 && spread(bar) <= 2 && standard, numbers)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { take(0.9) }
            }
            step(0)
        }

        dashboard.onRead = {
            dashboard.onRead = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                simple.smokeType("Follow up on the Harborline quote")
                let typed = simple.smokeState()
                run(simple.smokeWindow, "simple", surface: { b in everything(b).first { ($0 as? NSBox)?.boxType == .custom } }) {
                    expect("the simple window still shows the typed task and its preview after all the changes of background", simple.smokeState().filter { !$0.hasPrefix("simple.fieldFocused=") } == typed.filter { !$0.hasPrefix("simple.fieldFocused=") } && typed.contains { $0.hasPrefix("simple.preview=Task: Follow up on the Harborline quote") })
                    dashboard.show()
                    run(dashboard.smokeWindow, "dashboard", surface: { b in everything(b).first { ($0 as? NSScrollView)?.documentView is NSTableView } }) { finish() }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("GLASS-SHOT FAIL  timed out"); try? fm.removeItem(at: temp); exit(1) }
        simple.show()
        app.run()
    }
}
