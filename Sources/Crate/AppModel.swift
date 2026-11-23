import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct Oops: LocalizedError { let text: String; var errorDescription: String? { text }; init(_ t: String) { text = t } }

/// Everything the window shows and everything Claude can change. Lives on the main thread.
final class AppModel: ObservableObject {
    static let port: UInt16 = 8790
    @Published var song: Song
    @Published var open: String? = nil          // id of the open track, or "master"
    @Published var playing = false
    @Published var recording = false
    @Published var kit = "Lofi"
    @Published var folder = "Kicks"
    @Published var picked: String? = nil
    @Published var status = "Ready"
    @Published var head = -1.0                  // 0...1 through the song, -1 when stopped at the top
    var cue = 0.0                               // where Play starts from, in steps; set by dragging the play line
    var dragBar = -1                            // the bar under the pointer during a drag of the play line
    @Published var canUndo = false
    @Published var hidden: Set<String>
    @Published var octave = 0
    @Published var claudeSeen = false
    @Published var backs: [String: Int] = [:]   // how many steps "Back" can take, per track
    var flat = false                            // true only when the window is drawn into a picture
    var scrolls = false                         // with flat: keep the real scrolling lists anyway (for a screenshot of the window as it looks)
    @Published var projectURL: URL? = nil       // the project file this song was opened from or last saved to
    @Published var palette = Palette.standard { // the window's colours
        didSet { Theme.look = Look(palette); paletteStamp += 1; if !flat, let d = try? JSONEncoder().encode(palette) { UserDefaults.standard.set(d, forKey: "palette") } }
    }
    @Published var paletteStamp = 0
    @Published var paletteBefore: Palette? = nil // what Randomize or Reset replaced, for Undo in the Colors window
    @Published var selSection: Int? = nil       // the first section picked on the ruler (from 0), if any
    @Published var selCount = 1                 // how many sections in a row are picked
    @Published var roll = UserDefaults.standard.bool(forKey: "roll") { didSet { if !flat { UserDefaults.standard.set(roll, forKey: "roll") } } }   // the piano roll is showing in the open track
    @Published var rollPage = 0                 // which page of bars the piano roll shows
    var rollLen = 2.0                           // how long a new note in the piano roll is, in steps: the length last used
    var probing = false                         // true only in the click test
    var played: [Int?] = []                     // in the click test: the notes asked for, in order
    private var typing: [Character: Int?] = [:] // keys on the typing keyboard that are held down, and the note each is playing
    var probe: [String: CGRect] = [:]           // in the click test: where the ruler, the lanes and the piano roll are in the window
    private var keyMonitor: Any?
    @Published var clip: SectionClip? = nil     // the copied section
    struct SectionClip { var bars: Int; var notes: [String: [Note]]; var only: String? = nil }   // notes per track id, steps counted from the start of the copy; only: the one track it was copied from, when it came from a track's lane
    private var savedSong: Song? = nil          // the song as it is in that file, to tell whether anything changed since
    var projectName: String { projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }
    var unsaved: Bool { projectURL == nil || savedSong != song }

    let lib = Library()
    private(set) var engine: Engine?
    private var undoStack: [Song] = []
    private var undoProject: [URL?] = []        // which project each undo step belongs to, so Undo after Open goes back to the right file
    private var history: [String: [Plugins]] = [:]
    private var soundHistory: [String: [String]] = [:]      // the sound each of those steps had, so Back can bring a rolled sound back too
    private var held: [Int: Double] = [:]
    private var takeHasUndo = false
    private var server: MCPServer?
    private var saveWork: DispatchWorkItem?

    static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Crate")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// quiet: no audio and no server, for drawing the window into a picture.
    init(quiet: Bool = false) {
        hidden = Set(UserDefaults.standard.stringArray(forKey: "hidden") ?? [])
        if let data = try? Data(contentsOf: AppModel.folderURL.appendingPathComponent("song.json")), let s = try? JSONDecoder().decode(Song.self, from: data) { song = AppModel.tidy(s) }
        else { song = AppModel.demo(lib) }
        if let d = UserDefaults.standard.data(forKey: "palette"), let p = try? JSONDecoder().decode(Palette.self, from: d) { palette = p; Theme.look = Look(p) }
        if let p = UserDefaults.standard.string(forKey: "project"), FileManager.default.fileExists(atPath: p) { projectURL = URL(fileURLWithPath: p); savedSong = AppModel.readProject(URL(fileURLWithPath: p)) }
        if quiet { flat = true; return }
        do { engine = try Engine(); engine?.load(song, lib) } catch { status = "Audio could not start: \(error.localizedDescription)" }
        let s = MCPServer(port: AppModel.port) { [weak self] msg, reply in
            DispatchQueue.main.async { reply(self?.rpc(msg)) }
        }
        do { try s.start(); server = s } catch { status = "Claude cannot connect: port \(AppModel.port) is busy" }
        installMonitors()
    }

    /// Keys that act on the picked section.
    func installMonitors() {
        // With a section picked on the ruler: Cmd-C copies it, Cmd-X cuts it, Cmd-V pastes over it, Shift-Cmd-V pastes in front of it as new bars,
        // Cmd-D puts a copy right after it, Esc lets go. With a track open, the letter keys play it (see keyNote). Typing in a
        // text box is left alone.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self, !(NSApp.keyWindow?.firstResponder is NSText) else { return e }
            let mods = e.modifierFlags.intersection([.command, .shift, .option, .control]), key = e.charactersIgnoringModifiers?.lowercased() ?? ""
            if e.type == .keyDown, let k = self.selSection {
                if mods == .command && key == "c" { self.copySection(k, count: self.selCount); return nil }
                if mods == .command && key == "x" { self.cutSection(k, count: self.selCount); return nil }
                if mods == .command && key == "v" { self.pasteSection(k, insert: false); return nil }
                if mods == [.command, .shift] && key == "v" { self.pasteSection(k, insert: true); return nil }
                if mods == .command && key == "d" { self.duplicateSection(k, count: self.selCount); return nil }
                if mods.isEmpty && e.keyCode == 53 { self.selSection = nil; self.selCount = 1; return nil }
            }
            guard mods.isEmpty, key.count == 1, let ch = key.first else { return e }
            if e.type == .keyUp {
                guard let held = self.typing.removeValue(forKey: ch) else { return e }
                self.keyUp(held); return nil
            }
            guard let note = self.keyNote(ch) else { return e }
            if !e.isARepeat { self.typing[ch] = .some(note.pitch); self.keyDown(note.pitch) }
            return nil
        }
    }

    /// The typing keyboard as a music keyboard for the open track. The middle row of letters (A S D F ...) is the notes of the key
    /// going up from the track's home note, the row above (Q W E ...) starts an octave higher and the row below (Z X C ...)
    /// an octave lower. On a drum track every one of those keys is a hit.
    static let keyRows: [(keys: String, octave: Int)] = [("asdfghjkl;'", 0), ("qwertyuiop[]", 1), ("zxcvbnm,./", -1)]
    func keyNote(_ ch: Character) -> (pitch: Int?, track: Int)? {
        guard let i = index(open), let info = lib.info(song.tracks[i].sound) else { return nil }
        for row in AppModel.keyRows {
            guard let at = row.keys.firstIndex(of: ch) else { continue }
            guard info.melodic, let base = homeNote(info) else { return (nil, i) }
            let scale = SCALES[song.scale] ?? SCALES["minor"]!, n = scale.count, degree = row.keys.distance(from: row.keys.startIndex, to: at) + row.octave * n
            let p = base + 12 * Int((Double(degree) / Double(n)).rounded(.down)) + scale[((degree % n) + n) % n]
            return p >= 0 && p <= 127 ? (p, i) : nil
        }
        return nil
    }
    /// The letter that plays each note on a track, for the labels beside the piano roll. Where two letters give the same note,
    /// the one on the middle row is shown.
    func keyLetters(_ t: Track) -> [Int: String] {
        guard let info = lib.info(t.sound), info.melodic, let base = homeNote(info) else { return [:] }
        let scale = SCALES[song.scale] ?? SCALES["minor"]!, n = scale.count
        var out: [Int: String] = [:]
        for row in AppModel.keyRows { for (k, ch) in row.keys.enumerated() {
            let degree = k + row.octave * n, p = base + 12 * Int((Double(degree) / Double(n)).rounded(.down)) + scale[((degree % n) + n) % n]
            if out[p] == nil { out[p] = String(ch).uppercased() }
        } }
        return out
    }

    /// Keys used to be listed with Db; the list says C# now. A song saved either way reads the same.
    static func tidy(_ s: Song) -> Song { var s = s; if !KEYS.contains(s.key), let pc = pitchClass(s.key) { s.key = KEYS[pc] }; return s }

    /// The song the app opens with: the sixteen-bar piece, read from the sounds folder.
    static func demo(_ lib: Library) -> Song {
        struct DemoTrack: Codable { let name: String; let sound: String; let vol: Double; let mono: Bool; let notes: [Note] }
        struct Demo: Codable { let bpm: Double; let key: String; let scale: String; let bars: Int; let tracks: [DemoTrack] }
        var song = Song()
        guard let data = try? Data(contentsOf: lib.dir.appendingPathComponent("demo.json")), let d = try? JSONDecoder().decode(Demo.self, from: data) else { return song }
        song.bpm = d.bpm; song.key = d.key; song.scale = d.scale; song.bars = d.bars
        song.tracks = d.tracks.enumerated().map { i, t in Track(id: "t\(i + 1)", name: t.name, sound: t.sound, vol: t.vol, mute: false, mono: t.mono, notes: t.notes, fx: Plugins()) }
        song.master.loudness = 2
        return song
    }

    // MARK: - Small helpers

    func index(_ id: String?) -> Int? { id.flatMap { i in song.tracks.firstIndex { $0.id == i } } }
    var flats: Bool { song.flats }
    func soundName(_ t: Track) -> String { lib.info(t.sound)?.name ?? "No sound" }
    func isMelodic(_ t: Track) -> Bool { lib.info(t.sound)?.melodic ?? false }
    var kits: [String] { ["All"] + Array(NSOrderedSet(array: lib.sounds.map { $0.kit })).compactMap { $0 as? String } }
    func visible(_ s: SoundInfo) -> Bool { !hidden.contains(s.id) && (kit == "All" || s.kit == kit) }
    var shown: [SoundInfo] { lib.sounds.filter { visible($0) && $0.folder == folder } }
    func count(_ f: String) -> Int { lib.sounds.filter { visible($0) && $0.folder == f }.count }

    /// The key's own note nearest to where a melodic sound was built.
    func homeNote(_ info: SoundInfo) -> Int? {
        guard info.melodic, let root = info.root else { return nil }
        let pc = pitchClass(song.key) ?? 0
        var n = root - (((root - pc) % 12) + 12) % 12
        if root - n > 6 { n += 12 }
        return n
    }

    /// The pads for a track: the notes of the scale, one octave, from the key's own note.
    func keys(for t: Track) -> [Int] {
        guard let info = lib.info(t.sound), let base = homeNote(info) else { return [] }
        return ((SCALES[song.scale] ?? SCALES["minor"]!) + [12]).map { min(127, max(0, base + 12 * octave + $0)) }
    }

    func save() {
        if flat { return }                          // a window drawn into a picture or a self-test never writes the song
        saveWork?.cancel()
        let snapshot = song
        let work = DispatchWorkItem { if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: AppModel.folderURL.appendingPathComponent("song.json")) } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// After notes, sounds or tracks change.
    func commit(_ note: String? = nil) {
        if let o = open, o != "master", index(o) == nil { open = nil }
        if let k = selSection, k >= sectionCount { selSection = nil; selCount = 1 }
        if let k = selSection { selCount = min(selCount, sectionCount - k) }
        rollPage = min(max(0, rollPage), rollPages - 1)
        engine?.load(song, lib); save()
        if let note { status = note }
    }

    func pushUndo() { undoStack.append(song); undoProject.append(projectURL); if undoStack.count > 40 { undoStack.removeFirst(); undoProject.removeFirst() }; canUndo = true }
    func undo() { guard let s = undoStack.popLast() else { return }; let p = undoProject.popLast() ?? projectURL; song = s; if p != projectURL { setProject(p) }; canUndo = !undoStack.isEmpty; commit("Undone") }
    /// A tool call that failed changes nothing: take back the snapshot made for it.
    func undoStack_popForFailedCall() -> Song? { let s = undoStack.popLast(); let p = undoProject.popLast() ?? projectURL; if p != projectURL { setProject(p) }; canUndo = !undoStack.isEmpty; return s }

    // MARK: - Transport and recording

    func togglePlay() {
        guard let e = engine else { return }
        if playing { stopAll(); return }
        guard recording || song.tracks.contains(where: { !$0.notes.isEmpty && !$0.mute }) else { status = "Nothing to play yet. Tell Claude what you want."; return }
        e.play(fromStep: cue); playing = true
    }
    func stopAll() {
        engine?.stop(); playing = false; head = cue > 0 ? cue / song.steps : -1
        if recording { recording = false; status = "Recording stopped. What you played is on the grid." }
    }
    func toggleRecord() {
        if recording { recording = false; status = "Recording stopped. What you played is on the grid."; return }
        guard let i = index(open) else { status = "Open a track first, then press Record"; return }
        recording = true; takeHasUndo = false; held = [:]
        if !playing { engine?.play(fromStep: cue); playing = true }
        status = "Recording \(song.tracks[i].name). Play it on the letter keys."
    }
    func tick() { if playing, let p = engine?.position { head = p / song.steps } }
    /// Move the play line to a bar (from 0). It lands on the start of the bar so everything in that bar sounds.
    /// While the song plays it jumps there; while stopped, that is where Play will start.
    func seek(bar: Int) {
        let b = min(song.bars - 1, max(0, bar))
        cue = Double(b * 16)
        if playing { engine?.seek(toStep: cue) }
        head = b == 0 && !playing ? -1 : cue / song.steps
    }

    func keyDown(_ pitch: Int?) {
        guard let i = index(open) else { return }
        engine?.hit(track: i, pitch: pitch, song: song, lib: lib)
        if probing { played.append(pitch) }
        if recording, let pos = engine?.position { held[pitch ?? -1] = pos - 0.03 / (60 / song.bpm / 4) }    // what is heard runs a touch behind the clock
    }
    func keyUp(_ pitch: Int?) {
        guard recording, let i = index(open), let down = held.removeValue(forKey: pitch ?? -1), let now = engine?.position else { return }
        var length = now - down
        if length < 0 { length += song.steps }
        var s = down.rounded()                                      // put it on the nearest sixteenth
        if s < 0 { s += song.steps }
        if s >= song.steps { s = 0 }
        let melodic = isMelodic(song.tracks[i])
        let note = Note(s: s, n: melodic ? pitch : nil, l: melodic ? max(1, length.rounded()) : nil, v: 0.8)
        if !takeHasUndo { pushUndo(); takeHasUndo = true }
        song.tracks[i].notes.removeAll { abs($0.s - s) < 0.01 && $0.n == note.n }
        song.tracks[i].notes.append(note)
        song.tracks[i].notes.sort { $0.s < $1.s }
        commit()
    }

    // MARK: - Sounds and tracks

    func pick(_ id: String) {
        picked = id
        guard let info = lib.info(id) else { return }
        engine?.audition(info, lib, pitch: homeNote(info), song: song)
    }
    func hide(_ id: String) { hidden.insert(id); UserDefaults.standard.set(Array(hidden), forKey: "hidden"); status = "Removed from the crate" }
    func auditionTrack(_ id: String) {
        guard let i = index(id), let info = lib.info(song.tracks[i].sound) else { return }
        engine?.hit(track: i, pitch: homeNote(info), song: song, lib: lib)
    }
    @discardableResult func addTrack(sound id: String, name: String? = nil) throws -> Int {
        guard let info = lib.info(id) else { throw Oops("That sound is not in the crate.") }
        guard song.tracks.count < Engine.maxTracks else { throw Oops("There is room for \(Engine.maxTracks) tracks. Remove one first.") }
        var t = Track(id: "t" + String(UUID().uuidString.prefix(6)).lowercased(), name: String((name ?? info.name).prefix(24)), sound: id)
        t.mono = info.folder == "808s"
        song.tracks.append(t)
        return song.tracks.count - 1
    }
    func drop(sound id: String, on track: String?) {
        pushUndo()
        if let i = index(track), let info = lib.info(id) {
            song.tracks[i].sound = id
            if info.melodic, let home = homeNote(info) { for j in song.tracks[i].notes.indices where song.tracks[i].notes[j].n == nil { song.tracks[i].notes[j].n = home } }
            commit("\(song.tracks[i].name) now plays \(info.name)")
        } else {
            do { let i = try addTrack(sound: id); open = song.tracks[i].id; commit("\(song.tracks[i].name) is on a new track. Tell Claude what it should play.") }
            catch { _ = undoStack.popLast(); canUndo = !undoStack.isEmpty; status = error.localizedDescription }
        }
    }
    func removeTrack(_ id: String) { guard let i = index(id) else { return }; pushUndo(); let n = song.tracks[i].name; song.tracks.remove(at: i); commit("Removed \(n). Undo brings it back.") }
    func toggleMute(_ id: String) { guard let i = index(id) else { return }; pushUndo(); song.tracks[i].mute.toggle(); engine?.applyPlugins(song); save() }
    func toggleOpen(_ id: String) { open = open == id ? nil : id; octave = 0 }

    // MARK: - Colours

    func randomizeColors() { let was = palette; palette = Palette.random(seed: UInt64.random(in: 0...UInt64.max)); paletteBefore = was }
    func resetColors() { let was = palette; palette = .standard; paletteBefore = was }
    func undoColors() { if let p = paletteBefore { palette = p; paletteBefore = nil } }

    // MARK: - Sections: the numbered blocks on the ruler. Pick, copy, paste, duplicate and delete work on whole sections.

    /// How many bars one section on the ruler is.
    var sectionBars: Int { song.bars <= 16 ? 1 : song.bars <= 32 ? 4 : 8 }
    var sectionCount: Int { (song.bars + sectionBars - 1) / sectionBars }
    private func sectionSteps(_ k: Int, _ count: Int = 1) -> (start: Double, len: Double)? {
        let a = k * sectionBars
        guard k >= 0, a < song.bars else { return nil }
        return (Double(a * 16), Double(min(sectionBars * max(1, count), song.bars - a) * 16))
    }
    func sectionLabel(_ k: Int, _ count: Int = 1) -> String {
        let word = sectionBars == 1 ? "bar" : "section", last = min(sectionCount, k + max(1, count))
        return last - k > 1 ? "\(word)s \(k + 1) to \(last)" : "\(word) \(k + 1)"
    }
    /// A click on the ruler picks a section (click it again to let go). With Shift held, what is picked stretches to the one clicked.
    func selectSection(_ k: Int, extend: Bool = false) {
        guard k >= 0, k < sectionCount else { return }
        if extend, let a = selSection { let lo = min(a, k), hi = max(a + selCount - 1, k); selSection = lo; selCount = hi - lo + 1 }
        else if selSection == k && selCount == 1 { selSection = nil }
        else { selSection = k; selCount = 1 }
        if let s = selSection { rollPage = min(rollPages - 1, (s * sectionBars) / max(1, rollBars)) }
    }
    /// Shift-click on a section: pick it and bring up copy, paste and the rest. A second Shift-click elsewhere stretches the
    /// pick to reach it; a Shift-click inside what is picked lets go.
    func pickSection(_ k: Int) {
        guard k >= 0, k < sectionCount else { return }
        if let a = selSection {
            if k >= a && k < a + selCount { selSection = nil; selCount = 1 }
            else { let lo = min(a, k), hi = max(a + selCount - 1, k); selSection = lo; selCount = hi - lo + 1 }
        } else { selSection = k; selCount = 1 }
    }
    /// A plain click on a section: turn the piano roll to those bars. A click in a track's own lane also opens that track
    /// with the roll showing; a click on the ruler shows the bars for whichever track is open.
    func showInRoll(bar: Int, track id: String? = nil) {
        rollPage = min(rollPages - 1, max(0, bar) / max(1, rollBars))
        if let id, index(id) != nil { if open != id { open = id; octave = 0 }; roll = true }
        else if index(open) != nil { roll = true }
    }
    /// Run an edit over what every track plays and over its other versions too, so they all stay lined up.
    private func everyVersion(_ edit: ([Note]) -> [Note]) {
        for i in song.tracks.indices {
            stash(i)
            song.tracks[i].notes = edit(song.tracks[i].notes).sorted { $0.s < $1.s }
            for j in song.tracks[i].takes.indices { song.tracks[i].takes[j].notes = edit(song.tracks[i].takes[j].notes).sorted { $0.s < $1.s } }
        }
    }
    /// What every track plays between two places, with steps counted from the first.
    private func cut(_ start: Double, _ len: Double) -> SectionClip {
        var notes: [String: [Note]] = [:]
        for t in song.tracks { notes[t.id] = t.notes.filter { $0.s >= start && $0.s < start + len }.map { var n = $0; n.s -= start; if let l = n.l { n.l = min(l, len - n.s) }; return n } }
        return SectionClip(bars: Int(len / 16), notes: notes)
    }
    /// Put a clip into the song at a step: over what is there, or (insert) as new bars that push the rest along.
    private func place(_ c: SectionClip, at start: Double, insert: Bool) {
        let len = insert ? Double(c.bars * 16) : min(Double(c.bars * 16), song.steps - start)
        if insert {
            everyVersion { $0.map { var n = $0; if n.s >= start { n.s += len }; return n } }
            song.bars += c.bars
        }
        for i in song.tracks.indices {
            stash(i)
            var notes = song.tracks[i].notes.filter { !($0.s >= start && $0.s < start + len) }
            for n in c.notes[song.tracks[i].id] ?? [] where n.s < len { var m = n; m.s += start; if let l = m.l { m.l = min(l, len - n.s) }; notes.append(m) }
            song.tracks[i].notes = notes.sorted { $0.s < $1.s }
            stash(i)
        }
    }
    func copySection(_ k: Int, count: Int = 1) {
        guard let r = sectionSteps(k, count) else { return }
        clip = cut(r.start, r.len)
        status = "Copied \(sectionLabel(k, count))"
    }
    func deleteSection(_ k: Int, count: Int = 1) {
        guard let r = sectionSteps(k, count), song.bars > Int(r.len / 16) else { return }
        let label = sectionLabel(k, count)
        pushUndo()
        everyVersion { $0.filter { !($0.s >= r.start && $0.s < r.start + r.len) }.map { var n = $0; if n.s >= r.start { n.s -= r.len }; return n } }
        song.bars -= Int(r.len / 16)
        cue = 0; selSection = nil; selCount = 1
        commit("Deleted \(label). Undo brings it back.")
    }
    /// Paste what was copied over section k, or (insert) in front of it as new bars that make the song longer.
    /// With insert, k may be one past the last section: the copy then goes on the end.
    func pasteSection(_ k: Int, insert: Bool) {
        guard let c = clip else { return }
        let start: Double
        if insert && k * sectionBars >= song.bars { start = song.steps } else if let r = sectionSteps(k) { start = r.start } else { return }
        if insert && song.bars + c.bars > MAX_BARS { status = "The song cannot get longer than \(MAX_BARS) bars"; return }
        pushUndo()
        place(c, at: start, insert: insert)
        if insert { selSection = nil; selCount = 1 }
        commit(insert ? "Pasted as new bars. Undo takes them out." : "Pasted. Undo puts back what was there.")
    }
    /// A copy of the picked sections, put in right after them. What was copied earlier stays copied.
    func duplicateSection(_ k: Int, count: Int = 1) {
        guard let r = sectionSteps(k, count) else { return }
        let c = cut(r.start, r.len), label = sectionLabel(k, count)
        if song.bars + c.bars > MAX_BARS { status = "The song cannot get longer than \(MAX_BARS) bars"; return }
        pushUndo()
        place(c, at: r.start + r.len, insert: true)
        selSection = nil; selCount = 1
        commit("Duplicated \(label). Undo takes the copy out.")
    }

    // MARK: - The right-click menu's copy and paste: a section of one track or of every track, pasted into one section or looped across many

    /// The notes a lane shows: a track's playing version, or (take) another of its versions.
    private func laneNotes(_ i: Int, _ take: Int?) -> [Note] {
        let t = song.tracks[i]
        if let k = take, k != t.take, k < t.takes.count { return t.takes[k].notes }
        return t.notes
    }
    private func setLaneNotes(_ i: Int, _ take: Int?, _ notes: [Note]) {
        let sorted = notes.sorted { $0.s < $1.s }
        if let k = take, k != song.tracks[i].take, k < song.tracks[i].takes.count { song.tracks[i].takes[k].notes = sorted }
        else { song.tracks[i].notes = sorted; stash(i) }
    }
    /// Copy bars (counted from 0). With a track, only that track's part: the version given, or the one playing. Without, every track.
    func copyBars(_ bar: Int, count: Int = 1, track: String? = nil, take: Int? = nil) {
        let b = min(song.bars - 1, max(0, bar)), n = max(1, min(count, song.bars - b)), start = Double(b * 16), len = Double(n * 16)
        func slice(_ notes: [Note]) -> [Note] { notes.filter { $0.s >= start && $0.s < start + len }.map { var x = $0; x.s -= start; if let l = x.l { x.l = min(l, len - x.s) }; return x } }
        var out: [String: [Note]] = [:]
        let one = index(track)
        if let id = track, let i = one { out[id] = slice(laneNotes(i, take)) } else { for t in song.tracks { out[t.id] = slice(t.notes) } }
        clip = SectionClip(bars: n, notes: out, only: one != nil ? track : nil)
        status = "Copied " + (n == 1 ? "bar \(b + 1)" : "bars \(b + 1) to \(b + n)") + (one.map { " of \(song.tracks[$0].name)" } ?? "")
    }
    /// Cut: copy the bars, then empty them. The bars stay in the song, silent, so nothing after them moves.
    func cutBars(_ bar: Int, count: Int = 1, track: String? = nil, take: Int? = nil) {
        let b = min(song.bars - 1, max(0, bar)), n = max(1, min(count, song.bars - b)), start = Double(b * 16), len = Double(n * 16)
        copyBars(b, count: n, track: track, take: take)
        pushUndo()
        let one = index(track)
        for i in song.tracks.indices where one == nil || one == i {
            let version = one == nil ? nil : take
            setLaneNotes(i, version, laneNotes(i, version).filter { !($0.s >= start && $0.s < start + len) })
        }
        commit("Cut " + (n == 1 ? "bar \(b + 1)" : "bars \(b + 1) to \(b + n)") + (one.map { " of \(song.tracks[$0].name)" } ?? "") + ". Paste puts it somewhere else; Undo brings it back.")
    }
    func cutSection(_ k: Int, count: Int = 1) { guard let r = sectionSteps(k, count) else { return }; cutBars(Int(r.start / 16), count: Int(r.len / 16)) }
    /// Paste what was copied, starting at a bar (from 0), over what is there. fill is how many bars to cover, repeating the copy
    /// as often as it takes (the loop option); nil pastes it once. With a track, only that track is written, whatever the copy
    /// came from; without, a copy of one track goes back to that track and a copy of every track goes to every track.
    func pasteBars(_ bar: Int, fill: Int? = nil, track: String? = nil, take: Int? = nil) {
        guard let c = clip, c.bars > 0 else { return }
        let b = min(song.bars - 1, max(0, bar)), total = max(1, min(fill ?? c.bars, song.bars - b))
        let start = Double(b * 16), len = Double(total * 16), unit = Double(c.bars * 16)
        var jobs: [(Int, [Note])] = []
        if let id = track, let i = index(id) { jobs = [(i, c.notes[c.only ?? id] ?? [])] }
        else if let only = c.only { if let i = index(only) { jobs = [(i, c.notes[only] ?? [])] } }
        else { jobs = song.tracks.indices.map { ($0, c.notes[song.tracks[$0].id] ?? []) } }
        guard !jobs.isEmpty else { return }
        let version = track == nil ? nil : take
        pushUndo()
        for (i, src) in jobs {
            let info = lib.info(song.tracks[i].sound), melodic = info?.melodic ?? false, home = info.flatMap { homeNote($0) }
            var notes = laneNotes(i, version).filter { !($0.s >= start && $0.s < start + len) }
            var at = 0.0
            while at < len {
                for n in src where n.s + at < len {
                    var x = n
                    x.s += start + at
                    if let l = x.l { x.l = min(l, len - (n.s + at)) }
                    if melodic { if x.n == nil { x.n = home; x.l = x.l ?? 1 } } else { x.n = nil; x.l = nil }      // a part pasted onto a different kind of track still plays
                    notes.append(x)
                }
                at += unit
            }
            setLaneNotes(i, version, notes)
        }
        let whereTo = total == 1 ? "bar \(b + 1)" : "bars \(b + 1) to \(b + total)"
        commit((fill != nil && total > c.bars ? "Looped across " : "Pasted into ") + whereTo + ". Undo puts back what was there.")
    }

    // MARK: - The piano roll: notes edited by hand, on the version that is playing

    /// The roll shows up to eight bars at a time.
    var rollBars: Int { max(1, min(8, song.bars)) }
    var rollPages: Int { max(1, (song.bars + rollBars - 1) / rollBars) }
    var rollFirstBar: Int { min(max(0, rollPage), rollPages - 1) * rollBars }
    /// The stretch of notes the roll shows for each track, lowest to highest. It is worked out once and then held still, so the
    /// grid does not slide under the pointer while notes are being added. It only grows, and only between edits.
    private var rollSpans: [String: ClosedRange<Int>] = [:]
    private func rollSpan(_ t: Track, home: Int) -> ClosedRange<Int> {
        let used = t.notes.compactMap { $0.n }
        if let s = rollSpans[t.id], used.allSatisfy({ s.contains($0) }) { return s }
        var lo = (used.min() ?? home) - 7, hi = (used.max() ?? home) + 7
        if hi - lo < 24 { let more = 24 - (hi - lo); lo -= more / 2; hi += more - more / 2 }
        if let s = rollSpans[t.id] { lo = min(lo, s.lowerBound); hi = max(hi, s.upperBound) }
        let s = max(0, lo)...min(127, hi)
        rollSpans[t.id] = s
        return s
    }
    /// The rows of the roll for a track, highest first: the notes of the key around what the track plays, plus any note it
    /// already plays outside the key. Empty for drums, which get a single row.
    func rollRows(_ t: Track) -> [Int] {
        guard let info = lib.info(t.sound), info.melodic, let home = homeNote(info) else { return [] }
        let inKey = Set(scaleClasses(key: song.key, scale: song.scale)), usedSet = Set(t.notes.compactMap { $0.n })
        return rollSpan(t, home: home).reversed().filter { inKey.contains($0 % 12) || usedSet.contains($0) }
    }
    /// A new note. Returns where it sits in the track's notes until the edit is finished.
    func rollAdd(_ id: String, step: Double, pitch: Int?) -> Int? {
        guard let i = index(id), step >= 0, step < song.steps else { return nil }
        let melodic = isMelodic(song.tracks[i])
        if melodic && pitch == nil { return nil }
        song.tracks[i].notes.append(Note(s: step, n: melodic ? pitch : nil, l: melodic ? max(1, min(rollLen, song.steps - step)) : nil, v: 0.8))
        engine?.hit(track: i, pitch: melodic ? pitch : nil, song: song, lib: lib)
        return song.tracks[i].notes.count - 1
    }
    /// Move a note, change its pitch, or change how long it lasts.
    func rollChange(_ id: String, _ k: Int, step: Double? = nil, pitch: Int? = nil, len: Double? = nil) {
        guard let i = index(id), k < song.tracks[i].notes.count else { return }
        var n = song.tracks[i].notes[k]
        if let s = step { n.s = min(song.steps - 0.25, max(0, s)); if let l = n.l { n.l = min(l, song.steps - n.s) } }
        if let p = pitch, n.n != nil, p != n.n { n.n = p; engine?.hit(track: i, pitch: p, song: song, lib: lib) }
        if let l = len, n.n != nil { n.l = max(1, min(l, song.steps - n.s)); rollLen = n.l ?? rollLen }
        if n != song.tracks[i].notes[k] { song.tracks[i].notes[k] = n }
    }
    func rollRemove(_ id: String, _ k: Int) { guard let i = index(id), k < song.tracks[i].notes.count else { return }; song.tracks[i].notes.remove(at: k) }
    /// The edit is finished: put the notes in order, keep them with their version, and send them to the engine.
    func rollDone(_ id: String) {
        guard let i = index(id) else { return }
        song.tracks[i].notes.sort { $0.s < $1.s }; stash(i)
        // A note placed right at the top or bottom of the grid gives it another octave that way, now that the edit is over.
        if let s = rollSpans[id], let lo = song.tracks[i].notes.compactMap({ $0.n }).min(), let hi = song.tracks[i].notes.compactMap({ $0.n }).max() {
            rollSpans[id] = max(0, lo - s.lowerBound < 3 ? s.lowerBound - 12 : s.lowerBound)...min(127, s.upperBound - hi < 3 ? s.upperBound + 12 : s.upperBound)
        }
        commit()
    }

    // MARK: - Project files: the song saved as "Name.crate"

    static let projectType = UTType("us.okeke.crate.project") ?? UTType(filenameExtension: "crate") ?? .json
    /// Where projects and exported songs go unless the person picks somewhere else.
    static var projectsURL: URL {
        let dir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("Crate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func readProject(_ url: URL) -> Song? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let p = try? JSONDecoder().decode(ProjectFile.self, from: data) { return tidy(p.song) }
        return (try? JSONDecoder().decode(Song.self, from: data)).map { tidy($0) }
    }
    func setProject(_ url: URL?) {
        projectURL = url; savedSong = url.flatMap { AppModel.readProject($0) }
        if let u = url { UserDefaults.standard.set(u.path, forKey: "project") } else { UserDefaults.standard.removeObject(forKey: "project") }
    }
    func writeProject(to url: URL) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(ProjectFile(saved: ISO8601DateFormatter().string(from: Date()), song: song))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        projectURL = url; savedSong = song
        UserDefaults.standard.set(url.path, forKey: "project")
        status = "Saved \(projectName)"
    }
    func loadProject(_ url: URL) throws {
        guard let s = AppModel.readProject(url) else { throw Oops("\(url.lastPathComponent) is not a Crate project.") }
        if playing { stopAll() }
        song = s; open = nil; cue = 0; head = -1
        projectURL = url; savedSong = s
        UserDefaults.standard.set(url.path, forKey: "project")
    }
    /// Open a project from the window or the Finder. Undo goes back to the song that was open.
    func openProject(_ url: URL) {
        pushUndo()
        do { try loadProject(url); commit("Opened \(projectName)") } catch { if let s = undoStack_popForFailedCall() { song = s }; status = error.localizedDescription }
    }
    func saveProject() {
        guard let url = projectURL else { saveProjectAs(); return }
        do { try writeProject(to: url) } catch { status = "Could not save: \(error.localizedDescription)" }
    }
    func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [AppModel.projectType]; panel.canCreateDirectories = true
        panel.directoryURL = projectURL?.deletingLastPathComponent() ?? AppModel.projectsURL
        panel.nameFieldStringValue = projectName + ".crate"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try writeProject(to: url) } catch { status = "Could not save: \(error.localizedDescription)" }
    }
    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [AppModel.projectType]; panel.allowsMultipleSelection = false
        panel.directoryURL = projectURL?.deletingLastPathComponent() ?? AppModel.projectsURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url)
    }
    func newSong() {
        pushUndo()
        if playing { stopAll() }
        song = Song(); open = nil; cue = 0; head = -1
        setProject(nil)
        commit("New song. Undo brings the last one back.")
    }

    // MARK: - Mastering choices, shown as lines under Master

    /// Keep any knob changes made to the master with the choice that is in use.
    func stashMaster() { if let k = song.masterPick, let n = song.masters?.count, k < n { song.masters![k].fx = song.master } }
    func chooseMaster(_ k: Int) {
        guard let n = song.masters?.count, k < n, k != song.masterPick else { return }
        pushUndo(); stashMaster()
        song.masterPick = k; song.master = song.masters![k].fx
        commit("Master: \(song.masters![k].name)")
    }
    func dropMaster(_ k: Int) {
        guard let n = song.masters?.count, k < n, k != song.masterPick else { return }
        pushUndo(); stashMaster()
        let name = song.masters![k].name
        song.masters!.remove(at: k)
        if let p = song.masterPick, k < p { song.masterPick = p - 1 }
        if song.masters!.count < 2 { song.masters = nil; song.masterPick = nil }
        commit("Discarded \(name). Undo brings it back.")
    }

    // MARK: - Takes: versions of a part, shown as sub-tracks

    /// Put the notes that are playing back into their take, so nothing played or written since is lost.
    func stash(_ i: Int) { let t = song.tracks[i]; if t.take < t.takes.count { song.tracks[i].takes[t.take].notes = t.notes } }
    func chooseTake(_ id: String, _ k: Int) {
        guard let i = index(id), k < song.tracks[i].takes.count, k != song.tracks[i].take else { return }
        pushUndo(); stash(i)
        song.tracks[i].take = k
        song.tracks[i].notes = song.tracks[i].takes[k].notes
        commit("\(song.tracks[i].name): \(song.tracks[i].takes[k].name)")
    }
    func dropTake(_ id: String, _ k: Int) {
        guard let i = index(id), k < song.tracks[i].takes.count, k != song.tracks[i].take else { return }
        pushUndo(); stash(i)
        let name = song.tracks[i].takes[k].name
        song.tracks[i].takes.remove(at: k)
        if k < song.tracks[i].take { song.tracks[i].take -= 1 }
        if song.tracks[i].takes.count < 2 { song.tracks[i].takes = []; song.tracks[i].take = 0 }
        commit("Discarded \(name). Undo brings it back.")
    }

    // MARK: - Plugins

    func plugins(_ target: String) -> Plugins { target == "master" ? song.master : (index(target).map { song.tracks[$0].fx } ?? Plugins()) }
    func change(_ target: String, reload: Bool = false, _ edit: (inout Plugins) -> Void) {
        if target == "master" { edit(&song.master) } else if let i = index(target) { edit(&song.tracks[i].fx) } else { return }
        if reload { engine?.load(song, lib) } else { engine?.applyPlugins(song) }
        save()
    }
    func knob(_ target: String, _ k: Knob) -> Binding<Double> {
        Binding(get: {
            let v = self.plugins(target)[keyPath: k.path]
            return k.log ? log(v / k.range.lowerBound) / log(k.range.upperBound / k.range.lowerBound) : (v - k.range.lowerBound) / (k.range.upperBound - k.range.lowerBound)
        }, set: { x in
            var v = k.log ? k.range.lowerBound * pow(k.range.upperBound / k.range.lowerBound, x) : k.range.lowerBound + x * (k.range.upperBound - k.range.lowerBound)
            if k.unit == "st" { v = v.rounded() }
            self.change(target, reload: k.key == "tune") { $0[keyPath: k.path] = v }
        })
    }
    func text(_ target: String, _ path: WritableKeyPath<Plugins, String>) -> Binding<String> {
        Binding(get: { self.plugins(target)[keyPath: path] }, set: { v in self.pushUndo(); self.change(target) { $0[keyPath: path] = v } })
    }
    func volume(_ id: String) -> Binding<Double> {
        Binding(get: { self.index(id).map { self.song.tracks[$0].vol } ?? 0.8 }, set: { v in if let i = self.index(id) { self.song.tracks[i].vol = v; self.engine?.applyPlugins(self.song); self.save() } })
    }

    /// Roll the dice. Pitch, loudness and the Hold settings are left alone so the part still fits.
    func randomize(_ target: String) {
        let old = plugins(target), master = target == "master"
        let low = index(target).flatMap { lib.info(song.tracks[$0].sound) }.map { $0.folder == "Kicks" || $0.folder == "808s" } ?? false
        func r(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
        func on(_ p: Double) -> Bool { Double.random(in: 0...1) < p }
        var p = Plugins(); p.tune = old.tune; p.loudness = old.loudness; p.hold = old.hold; p.attack = old.attack; p.release = old.release
        if on(0.5) { p.eqLow = (r(-4, 4) * 2).rounded() / 2 }
        if on(0.4) { p.eqMid = (r(-4, 4) * 2).rounded() / 2; p.eqMidFreq = (r(300, 4000) / 50).rounded() * 50 }
        if on(0.5) { p.eqHigh = (r(-4, 4) * 2).rounded() / 2 }
        if on(0.5) { p.compThreshold = r(master ? -18 : -28, -8).rounded(); p.compRatio = (r(2, master ? 4 : 8) * 10).rounded() / 10; p.compAttack = r(1, 40).rounded(); p.compRelease = r(60, 300).rounded() }
        if !master {
            if on(0.45) { p.cutoff = (r(low ? 1500 : 1800, low ? 6000 : 12000) / 100).rounded() * 100 }
            if on(0.4) { p.drive = (r(0.05, 0.5) * 100).rounded() / 100 }
            if on(0.35) { p.lofi = (r(0.1, 0.5) * 100).rounded() / 100 }
            if on(0.3) { p.chorus = (r(0.3, 0.8) * 100).rounded() / 100; p.chorusRate = r(0.2, 1.5); p.chorusDepth = r(0.2, 0.8) }
            if !low {
                if on(0.2) { p.lowCut = (r(60, 400) / 10).rounded() * 10 }
                if on(0.2) { p.flanger = (r(0.3, 0.7) * 100).rounded() / 100; p.flangerRate = r(0.1, 1); p.flangerDepth = r(0.3, 0.9); p.flangerFeedback = r(0.2, 0.7) }
                if on(0.2) { p.phaser = (r(0.4, 0.9) * 100).rounded() / 100; p.phaserRate = r(0.1, 1.2); p.phaserDepth = r(0.4, 0.9); p.phaserFeedback = r(0.2, 0.6) }
                if on(0.3) { p.delay = (r(0.15, 0.5) * 100).rounded() / 100; p.delayTime = DELAY_TIMES.randomElement()!; p.delayFeedback = (r(0.2, 0.6) * 100).rounded() / 100 }
                if on(0.5) { p.reverb = (r(0.1, 0.5) * 100).rounded() / 100; p.reverbSpace = SPACES.randomElement()! }
            }
        }
        pushUndo()
        history[target, default: []].append(old)
        soundHistory[target, default: []].append(index(target).map { song.tracks[$0].sound } ?? "")
        backs[target] = history[target]?.count ?? 0
        change(target) { $0 = p }
        status = "\(master ? "Master" : index(target).map { song.tracks[$0].name } ?? ""): effects randomized. Back steps through them."
    }
    func back(_ target: String) {
        guard let old = history[target]?.popLast() else { return }
        let sound = soundHistory[target]?.popLast() ?? ""
        backs[target] = history[target]?.count ?? 0
        if let i = index(target), !sound.isEmpty, song.tracks[i].sound != sound, lib.info(sound) != nil { song.tracks[i].sound = sound }
        change(target, reload: true) { $0 = old }
    }
    /// The dice on a track's row: a different sound of the same kind, picked at random, with a fresh roll of the effects.
    /// The notes, the level and the Hold settings stay. Back (inside the track) or Undo brings the old sound and effects back.
    /// "Randomize effects" inside the track rolls the effects only.
    func rollTrack(_ target: String) {
        guard target != "master", let i = index(target), let now = lib.info(song.tracks[i].sound) else { randomize(target); return }
        var pool = lib.sounds.filter { visible($0) && $0.folder == now.folder && $0.id != now.id }       // the kit picked in the sounds list first
        if pool.isEmpty { pool = lib.sounds.filter { !hidden.contains($0.id) && $0.folder == now.folder && $0.id != now.id } }
        guard let pick = pool.randomElement() else { randomize(target); return }
        randomize(target)                                              // one Undo step and one Back step cover the sound and the effects together
        song.tracks[i].sound = pick.id
        commit("\(song.tracks[i].name) now plays \(pick.name) with new effects. Back or Undo returns to \(now.name).")
    }

    func export() {
        let dir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("Crate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd-HHmm"
        let base = projectURL == nil ? "crate-\(song.bars)bars-\(Int(song.bpm))bpm-\(song.key.replacingOccurrences(of: "#", with: "sharp"))" : projectName
        let url = dir.appendingPathComponent("\(base)-\(stamp.string(from: Date())).wav")
        let snapshot = song, lib = self.lib
        status = "Rendering…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Engine.export(snapshot, lib, to: url) }
            DispatchQueue.main.async {
                switch result {
                case .success: self.status = "Saved in Music/Crate"; NSWorkspace.shared.activateFileViewerSelecting([url])
                case .failure(let e): self.status = "Could not save: \(e.localizedDescription)"
                }
            }
        }
    }
}
