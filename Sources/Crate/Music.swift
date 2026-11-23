import Foundation

// Notes, keys and the song itself. A step is a sixteenth note; a bar has 16 steps.

let KEYS = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
let SCALE_NAMES = ["major", "minor", "dorian", "phrygian", "harmonic minor", "minor pentatonic", "major pentatonic", "blues"]
let SCALES: [String: [Int]] = [
    "major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10], "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "harmonic minor": [0, 2, 3, 5, 7, 8, 11], "minor pentatonic": [0, 3, 5, 7, 10], "major pentatonic": [0, 2, 4, 7, 9], "blues": [0, 3, 5, 6, 7, 10],
]
let DELAY_TIMES = ["1/16", "1/8t", "1/8", "1/8d", "1/4", "1/4d"]
let DELAY_STEPS: [String: Double] = ["1/16": 1, "1/8t": 4.0 / 3.0, "1/8": 2, "1/8d": 3, "1/4": 4, "1/4d": 6]
let SPACES = ["Small Room", "Medium Room", "Large Room", "Medium Hall", "Large Hall", "Plate", "Medium Chamber", "Large Chamber", "Cathedral"]
let FOLDERS = ["Kicks", "Snares", "Hats", "808s", "Percs", "Synths"]
let MAX_BARS = 256
private let LETTER: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
private let SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
private let FLAT = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

func pitchClass(_ text: String) -> Int? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard let first = t.first, let base = LETTER[Character(first.uppercased())] else { return nil }
    let rest = t.dropFirst()
    let acc = rest.hasPrefix("#") ? 1 : rest.hasPrefix("b") ? -1 : 0
    return (base + acc + 12) % 12
}

/// "E1", "F#3", "Bb4". C4 is 60.
func parseNote(_ text: String) -> Int? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard let first = t.first, let base = LETTER[Character(first.uppercased())] else { return nil }
    var rest = t.dropFirst()
    var acc = 0
    if rest.hasPrefix("#") { acc = 1; rest = rest.dropFirst() } else if rest.hasPrefix("b") { acc = -1; rest = rest.dropFirst() }
    guard let octave = Int(rest.trimmingCharacters(in: .whitespaces)) else { return nil }
    return min(127, max(0, 12 * (octave + 1) + base + acc))
}

func scaleClasses(key: String, scale: String) -> [Int] {
    let root = pitchClass(key) ?? 0
    return (SCALES[scale] ?? SCALES["minor"]!).map { (root + $0) % 12 }
}

func usesFlats(key: String, scale: String) -> Bool {
    if key.dropFirst().contains("b") { return true }
    if key.contains("#") { return false }
    let pcs = scaleClasses(key: key, scale: scale)
    let clean: ([String]) -> Bool = { names in Set(pcs.map { names[$0].first! }).count == pcs.count }
    return !(clean(SHARP) && !clean(FLAT))
}

func noteName(_ midi: Int, flats: Bool = true) -> String {
    (flats ? FLAT : SHARP)[((midi % 12) + 12) % 12] + String(midi / 12 - 1)
}

struct Note: Codable, Equatable {
    var s: Double            // step from the start of the song
    var n: Int?              // pitch, for melodic tracks
    var l: Double?           // length in steps; nil lets the sound ring
    var v: Double = 0.8      // loudness 0...1
}

/// Every plugin setting for one track (or for the master). A value at rest means that control is doing nothing.
struct Plugins: Codable, Equatable {
    var tune = 0.0, cutoff = 20000.0, lowCut = 20.0, drive = 0.0, lofi = 0.0
    var eqLow = 0.0, eqMid = 0.0, eqMidFreq = 1000.0, eqHigh = 0.0
    var compThreshold = 0.0, compRatio = 4.0, compAttack = 10.0, compRelease = 120.0, compMakeup = 0.0
    var chorus = 0.0, chorusRate = 0.8, chorusDepth = 0.5
    var flanger = 0.0, flangerRate = 0.3, flangerDepth = 0.6, flangerFeedback = 0.5
    var phaser = 0.0, phaserRate = 0.4, phaserDepth = 0.7, phaserFeedback = 0.4
    var delay = 0.0, delayFeedback = 0.4, delayTone = 6000.0, delayTime = "1/8d"
    var reverb = 0.0, reverbSpace = "Medium Hall"
    var loudness = 0.0       // master only: push into the limiter, in dB
    var hold = 0.0           // 0 lets a note fade the way the sound does; 1 keeps it at full level for its whole length
    var attack = 1.0         // ms a note takes to come in
    var release = 90.0       // ms a note takes to fade once it ends
}

extension Plugins {
    // Songs saved by an earlier build do not have the newer controls. Anything missing stays at rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var p = Plugins()
        let numbers: [(CodingKeys, WritableKeyPath<Plugins, Double>)] = [
            (.tune, \.tune), (.cutoff, \.cutoff), (.lowCut, \.lowCut), (.drive, \.drive), (.lofi, \.lofi),
            (.eqLow, \.eqLow), (.eqMid, \.eqMid), (.eqMidFreq, \.eqMidFreq), (.eqHigh, \.eqHigh),
            (.compThreshold, \.compThreshold), (.compRatio, \.compRatio), (.compAttack, \.compAttack), (.compRelease, \.compRelease), (.compMakeup, \.compMakeup),
            (.chorus, \.chorus), (.chorusRate, \.chorusRate), (.chorusDepth, \.chorusDepth),
            (.flanger, \.flanger), (.flangerRate, \.flangerRate), (.flangerDepth, \.flangerDepth), (.flangerFeedback, \.flangerFeedback),
            (.phaser, \.phaser), (.phaserRate, \.phaserRate), (.phaserDepth, \.phaserDepth), (.phaserFeedback, \.phaserFeedback),
            (.delay, \.delay), (.delayFeedback, \.delayFeedback), (.delayTone, \.delayTone), (.reverb, \.reverb), (.loudness, \.loudness),
            (.hold, \.hold), (.attack, \.attack), (.release, \.release),
        ]
        for (key, path) in numbers { if let v = try c.decodeIfPresent(Double.self, forKey: key) { p[keyPath: path] = v } }
        if let v = try c.decodeIfPresent(String.self, forKey: .delayTime) { p.delayTime = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .reverbSpace) { p.reverbSpace = v }
        self = p
    }
}

/// One version of a part. A track can hold several; they show as sub-tracks and one of them plays.
struct Take: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var notes: [Note]
}

struct Track: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var sound: String        // id of a sound in the crate
    var vol = 0.8
    var mute = false
    var mono = false         // one note at a time
    var notes: [Note] = []   // what plays: the notes of the chosen take
    var fx = Plugins()
    var takes: [Take] = []   // every version of the part, when there is more than one
    var take = 0             // which of them is playing
}

extension Track {
    // Songs saved by an earlier build have no takes; read them anyway.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sound = try c.decode(String.self, forKey: .sound)
        vol = try c.decodeIfPresent(Double.self, forKey: .vol) ?? 0.8
        mute = try c.decodeIfPresent(Bool.self, forKey: .mute) ?? false
        mono = try c.decodeIfPresent(Bool.self, forKey: .mono) ?? false
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        fx = try c.decodeIfPresent(Plugins.self, forKey: .fx) ?? Plugins()
        takes = try c.decodeIfPresent([Take].self, forKey: .takes) ?? []
        take = try c.decodeIfPresent(Int.self, forKey: .take) ?? 0
    }
}

/// A song saved as a file the person can keep, copy and reopen: "Name.crate". Plain JSON inside.
struct ProjectFile: Codable {
    var format = "crate-project"
    var version = 1
    var saved: String
    var song: Song
}

/// One mastering choice: a named set of master plugin settings. They show as lines under Master and one is in use.
struct MasterOption: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var fx: Plugins
}

struct Song: Codable, Equatable {
    var bpm = 86.0
    var key = "E"
    var scale = "minor"
    var bars = 8
    var tracks: [Track] = []
    var master = Plugins()             // the master settings in use
    var masters: [MasterOption]?       // mastering choices, when more than one has been offered (optional so older songs still load)
    var masterPick: Int?               // which of them is in use

    var steps: Double { Double(bars * 16) }
    var flats: Bool { usesFlats(key: key, scale: scale) }
    var seconds: Double { steps * 60 / bpm / 4 }
}

// MARK: - The plugin controls, described once and used by the window, by Claude's tool, and by the dice

struct Knob {
    let key: String
    let label: String
    let path: WritableKeyPath<Plugins, Double>
    let range: ClosedRange<Double>
    let rest: Double
    let unit: String
    var log = false

    func show(_ v: Double) -> String {
        switch unit {
        case "%": return "\(Int((v * 100).rounded()))%"
        case "Hz": return v >= 1000 ? String(format: "%.1f kHz", v / 1000) : v < 20 ? String(format: "%.2f Hz", v) : "\(Int(v.rounded())) Hz"
        case "dB": return String(format: "%@%.1f dB", v > 0 ? "+" : "", v)
        case "ms": return v < 10 ? String(format: "%.1f ms", v) : "\(Int(v.rounded())) ms"
        case "st": return String(format: "%@%d st", v > 0 ? "+" : "", Int(v.rounded()))
        case ":1": return String(format: "%.1f:1", v)
        default: return String(format: "%.2f %@", v, unit)
        }
    }
}

struct Module {
    let id: String
    let name: String
    let knobs: [Knob]
    var masterToo = false
    var masterOnly = false
}

let MODULES: [Module] = [
    Module(id: "hold", name: "Hold", knobs: [
        Knob(key: "hold", label: "Hold", path: \.hold, range: 0...1, rest: 0, unit: "%"),
        Knob(key: "attack", label: "Attack", path: \.attack, range: 1...2000, rest: 1, unit: "ms", log: true),
        Knob(key: "release", label: "Release", path: \.release, range: 10...4000, rest: 90, unit: "ms", log: true),
    ]),
    Module(id: "tone", name: "Tone", knobs: [
        Knob(key: "tune", label: "Tune", path: \.tune, range: -12...12, rest: 0, unit: "st"),
        Knob(key: "cutoff", label: "Cutoff", path: \.cutoff, range: 80...20000, rest: 20000, unit: "Hz", log: true),
        Knob(key: "low_cut", label: "Low cut", path: \.lowCut, range: 20...8000, rest: 20, unit: "Hz", log: true),
        Knob(key: "drive", label: "Drive", path: \.drive, range: 0...1, rest: 0, unit: "%"),
        Knob(key: "lofi", label: "Lo-fi", path: \.lofi, range: 0...1, rest: 0, unit: "%"),
    ]),
    Module(id: "chorus", name: "Chorus", knobs: [
        Knob(key: "chorus", label: "Mix", path: \.chorus, range: 0...1, rest: 0, unit: "%"),
        Knob(key: "chorus_rate", label: "Rate", path: \.chorusRate, range: 0.05...5, rest: 0.8, unit: "Hz", log: true),
        Knob(key: "chorus_depth", label: "Depth", path: \.chorusDepth, range: 0...1, rest: 0.5, unit: "%"),
    ]),
    Module(id: "flanger", name: "Flanger", knobs: [
        Knob(key: "flanger", label: "Mix", path: \.flanger, range: 0...1, rest: 0, unit: "%"),
        Knob(key: "flanger_rate", label: "Rate", path: \.flangerRate, range: 0.05...5, rest: 0.3, unit: "Hz", log: true),
        Knob(key: "flanger_depth", label: "Depth", path: \.flangerDepth, range: 0...1, rest: 0.6, unit: "%"),
        Knob(key: "flanger_feedback", label: "Feedback", path: \.flangerFeedback, range: 0...0.9, rest: 0.5, unit: "%"),
    ]),
    Module(id: "phaser", name: "Phaser", knobs: [
        Knob(key: "phaser", label: "Mix", path: \.phaser, range: 0...1, rest: 0, unit: "%"),
        Knob(key: "phaser_rate", label: "Rate", path: \.phaserRate, range: 0.05...5, rest: 0.4, unit: "Hz", log: true),
        Knob(key: "phaser_depth", label: "Depth", path: \.phaserDepth, range: 0...1, rest: 0.7, unit: "%"),
        Knob(key: "phaser_feedback", label: "Feedback", path: \.phaserFeedback, range: 0...0.9, rest: 0.4, unit: "%"),
    ]),
    Module(id: "comp", name: "Compressor", knobs: [
        Knob(key: "comp_threshold", label: "Threshold", path: \.compThreshold, range: -40...0, rest: 0, unit: "dB"),
        Knob(key: "comp_ratio", label: "Ratio", path: \.compRatio, range: 1...20, rest: 4, unit: ":1"),
        Knob(key: "comp_attack", label: "Attack", path: \.compAttack, range: 0.1...200, rest: 10, unit: "ms", log: true),
        Knob(key: "comp_release", label: "Release", path: \.compRelease, range: 10...1500, rest: 120, unit: "ms", log: true),
        Knob(key: "comp_makeup", label: "Makeup", path: \.compMakeup, range: 0...24, rest: 0, unit: "dB"),
    ], masterToo: true),
    Module(id: "delay", name: "Delay", knobs: [
        Knob(key: "delay", label: "Mix", path: \.delay, range: 0...1, rest: 0, unit: "%"),
        Knob(key: "delay_feedback", label: "Repeats", path: \.delayFeedback, range: 0...0.9, rest: 0.4, unit: "%"),
        Knob(key: "delay_tone", label: "Tone", path: \.delayTone, range: 500...16000, rest: 6000, unit: "Hz", log: true),
    ]),
    Module(id: "reverb", name: "Reverb", knobs: [
        Knob(key: "reverb", label: "Mix", path: \.reverb, range: 0...1, rest: 0, unit: "%"),
    ]),
    Module(id: "eq", name: "EQ", knobs: [
        Knob(key: "eq_low", label: "Low", path: \.eqLow, range: -12...12, rest: 0, unit: "dB"),
        Knob(key: "eq_mid", label: "Mid", path: \.eqMid, range: -12...12, rest: 0, unit: "dB"),
        Knob(key: "eq_mid_freq", label: "Mid at", path: \.eqMidFreq, range: 200...8000, rest: 1000, unit: "Hz", log: true),
        Knob(key: "eq_high", label: "High", path: \.eqHigh, range: -12...12, rest: 0, unit: "dB"),
    ], masterToo: true),
    Module(id: "loud", name: "Limiter", knobs: [
        Knob(key: "loudness", label: "Loudness", path: \.loudness, range: 0...18, rest: 0, unit: "dB"),
    ], masterOnly: true),
]
let ALL_KNOBS: [Knob] = MODULES.flatMap { $0.knobs }

func modules(master: Bool) -> [Module] { MODULES.filter { master ? ($0.masterToo || $0.masterOnly) : !$0.masterOnly } }

/// What a module is doing, in a few words. Empty when it is off.
func summary(_ m: Module, _ fx: Plugins) -> String {
    let gate: [String: WritableKeyPath<Plugins, Double>] = ["comp": \.compThreshold, "chorus": \.chorus, "flanger": \.flanger, "phaser": \.phaser, "delay": \.delay, "reverb": \.reverb]
    if let g = gate[m.id], fx[keyPath: g] == 0, !(m.id == "comp" && fx.compMakeup != 0) { return "" }
    var parts = m.knobs.filter { abs(fx[keyPath: $0.path] - $0.rest) > 1e-9 }.map { "\($0.label.lowercased()) \($0.show(fx[keyPath: $0.path]))" }
    if m.id == "delay", fx.delay > 0 { parts.append(fx.delayTime) }
    if m.id == "reverb", fx.reverb > 0 { parts.append(fx.reverbSpace.lowercased()) }
    return parts.joined(separator: ", ")
}

func chainText(_ fx: Plugins, master: Bool) -> String {
    modules(master: master).compactMap { m in let t = summary(m, fx); return t.isEmpty ? nil : "\(m.name.lowercased()): \(t)" }.joined(separator: "; ")
}
