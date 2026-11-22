// Contexta Horizon — the mark: "-C-".
// A line arrives from the left and touches the C at the middle of its back; the C is open on the right; a separate
// line leaves on the right. The whole mark is one canonical SVG path, stroked 9 wide with round caps and no fill, in a
// 112 by 80 box. Everything is made from that one string: the 18-point template image in the menu bar (drawn here)
// and the Finder icon, the SVG files and the PNGs (Icon/make-icon.swift).

import AppKit

enum ThreadGlyph {
    /// The canonical mark. Do not redraw it: change nothing here without changing the approved design.
    static let viewBox = CGSize(width: 112, height: 80)
    static let path = "M6 40H32 M69 20A23 23 0 1 0 69 60 M80 40H106"
    static let strokeWidth: CGFloat = 9

    /// The path as an SVG element (stroked, round caps, no fill) in the given colour.
    static func svgPath(stroke: String) -> String {
        "<path d=\"\(path)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(Int(strokeWidth))\" stroke-linecap=\"round\"/>"
    }

    /// The canonical string as a CGPath, in the box's own coordinates (x to the right, y DOWN, as SVG has it).
    /// Reads the three absolute commands the mark uses: M x y, H x, and A rx ry rotation large-arc sweep x y (a
    /// circular arc, rx = ry, no rotation). Anything else is left out, and `elements` would then not be 3 + 3.
    static func outline() -> (path: CGPath, elements: Int) {
        let out = CGMutablePath()
        var tokens: [String] = [], word = ""
        for ch in path {
            if ch.isLetter { if !word.isEmpty { tokens.append(word); word = "" }; tokens.append(String(ch)) }
            else if ch == " " || ch == "," { if !word.isEmpty { tokens.append(word); word = "" } }
            else { word.append(ch) }
        }
        if !word.isEmpty { tokens.append(word) }
        var i = 0, at = CGPoint.zero, elements = 0
        func number() -> CGFloat? { guard i < tokens.count, let v = Double(tokens[i]) else { return nil }; i += 1; return CGFloat(v) }
        while i < tokens.count {
            let command = tokens[i]; i += 1
            switch command {
            case "M":
                guard let x = number(), let y = number() else { return (out, -1) }
                at = CGPoint(x: x, y: y); out.move(to: at); elements += 1
            case "H":
                guard let x = number() else { return (out, -1) }
                at = CGPoint(x: x, y: at.y); out.addLine(to: at); elements += 1
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(), let large = number(), let sweep = number(), let x = number(), let y = number(), rx == ry, rotation == 0, rx > 0 else { return (out, -1) }
                // endpoint → centre (SVG implementation notes, F.6.5), for a circle
                let end = CGPoint(x: x, y: y), hx = (at.x - end.x) / 2, hy = (at.y - end.y) / 2
                let d2 = hx * hx + hy * hy
                guard d2 > 0, d2 <= rx * rx else { return (out, -1) }
                let k = (large != sweep ? 1 : -1) * ((rx * rx - d2) / d2).squareRoot()
                let centre = CGPoint(x: k * hy + (at.x + end.x) / 2, y: -k * hx + (at.y + end.y) / 2)
                let a0 = atan2(at.y - centre.y, at.x - centre.x), a1 = atan2(end.y - centre.y, end.x - centre.x)
                // sweep 1 runs towards larger angles (in these y-down coordinates), sweep 0 towards smaller ones
                out.addArc(center: centre, radius: rx, startAngle: a0, endAngle: a1, clockwise: sweep == 0)
                at = end; elements += 1
            default: return (out, -1)
            }
        }
        return (out, elements)
    }

    /// Where the 112 by 80 box lands in `rect`: as large as fits, proportions kept, centred (SVG's "xMidYMid meet").
    /// `rect` is in ordinary drawing coordinates (y up); the box's y runs down, so it is flipped here.
    static func placement(in rect: CGRect) -> (scale: CGFloat, transform: CGAffineTransform) {
        let s = min(rect.width / viewBox.width, rect.height / viewBox.height)
        return (s, CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: rect.midX - viewBox.width / 2 * s, ty: rect.midY + viewBox.height / 2 * s))
    }

    /// Strokes the mark into `rect` in one colour: 9 units wide, round caps, nothing filled.
    static func draw(in context: CGContext, rect: CGRect, color: CGColor) {
        let place = placement(in: rect)
        var transform = place.transform
        guard let placed = outline().path.copy(using: &transform) else { return }
        context.saveGState()
        context.setStrokeColor(color); context.setLineWidth(strokeWidth * place.scale); context.setLineCap(.round); context.setLineJoin(.round)
        context.addPath(placed); context.strokePath()
        context.restoreGState()
    }

    /// The menu-bar glyph: the same path, scaled in proportion and centred in 18 by 18 points, as a template image
    /// (the menu bar tints it light or dark).
    static func menuImage(points: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Contexta Horizon"
        return image
    }
}
