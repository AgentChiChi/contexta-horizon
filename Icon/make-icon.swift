// Draws the Contexta Horizon icon from the one canonical path in Sources/Glyph.swift ("-C-"). Deterministic: no
// clock, no randomness, no input but that path. Writes, into the folder given as its argument:
//   mark.svg                          the canonical mark: viewBox 0 0 112 80, the path, stroke 9, round caps, no fill
//   icon.svg                          the Finder icon: the approved 112 by 112 tile (corner radius 25, the mark as an
//                                     87 by 72 SVG centred in it) placed inside the macOS icon margins
//   menu-glyph.svg, menu-glyph.png, menu-glyph@2x.png     the 18-point menu-bar template (one colour on transparent)
//   AppIcon.iconset/…                 the ten PNGs macOS expects (16 … 512 points, 1x and 2x); iconutil makes AppIcon.icns of them
//   icon-preview.png                  the Finder icon at six sizes and the menu-bar glyph on a light and a dark bar
// Built and run by Icon/make-icon.sh. Nothing is read from this Mac and nothing is sent.

import AppKit

@main struct MakeIcon {
    static let indexYellow = "#F4D447"                                   // the plate: Index Yellow, flat and solid
    static let markInk = "#20231F"                                       // the mark: ink, flat and solid, at full strength
    static let tile: CGFloat = 112, corner: CGFloat = 25                 // the approved tile …
    static let markBox = CGRect(x: 12.5, y: 20, width: 87, height: 72)   // … and the mark's 87 by 72 box, centred in it
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    static func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        return CGColor(colorSpace: space, components: [CGFloat((v >> 16) & 255) / 255, CGFloat((v >> 8) & 255) / 255, CGFloat(v & 255) / 255, alpha])!
    }

    static func bitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .high
        draw(c)
        return c.makeImage()!
    }

    /// The Finder icon at `px` pixels: the tile, as large as the macOS icon margins allow (824 of 1024), in flat Index
    /// Yellow with the mark in flat ink.
    static func appIcon(_ px: Int) -> CGImage {
        bitmap(px, px) { c in
            let s = CGFloat(px) / 1024, plate = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), u = plate.width / tile
            c.setFillColor(color(indexYellow))
            c.addPath(CGPath(roundedRect: plate, cornerWidth: corner * u, cornerHeight: corner * u, transform: nil)); c.fillPath()
            // the mark's box in the tile (the tile's y runs down, the bitmap's up; the box is centred, so it is the same)
            let box = CGRect(x: plate.minX + markBox.minX * u, y: plate.minY + (tile - markBox.maxY) * u, width: markBox.width * u, height: markBox.height * u)
            ThreadGlyph.draw(in: c, rect: box, color: color(markInk))
        }
    }

    /// The menu-bar template at `px` pixels square: the mark alone, in black on nothing.
    static func menuGlyph(_ px: Int) -> CGImage { bitmap(px, px) { c in ThreadGlyph.draw(in: c, rect: CGRect(x: 0, y: 0, width: px, height: px), color: color("#000000")) } }

    static func write(_ image: CGImage, _ url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
    }
    static func write(_ text: String, _ url: URL) { try! Data(text.utf8).write(to: url) }

    static func main() {
        precondition(ThreadGlyph.outline().elements == 6, "the canonical path was not read in full")       // three moves, two lines, one arc
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Icon", isDirectory: true)
        let set = out.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.removeItem(at: set)
        try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            write(appIcon(points), set.appendingPathComponent("icon_\(points)x\(points).png"))
            write(appIcon(points * 2), set.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
        write(menuGlyph(18), out.appendingPathComponent("menu-glyph.png"))
        write(menuGlyph(36), out.appendingPathComponent("menu-glyph@2x.png"))

        let box = "0 0 \(Int(ThreadGlyph.viewBox.width)) \(Int(ThreadGlyph.viewBox.height))"
        write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- Contexta Horizon: the canonical mark. Written by Icon/make-icon.swift from Sources/Glyph.swift. -->
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(box)" width="112" height="80">
          \(ThreadGlyph.svgPath(stroke: markInk))
        </svg>

        """, out.appendingPathComponent("mark.svg"))
        write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- Contexta Horizon, Finder icon: the 112 by 112 tile (corner radius 25, the mark as an 87 by 72 SVG centred in it) inside the macOS icon margins. Written by Icon/make-icon.swift from Sources/Glyph.swift. -->
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
          <g transform="translate(100 100) scale(\(String(format: "%.9f", 824.0 / 112.0)))">
            <rect width="112" height="112" rx="25" fill="\(indexYellow)"/>
            <svg x="12.5" y="20" width="87" height="72" viewBox="\(box)" preserveAspectRatio="xMidYMid meet">
              \(ThreadGlyph.svgPath(stroke: markInk))
            </svg>
          </g>
        </svg>

        """, out.appendingPathComponent("icon.svg"))
        write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- Contexta Horizon menu-bar glyph (template: one colour), 18 by 18 points: the same path, scaled in proportion and centred. Written by Icon/make-icon.swift from Sources/Glyph.swift. -->
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="18" height="18">
          <svg x="0" y="0" width="18" height="18" viewBox="\(box)" preserveAspectRatio="xMidYMid meet">
            \(ThreadGlyph.svgPath(stroke: "#000000"))
          </svg>
        </svg>

        """, out.appendingPathComponent("menu-glyph.svg"))

        // the preview: the Finder icon at six sizes; the menu glyph at 18 points (2x and 1x) on a light and a dark menu bar, and enlarged
        let preview = bitmap(1500, 640) { c in
            c.setFillColor(color("#ffffff")); c.fill(CGRect(x: 0, y: 0, width: 1500, height: 640))
            var x: CGFloat = 40
            for px in [512, 256, 128, 64, 32, 16] {
                let shown = CGFloat(px == 512 ? 400 : px)
                c.draw(appIcon(px == 512 ? 800 : px), in: CGRect(x: x, y: 600 - shown, width: shown, height: shown))
                x += shown + 26
            }
            func bar(_ origin: CGPoint, dark: Bool) {
                c.setFillColor(color(dark ? "#29292b" : "#ededf0")); c.fill(CGRect(x: origin.x, y: origin.y, width: 560, height: 48))
                let tint = dark ? color("#ffffff", 0.92) : color("#000000", 0.85)
                ThreadGlyph.draw(in: c, rect: CGRect(x: origin.x + 24, y: origin.y + 6, width: 36, height: 36), color: tint)       // 18 points at 2x
                ThreadGlyph.draw(in: c, rect: CGRect(x: origin.x + 96, y: origin.y + 15, width: 18, height: 18), color: tint)      // 18 points at 1x
                c.setFillColor(dark ? color("#ffffff", 0.25) : color("#000000", 0.2))
                for i in 0..<5 { c.fill(CGRect(x: origin.x + 180 + CGFloat(i) * 70, y: origin.y + 19, width: 44, height: 10)) }    // other menu-bar items, as blocks
            }
            bar(CGPoint(x: 40, y: 110), dark: false)
            bar(CGPoint(x: 40, y: 40), dark: true)
            ThreadGlyph.draw(in: c, rect: CGRect(x: 660, y: 20, width: 160, height: 160), color: color("#000000", 0.85))           // the glyph enlarged
            c.setFillColor(color("#29292b")); c.fill(CGRect(x: 860, y: 20, width: 160, height: 160))
            ThreadGlyph.draw(in: c, rect: CGRect(x: 860, y: 20, width: 160, height: 160), color: color("#ffffff", 0.92))
        }
        write(preview, out.appendingPathComponent("icon-preview.png"))
        print("Icon written to \(out.path): mark.svg, icon.svg, menu-glyph.svg, menu-glyph.png, menu-glyph@2x.png, AppIcon.iconset (10 PNGs), icon-preview.png")
    }
}
