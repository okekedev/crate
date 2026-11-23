import SwiftUI
import AppKit

// Custom colours for the window. The person picks a colour for each part, or presses Randomize for a full palette that
// stays readable. Saved in UserDefaults under "palette" as hex strings. Same idea as the custom colours in Okeke Control.

// MARK: - Plain RGB maths (hex, contrast)

struct RGB: Equatable {
    var r: Double, g: Double, b: Double
    static let black = RGB(r: 0, g: 0, b: 0), white = RGB(r: 1, g: 1, b: 1)

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    init(h: Double, s: Double, v: Double) {
        let hue = (h - floor(h)) * 6, i = Int(hue) % 6, f = hue - floor(hue)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: self.init(r: v, g: t, b: p)
        case 1: self.init(r: q, g: v, b: p)
        case 2: self.init(r: p, g: v, b: t)
        case 3: self.init(r: p, g: q, b: v)
        case 4: self.init(r: t, g: p, b: v)
        default: self.init(r: v, g: p, b: q)
        }
    }
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255, b: Double(value & 0xFF) / 255)
    }
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(r: Double(min(max(c.redComponent, 0), 1)), g: Double(min(max(c.greenComponent, 0), 1)), b: Double(min(max(c.blueComponent, 0), 1)))
    }

    var hex: String { String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
    var color: Color { Color(red: r, green: g, blue: b) }

    /// WCAG relative luminance.
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
    /// WCAG contrast ratio, 1 to 21.
    func contrast(with other: RGB) -> Double { let a = luminance, b = other.luminance; return (max(a, b) + 0.05) / (min(a, b) + 0.05) }
    func mixed(with other: RGB, _ amount: Double) -> RGB { RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount) }
    /// This colour, pushed toward black or white until it reads on `background` at `ratio` or better.
    func readable(on background: RGB, ratio: Double = 4.5) -> RGB {
        if contrast(with: background) >= ratio { return self }
        let target: RGB = RGB.white.contrast(with: background) >= RGB.black.contrast(with: background) ? .white : .black
        var amount = 0.1
        while amount < 1.0 {
            let candidate = mixed(with: target, amount)
            if candidate.contrast(with: background) >= ratio { return candidate }
            amount += 0.1
        }
        return target
    }
    /// Black or white, whichever reads better on this colour.
    var ink: RGB { RGB.white.contrast(with: self) >= RGB.black.contrast(with: self) ? .white : .black }
}

/// Small deterministic generator (SplitMix64) so a seed always gives the same palette.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - The saved colours

/// Every colour of the window, as hex strings ("#RRGGBB").
struct Palette: Codable, Equatable {
    var window = "#1A1C1B"          // behind the panels
    var panel = "#242726"
    var text = "#E3E5DF"
    var smallText = "#A3AAA4"
    var trackLine = "#3E4340"
    var button = "#343837"
    var buttonText = "#E3E5DF"
    var outline = "#0B0C0C"
    var screen = "#17120A"          // the display, the sound list and the track lanes
    var screenText = "#FFB648"
    var screenDim = "#B07A2A"
    var accent = "#D8482F"          // play line, what is switched on, first pad
    var pad2 = "#E0862A"
    var pad3 = "#D9B62A"
    var pad4 = "#E9E6DA"

    static let standard = Palette()

    /// Tool names for each colour, for Claude.
    static let fields: [(String, WritableKeyPath<Palette, String>)] = [
        ("window", \.window), ("panel", \.panel), ("text", \.text), ("small_text", \.smallText), ("track_line", \.trackLine),
        ("button", \.button), ("button_text", \.buttonText), ("outline", \.outline),
        ("screen", \.screen), ("screen_text", \.screenText), ("screen_dim", \.screenDim),
        ("accent", \.accent), ("pad2", \.pad2), ("pad3", \.pad3), ("pad4", \.pad4),
    ]

    // One random base hue; everything else comes from it: a tinted dark or light case, stepped surfaces, a screen,
    // and an accent that is a neighbour of the base hue or its opposite. Then every text colour is checked against
    // what it sits on and pushed to at least 4.5:1.
    static func random(seed: UInt64) -> Palette {
        var g = SeededGenerator(seed: seed)
        func unit() -> Double { Double(g.next() >> 11) / Double(1 << 53) }
        func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }

        let hue = unit(), dark = unit() < 0.7, complementary = unit() < 0.4
        let accentHue = complementary ? hue + 0.5 : hue + (unit() < 0.5 ? -1 : 1) * between(0.07, 0.12)
        let secondHue = hue + (unit() < 0.5 ? -1 : 1) * between(0.03, 0.06)

        let window: RGB, panel: RGB, button: RGB, screen: RGB
        var text: RGB
        if dark {
            let s = between(0.25, 0.55), v = between(0.08, 0.13)
            window = RGB(h: hue, s: s, v: v)
            panel = RGB(h: hue, s: s * 0.9, v: v + between(0.04, 0.06))
            button = RGB(h: secondHue, s: s * 0.75, v: v + between(0.12, 0.17))
            screen = RGB(h: hue, s: min(0.8, s * 1.15), v: max(0.035, v - between(0.03, 0.05)))
            text = RGB(h: hue, s: between(0.04, 0.12), v: 0.95)
        } else {
            let s = between(0.06, 0.16)
            window = RGB(h: hue, s: s, v: between(0.89, 0.94))
            panel = RGB(h: hue, s: s * 0.7, v: between(0.96, 0.99))
            button = RGB(h: secondHue, s: s + between(0.03, 0.10), v: between(0.84, 0.89))
            screen = unit() < 0.5 ? RGB(h: hue, s: between(0.30, 0.55), v: between(0.10, 0.16))     // dark glass in a light case
                                  : RGB(h: hue, s: s + 0.05, v: between(0.86, 0.91))
            text = RGB(h: hue, s: between(0.45, 0.75), v: between(0.14, 0.24))
        }
        let accent = RGB(h: accentHue, s: between(0.62, 0.82), v: dark ? between(0.80, 0.95) : between(0.62, 0.82))
        let row = panel.mixed(with: button, 0.55)                                   // what a track row looks like
        text = text.readable(on: button).readable(on: panel).readable(on: row)
        let small = text.mixed(with: panel, 0.35).readable(on: row, ratio: 3.2).readable(on: panel, ratio: 3.2)

        let glassDark = screen.luminance < 0.2
        let glow = glassDark ? RGB(h: complementary ? accentHue : hue + 0.08, s: between(0.45, 0.70), v: 1.0) : RGB(h: hue, s: 0.70, v: 0.22)
        let screenText = glow.readable(on: screen, ratio: 6)
        var dim = screenText.mixed(with: screen, 0.45), tries = 0
        while dim.contrast(with: screen) < 2.6 && tries < 8 { dim = dim.mixed(with: screenText, 0.25); tries += 1 }

        let padV = dark ? between(0.82, 0.92) : between(0.70, 0.82)
        return Palette(
            window: window.hex, panel: panel.hex, text: text.hex, smallText: small.hex,
            trackLine: panel.mixed(with: text, 0.18).hex,
            button: button.hex, buttonText: text.readable(on: button).hex,
            outline: window.mixed(with: .black, dark ? 0.6 : 0.4).hex,
            screen: screen.hex, screenText: screenText.hex, screenDim: dim.hex,
            accent: accent.hex,
            pad2: RGB(h: accentHue + 0.07, s: between(0.60, 0.78), v: padV).hex,
            pad3: RGB(h: accentHue + 0.14, s: between(0.55, 0.75), v: padV).hex,
            pad4: (dark ? RGB(h: hue, s: 0.08, v: 0.90) : RGB(h: hue, s: 0.30, v: 0.42)).hex)
    }

    /// The lowest contrast between any text colour and what it sits on (for checks and for Claude).
    var lowestTextContrast: Double {
        func c(_ a: String, _ b: String) -> Double { guard let x = RGB(hex: a), let y = RGB(hex: b) else { return 0 }; return x.contrast(with: y) }
        return [c(text, panel), c(buttonText, button), c(screenText, screen), c(text, window)].min() ?? 0
    }
}

/// The palette turned into colours the views read. Built once each time the palette changes.
struct Look {
    let caseBG: Color, plate: Color, key: Color, keyInk: Color, edge: Color, ink: Color, soft: Color, line: Color
    let lcd: Color, lcdInk: Color, lcdDim: Color, accentInk: Color
    let hues: [Color], padInk: [Color]
    let dark: Bool

    init(_ p: Palette) {
        func rgb(_ hex: String) -> RGB { RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5) }
        caseBG = rgb(p.window).color; plate = rgb(p.panel).color; key = rgb(p.button).color; keyInk = rgb(p.buttonText).color
        edge = rgb(p.outline).color; ink = rgb(p.text).color; soft = rgb(p.smallText).color; line = rgb(p.trackLine).color
        lcd = rgb(p.screen).color; lcdInk = rgb(p.screenText).color; lcdDim = rgb(p.screenDim).color
        let pads = [rgb(p.accent), rgb(p.pad2), rgb(p.pad3), rgb(p.pad4)]
        hues = pads.map { $0.color }; padInk = pads.map { $0.ink.color }; accentInk = pads[0].ink.color
        dark = rgb(p.panel).luminance < 0.4
    }
}

// MARK: - The editor window

/// A small window of colour wells, one per part of the main window, with Randomize, Undo and Reset.
struct ColorsEditor: View {
    @EnvironmentObject var m: AppModel

    private struct Row: Identifiable { let id: String; let path: WritableKeyPath<Palette, String> }
    private struct Group: Identifiable { let id: String; let rows: [Row] }
    private let groups: [Group] = [
        Group(id: "Window", rows: [Row(id: "Background", path: \.window)]),
        Group(id: "Panels", rows: [Row(id: "Background", path: \.panel), Row(id: "Text", path: \.text), Row(id: "Small text", path: \.smallText), Row(id: "Track outline", path: \.trackLine)]),
        Group(id: "Buttons", rows: [Row(id: "Background", path: \.button), Row(id: "Text", path: \.buttonText), Row(id: "Outline", path: \.outline)]),
        Group(id: "Screens and lanes", rows: [Row(id: "Background", path: \.screen), Row(id: "Notes and text", path: \.screenText), Row(id: "Dim notes", path: \.screenDim)]),
        Group(id: "Accent and pads", rows: [Row(id: "Accent and first pad", path: \.accent), Row(id: "Second pad", path: \.pad2), Row(id: "Third pad", path: \.pad3), Row(id: "Fourth pad", path: \.pad4)]),
    ]
    private func binding(_ path: WritableKeyPath<Palette, String>) -> Binding<Color> {
        Binding(get: { RGB(hex: m.palette[keyPath: path])?.color ?? .gray },
                set: { let hex = RGB($0).hex; if hex != m.palette[keyPath: path] { m.palette[keyPath: path] = hex } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { m.randomizeColors() } label: { Label("Randomize", systemImage: "dice") }.keyboardShortcut("r")
                Button("Undo") { m.undoColors() }.disabled(m.paletteBefore == nil)
                Spacer()
                Button("Reset") { m.resetColors() }.disabled(m.palette == .standard)
            }
            Form {
                ForEach(groups) { group in
                    Section(group.id) {
                        ForEach(group.rows) { row in ColorPicker(row.id, selection: binding(row.path), supportsOpacity: false) }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(14)
        .frame(width: 320, height: 620)
    }
}
