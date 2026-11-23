import SwiftUI
import AppKit

// Crate for Mac.
//   Crate                      opens the window
//   Crate --render out.wav     plays the opening song once into a file and quits (a check that the audio engine works)
//   Crate --headless           runs without a window, so Claude can still connect (for testing)
//   Crate --snapshot out.png   draws the window into a picture without showing it (add --open to open a track)
//   Crate --holdinfo           lists how each melodic sound is prepared for the Hold control
//   Crate --uitest             sends real clicks and drags into a hidden copy of the window and checks what they did
//   Crate --screenshot out.png a picture of the real window, drawn off the screen (--demo, --colors seed, --open N, --roll, --kit Name)

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
    let lib = Library()
    var song = AppModel.demo(lib)
    if args.contains("--saved") || args.contains("--song") {             // the song the app last saved, or a song file, instead of the opening one
        let url = args.firstIndex(of: "--song").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil } ?? AppModel.folderURL.appendingPathComponent("song.json")
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Song.self, from: data) else { print("failed: no song could be read at \(url.path)"); exit(1) }
        song = s
    }
    do { try Engine.export(song, lib, to: URL(fileURLWithPath: args[i + 1])); print("rendered \(song.bars) bars, \(song.tracks.count) tracks, \(lib.sounds.count) sounds in the crate") }
    catch { print("failed: \(error)"); exit(1) }
    exit(0)
}
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {      // draw the window into a picture, without showing it
    MainActor.assumeIsolated {
        let model = AppModel(quiet: true)
        if args.contains("--open"), !model.song.tracks.isEmpty {              // --open [--track N] [--roll] [--select N]
            let n = args.firstIndex(of: "--track").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 3
            model.open = model.song.tracks[min(model.song.tracks.count, max(1, n)) - 1].id
        }
        if args.contains("--roll") { model.roll = true }
        if let k = args.firstIndex(of: "--select"), k + 1 < args.count, let n = Int(args[k + 1]) { model.selectSection(n - 1); model.selectSection(n, extend: true) }
        if let k = args.firstIndex(of: "--colors"), k + 1 < args.count, let seed = UInt64(args[k + 1]) { model.palette = Palette.random(seed: seed); print(String(format: "lowest text contrast %.1f", model.palette.lowestTextContrast)) }
        let renderer = ImageRenderer(content: ContentView().environmentObject(model).frame(width: 1180, height: CGFloat(args.firstIndex(of: "--height").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 900), alignment: .top))
        renderer.scale = 1
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: args[i + 1])); print("snapshot written")
        } else { print("snapshot failed") }
    }
    exit(0)
}
if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {     // checks section copy, paste, duplicate and delete, and the piano roll's edits, on a project file; changes nothing on disk
    MainActor.assumeIsolated {
        let m = AppModel(quiet: true)
        guard let s = AppModel.readProject(URL(fileURLWithPath: args[i + 1])) else { print("failed: that project could not be read"); exit(1) }
        m.song = s
        let orig = m.song, per = m.sectionBars, tracks = 0..<orig.tracks.count
        func sec(_ song: Song, _ k: Int, _ t: Int) -> [String] {
            let a = Double(k * per * 16), b = a + Double(per * 16)
            return song.tracks[t].notes.filter { $0.s >= a && $0.s < b }.map { String(format: "%.4f|%d|%.3f", $0.s - a, $0.n ?? -1, $0.v) }.sorted()
        }
        func all(_ song: Song) -> [[String]] { song.tracks.map { $0.notes.map { String(format: "%.4f|%d|%.3f|%.3f", $0.s, $0.n ?? -1, $0.l ?? -1, $0.v) }.sorted() } }
        var ok = true
        func check(_ name: String, _ pass: Bool) { print(pass ? "ok   " : "FAIL ", name); if !pass { ok = false } }
        print("\(orig.bars) bars, sections of \(per) bars, \(orig.tracks.count) tracks")
        m.copySection(1)
        m.pasteSection(4, insert: true)
        check("paste before makes the song one section longer", m.song.bars == orig.bars + per)
        check("the new section holds the copy", tracks.allSatisfy { sec(m.song, 4, $0) == sec(orig, 1, $0) })
        check("the section after it moved along untouched", tracks.allSatisfy { sec(m.song, 5, $0) == sec(orig, 4, $0) })
        m.deleteSection(4)
        check("deleting that section gives the original song back", m.song.bars == orig.bars && all(m.song) == all(orig))
        m.pasteSection(2, insert: false)
        check("paste over replaces the section and keeps the length", m.song.bars == orig.bars && tracks.allSatisfy { sec(m.song, 2, $0) == sec(orig, 1, $0) })
        check("the sections either side are untouched", tracks.allSatisfy { sec(m.song, 1, $0) == sec(orig, 1, $0) && sec(m.song, 3, $0) == sec(orig, 3, $0) })
        m.undo()
        check("undo puts back what was there", all(m.song) == all(orig))
        m.deleteSection(0)
        check("delete shortens the song by one section", m.song.bars == orig.bars - per && tracks.allSatisfy { sec(m.song, 0, $0) == sec(orig, 1, $0) })
        m.undo()
        check("undo restores it", m.song.bars == orig.bars && all(m.song) == all(orig))
        if m.sectionCount >= 6 {
            m.copySection(1, count: 2)
            m.pasteSection(4, insert: false)
            check("two sections copied and pasted over two others", m.song.bars == orig.bars && tracks.allSatisfy { sec(m.song, 4, $0) == sec(orig, 1, $0) && sec(m.song, 5, $0) == sec(orig, 2, $0) && sec(m.song, 3, $0) == sec(orig, 3, $0) })
            m.undo()
            m.duplicateSection(2)
            check("duplicate puts a copy right after and moves the rest along", m.song.bars == orig.bars + per && tracks.allSatisfy { sec(m.song, 3, $0) == sec(orig, 2, $0) && sec(m.song, 2, $0) == sec(orig, 2, $0) && sec(m.song, 4, $0) == sec(orig, 3, $0) })
            m.undo()
            m.copySection(0)
            m.pasteSection(m.sectionCount, insert: true)
            check("insert past the last section adds the copy on the end", m.song.bars == orig.bars + per && all(m.song).indices.allSatisfy { all(m.song)[$0].count == all(orig)[$0].count + sec(orig, 0, $0).count })
            m.undo()
            check("after those, undo has the original song back", m.song.bars == orig.bars && all(m.song) == all(orig))
            m.selectSection(2); m.selectSection(4, extend: true)
            check("click then shift-click picks a run of sections", m.selSection == 2 && m.selCount == 3)
            m.selectSection(1); m.selectSection(1)
            check("clicking the picked section again lets go", m.selSection == nil)
        }
        // bars from the right-click menu: copy one bar, paste it into a bar, loop it across a section
        if orig.bars >= 4 * per && per > 1 {
            func bar(_ song: Song, _ t: Int, _ b: Int, take: Int? = nil) -> [String] {
                let src = take.map { song.tracks[t].takes[$0].notes } ?? song.tracks[t].notes, a = Double(b * 16)
                return src.filter { $0.s >= a && $0.s < a + 16 }.map { String(format: "%.4f|%d|%.3f", $0.s - a, $0.n ?? -1, $0.v) }.sorted()
            }
            let from = 3 * per                                         // a bar in the fourth section, where most tracks are playing
            m.copyBars(from); m.pasteBars(2)
            check("one bar copied from every track lands in the bar it is pasted into and nowhere else", tracks.allSatisfy { bar(m.song, $0, 2) == bar(orig, $0, from) && bar(m.song, $0, 1) == bar(orig, $0, 1) && bar(m.song, $0, 3) == bar(orig, $0, 3) } && m.song.bars == orig.bars)
            m.undo()
            m.copyBars(from); m.pasteBars(per, fill: per)
            check("looped across a section, every bar of that section is the copied bar and the sections either side are untouched", tracks.allSatisfy { t in (per..<2 * per).allSatisfy { bar(m.song, t, $0) == bar(orig, t, from) } && bar(m.song, t, per - 1) == bar(orig, t, per - 1) && bar(m.song, t, 2 * per) == bar(orig, t, 2 * per) })
            m.undo()
            if let ti = tracks.first(where: { !bar(orig, $0, from).isEmpty }) {
                let id = orig.tracks[ti].id
                m.copyBars(from, track: id); m.pasteBars(1, track: id)
                check("copied and pasted on one track's lane, only that track changes", bar(m.song, ti, 1) == bar(orig, ti, from) && tracks.allSatisfy { $0 == ti || all(m.song)[$0] == all(orig)[$0] })
                m.undo()
                m.copyBars(from, track: id); m.pasteBars(1)
                check("a copy of one track pasted on the ruler goes back to that track only", bar(m.song, ti, 1) == bar(orig, ti, from) && tracks.allSatisfy { $0 == ti || all(m.song)[$0] == all(orig)[$0] })
                m.undo()
                if let oi = tracks.first(where: { m.isMelodic(orig.tracks[$0]) != m.isMelodic(orig.tracks[ti]) }) {
                    m.copyBars(from, track: id); m.pasteBars(1, track: orig.tracks[oi].id)
                    let got = m.song.tracks[oi].notes.filter { $0.s >= 16 && $0.s < 32 }, melodic = m.isMelodic(orig.tracks[oi])
                    check("pasted onto a different kind of track, the hits keep their timing and get what that track needs to play", got.count == bar(orig, ti, from).count && got.allSatisfy { melodic ? ($0.n != nil && $0.l != nil) : ($0.n == nil && $0.l == nil) })
                    m.undo()
                }
                if orig.tracks[ti].takes.count > 1, let other = (0..<orig.tracks[ti].takes.count).first(where: { $0 != orig.tracks[ti].take }) {
                    m.copyBars(from, track: id); m.pasteBars(1, track: id, take: other)
                    check("pasted on the lane of a version that is not playing, that version changes and what plays does not", bar(m.song, ti, 1, take: other) == bar(orig, ti, from) && m.song.tracks[ti].notes == orig.tracks[ti].notes)
                    m.undo()
                }
            }
            if let ti = tracks.first(where: { !sec(orig, 3, $0).isEmpty }) {
                let id = orig.tracks[ti].id, full = orig.bars / per
                m.copyBars(3 * per, count: per, track: id); m.pasteBars(0, fill: full * per, track: id)
                check("a section looped across every section fills each full section of that track, and leaves a short last bar and the other tracks alone", (0..<full).allSatisfy { sec(m.song, $0, ti) == sec(orig, 3, ti) } && m.song.tracks[ti].notes.filter { $0.s >= Double(full * per * 16) } == orig.tracks[ti].notes.filter { $0.s >= Double(full * per * 16) } && tracks.allSatisfy { $0 == ti || all(m.song)[$0] == all(orig)[$0] })
                m.undo()
                m.copyBars(3 * per, count: per, track: id); m.pasteBars(1 * per, track: id)
                check("the same section pasted into one section changes that section only", sec(m.song, 1, ti) == sec(orig, 3, ti) && sec(m.song, 0, ti) == sec(orig, 0, ti) && sec(m.song, 2, ti) == sec(orig, 2, ti) && tracks.allSatisfy { $0 == ti || all(m.song)[$0] == all(orig)[$0] })
                m.undo()
            }
            if let ti = tracks.first(where: { !sec(orig, 3, $0).isEmpty }) {
                let id = orig.tracks[ti].id
                m.cutBars(3 * per, count: per, track: id)
                check("cut empties that section of that track, keeps the song the same length and leaves the other tracks alone", sec(m.song, 3, ti).isEmpty && m.song.bars == orig.bars && sec(m.song, 2, ti) == sec(orig, 2, ti) && sec(m.song, 4, ti) == sec(orig, 4, ti) && tracks.allSatisfy { $0 == ti || all(m.song)[$0] == all(orig)[$0] })
                m.pasteBars(1 * per, track: id)
                check("what was cut can be pasted into another section", sec(m.song, 1, ti) == sec(orig, 3, ti) && sec(m.song, 3, ti).isEmpty)
                m.undo(); m.undo()
                m.cutSection(3)
                check("cut on the ruler empties the section on every track", tracks.allSatisfy { sec(m.song, 3, $0).isEmpty && sec(m.song, 2, $0) == sec(orig, 2, $0) } && m.song.bars == orig.bars)
                m.undo()
            }
            check("after the bar edits, undo has the original song back", m.song.bars == orig.bars && all(m.song) == all(orig))
        }
        // the dice on a track's row: a new sound of the same kind plus new effects; Back and Undo return to the old ones
        for t in orig.tracks.prefix(3) where m.lib.info(t.sound) != nil {
            let was = m.lib.info(t.sound)
            m.rollTrack(t.id)
            let now = m.song.tracks.first { $0.id == t.id }!, got = m.lib.info(now.sound)
            check("the dice gives \(t.name) a different sound from the same folder and leaves its notes, level and hold alone", now.sound != t.sound && got?.folder == was?.folder && all(m.song) == all(orig) && now.vol == t.vol && now.fx.hold == t.fx.hold && now.fx.tune == t.fx.tune)
            m.back(t.id)
            let back = m.song.tracks.first { $0.id == t.id }!
            check("Back returns \(t.name) to its old sound and effects", back.sound == t.sound && back.fx == t.fx)
            m.undo()
        }
        check("after the dice, undo has the original song back", all(m.song) == all(orig) && m.song.tracks.map { $0.sound } == orig.tracks.map { $0.sound })
        // the typing keyboard as a music keyboard for the open track
        if let t = m.song.tracks.first(where: { m.isMelodic($0) }), let info = m.lib.info(t.sound), let home = m.homeNote(info) {
            m.open = t.id
            let inKey = Set(scaleClasses(key: m.song.key, scale: m.song.scale)), n = (SCALES[m.song.scale] ?? SCALES["minor"]!).count
            let every = "asdfghjkl;'qwertyuiop[]zxcvbnm,./"
            check("the letter keys play notes of the key: A is the track's home note, Q an octave above it, Z an octave below", m.keyNote("a")?.pitch == home && m.keyNote("q")?.pitch == home + 12 && m.keyNote("z")?.pitch == home - 12 && every.allSatisfy { ch in (m.keyNote(ch)?.pitch).map { inKey.contains($0 % 12) } ?? false })
            check("each key to the right is a higher note", zip("asdfghjkl;", "sdfghjkl;'").allSatisfy { (m.keyNote($0)?.pitch ?? 0) < (m.keyNote($1)?.pitch ?? 0) })
            check("other keys play nothing", m.keyNote("1") == nil && m.keyNote(" ") == nil && m.keyNote("-") == nil)
            let letters = m.keyLetters(t)
            check("the labels beside the roll show the letter for each note", letters[home] == "A" && letters[home + 12] == String(Array("asdfghjkl;'")[n]).uppercased() && letters[home - 12] == "Z")
            if let d = m.song.tracks.first(where: { !m.isMelodic($0) }) { m.open = d.id; check("on a drum track a letter key is a hit", m.keyNote("a") != nil && m.keyNote("a")?.pitch == nil) }
            m.open = nil
            check("with no track open the keys do nothing", m.keyNote("a") == nil)
        }
        // the piano roll, on the first melodic track and the first drum track
        if let t = m.song.tracks.first(where: { m.isMelodic($0) }) {
            let rows = m.rollRows(t), inKey = Set(scaleClasses(key: m.song.key, scale: m.song.scale)), used = Set(t.notes.compactMap { $0.n })
            check("the roll has a row for every note of the key in range, and for every note the track plays", rows.count >= 12 && rows == rows.sorted(by: >) && rows.allSatisfy { inKey.contains($0 % 12) || used.contains($0) } && used.isSubset(of: Set(rows)))
            let before = t.notes.count, pitch = rows[rows.count / 2]
            m.pushUndo()
            let k = m.rollAdd(t.id, step: 3, pitch: pitch) ?? -1
            m.rollChange(t.id, k, len: 5)
            m.rollChange(t.id, k, step: 6, pitch: rows[rows.count / 2 - 1])
            m.rollDone(t.id)
            let now = m.song.tracks.first { $0.id == t.id }!
            let made = now.notes.first { $0.s == 6 && $0.n == rows[rows.count / 2 - 1] && $0.l == 5 }
            check("a note added, lengthened and moved in the roll ends up where it was put", now.notes.count == before + 1 && made != nil && now.notes == now.notes.sorted { $0.s < $1.s })
            check("the edit is kept with the version that is playing", now.takes.isEmpty || now.takes[now.take].notes == now.notes)
            if let j = now.notes.firstIndex(where: { $0.s == 6 && $0.n == rows[rows.count / 2 - 1] && $0.l == 5 }) { m.rollRemove(t.id, j); m.rollDone(t.id) }
            check("removing it leaves the part as it was", all(m.song) == all(orig))
            m.undo()
        }
        if let t = m.song.tracks.first(where: { !m.isMelodic($0) }) {
            m.pushUndo()
            let k = m.rollAdd(t.id, step: 2, pitch: nil) ?? -1
            m.rollChange(t.id, k, step: 9)
            m.rollDone(t.id)
            let now = m.song.tracks.first { $0.id == t.id }!
            check("a drum hit added and moved has no pitch and no length", now.notes.count == t.notes.count + 1 && now.notes.contains { $0.s == 9 && $0.n == nil && $0.l == nil } && m.rollRows(t).isEmpty)
            m.undo()
            check("undo takes the hit back out", all(m.song) == all(orig))
        }
        print(ok ? "all passed" : "SOMETHING FAILED")
    }
    exit(0)
}
if let i = args.firstIndex(of: "--palettes"), i + 1 < args.count {     // the standard colours and the palettes for the given seeds, as JSON
    let list = [Palette.standard] + args[i + 1].split(separator: ",").compactMap { UInt64($0) }.map { Palette.random(seed: $0) }
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
    if let data = try? enc.encode(list), let text = String(data: data, encoding: .utf8) { print(text) }
    exit(0)
}
if let i = args.firstIndex(of: "--screenshot"), i + 1 < args.count {    // a picture of the real window, with its real sliders and menus, drawn off the screen
    MainActor.assumeIsolated {                                          // --demo (the opening song), --song File.crate, or the song last worked on; --colors seed; --open N; --roll; --kit Name; --size WxH
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited); app.finishLaunching()
        let model = AppModel(quiet: true); model.scrolls = true
        if args.contains("--demo") { model.song = AppModel.demo(model.lib); model.projectURL = nil }
        if let f = value("--song"), let s = AppModel.readProject(URL(fileURLWithPath: f)) { model.song = s; model.projectURL = URL(fileURLWithPath: f); model.markSaved() }      // a project file, shown under its own name
        if let seed = value("--colors").flatMap({ UInt64($0) }) { model.palette = Palette.random(seed: seed) }
        if let n = value("--open").flatMap({ Int($0) }), n >= 1, n <= model.song.tracks.count { model.open = model.song.tracks[n - 1].id }
        if args.contains("--roll") { model.roll = true }
        if let k = value("--kit") { model.kit = k }
        if let f = value("--folder") { model.folder = f }
        let size = (value("--size") ?? "1280x820").split(separator: "x").compactMap { Double($0) }, W = size.first ?? 1280, H = size.count > 1 ? size[1] : 820
        let win = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: W, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: ContentView().environmentObject(model))
        win.contentView = host; win.orderFrontRegardless()
        let end = Date().addingTimeInterval(1.2)
        while Date() < end { if let e = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) { app.sendEvent(e) } }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * 2), pixelsHigh: Int(H * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { print("failed: no picture could be made"); exit(1) }
        rep.size = NSSize(width: W, height: H)
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { print("failed: the picture could not be written"); exit(1) }
        try? png.write(to: URL(fileURLWithPath: args[i + 1])); print("screenshot written, \(Int(W * 2)) x \(Int(H * 2))")
    }
    exit(0)
}
final class TestWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }
if args.contains("--uitest") {                                         // sends real clicks and drags into a hidden copy of the window and checks what they did; changes nothing on disk
    MainActor.assumeIsolated {
        setvbuf(stdout, nil, _IONBF, 0)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited); app.finishLaunching()             // never comes to the front and never takes the keyboard
        let model = AppModel(quiet: true); model.probing = true
        if let i = args.firstIndex(of: "--song"), i + 1 < args.count, let s = AppModel.readProject(URL(fileURLWithPath: args[i + 1])) { model.song = s }
        guard let lead = model.song.tracks.first(where: { model.isMelodic($0) }) else { print("failed: the song has no melodic track"); exit(1) }
        model.open = lead.id; model.roll = true; model.rollPage = 0
        let H: CGFloat = 3800
        let win = TestWindow(contentRect: NSRect(x: -9000, y: -9000, width: 1180, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: ContentView().environmentObject(model))
        win.contentView = host
        win.title = "Crate"; model.installMonitors()
        win.orderFrontRegardless()                              // far off the screen, and never made the front window, so it does not take the keyboard from anything
        let direct = !args.contains("--queue")              // the app's own queue only passes clicks on when the app is in front, and this test never comes to the front
        var held: NSView? = nil
        func pump(_ seconds: Double) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { if let e = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) { app.sendEvent(e) } }
        }
        var number = 0
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint, shift: Bool = false) {      // p counts from the top left of the window, as the views do
            number += 1
            guard let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: H - p.y), modifierFlags: shift ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil, eventNumber: number, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { return }
            if direct {                                                             // straight to the view under the pointer, as the window would hand it on
                let target = host.hitTest(host.convert(e.locationInWindow, from: nil)) ?? host
                switch type { case .leftMouseDown: target.mouseDown(with: e); held = target; case .leftMouseDragged: (held ?? target).mouseDragged(with: e); default: (held ?? target).mouseUp(with: e); held = nil }
                pump(0.05)
            } else { app.postEvent(e, atStart: false); pump(0.05) }
        }
        func click(_ p: CGPoint, shift: Bool = false) { mouse(.leftMouseDown, p, shift: shift); mouse(.leftMouseUp, p, shift: shift); pump(0.08) }
        func drag(_ a: CGPoint, _ b: CGPoint) {
            mouse(.leftMouseDown, a)
            for i in 1...6 { let f = CGFloat(i) / 6; mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)) }
            mouse(.leftMouseUp, b); pump(0.08)
        }
        var ok = true
        func check(_ name: String, _ pass: Bool, _ got: String = "") { print(pass ? "ok   " : "FAIL ", name, pass ? "" : "| got: " + got); if !pass { ok = false } }
        pump(1.0)
        print("window key: \(win.isKeyWindow), visible: \(win.isVisible), app active: \(app.isActive), events sent \(direct ? "straight to the view" : "through the app's queue")")
        let other = model.song.tracks.first { $0.id != lead.id }
        guard model.probe["ruler"] != nil, model.probe["lane:" + lead.id] != nil, model.probe["roll"] != nil else { print("failed: could not find the ruler, a lane or the piano roll in the window: \(model.probe.keys.sorted())"); exit(1) }
        func R() -> CGRect { model.probe["ruler"]! }
        func L(_ id: String) -> CGRect { model.probe["lane:" + id]! }
        let orig = model.song, bars = CGFloat(model.song.bars), per = CGFloat(model.sectionBars), P = Int(per)
        func sel() -> String { "\(model.selSection.map { String($0) } ?? "none") x\(model.selCount)" }
        func inSection(_ k: Int, _ frame: CGRect) -> CGPoint { CGPoint(x: frame.minX + (CGFloat(k) + 0.5) * per / bars * frame.width, y: frame.midY) }
        print("\(model.song.bars) bars, sections of \(P); ruler at \(R().integral), piano roll at \(model.probe["roll"]!.integral)")
        if model.sectionCount >= 6 {
            let rulerWas = R()
            click(inSection(1, R()));               check("first, a plain click on the ruler moves the play line to that section", model.cue == Double(1 * P * 16) && model.selSection == nil, "cue \(model.cue), \(sel())")
            click(inSection(2, R()), shift: true);  check("Shift-click on the ruler picks that section", model.selSection == 2 && model.selCount == 1, sel())
            check("the ruler does not move when the copy and paste buttons come up", R() == rulerWas, "\(R()) was \(rulerWas)")
            click(inSection(4, R()), shift: true);  check("a second Shift-click stretches the pick to the section clicked", model.selSection == 2 && model.selCount == 3, sel())
            click(inSection(3, R()), shift: true);  check("Shift-click inside what is picked lets go", model.selSection == nil, sel())
            click(inSection(3, L(lead.id)), shift: true); check("Shift-click on a track's lane picks that section", model.selSection == 3 && model.selCount == 1, sel())
            click(inSection(5, L(lead.id)), shift: true); check("a second Shift-click on a lane stretches the pick", model.selSection == 3 && model.selCount == 3, sel())
            click(inSection(4, R()))
            check("a plain click on the ruler turns the piano roll to that section and moves the play line there, pick untouched", model.rollPage == (4 * P) / model.rollBars && model.cue == Double(4 * P * 16) && model.selSection == 3 && model.selCount == 3, "page \(model.rollPage), cue \(model.cue), \(sel())")
            drag(inSection(0, R()), inSection(2, R()))
            check("a drag along the ruler moves the play line and nothing else", model.cue == Double((2 * P + P / 2) * 16) && model.selSection == 3 && model.rollPage == (4 * P) / model.rollBars, "cue \(model.cue), \(sel()), page \(model.rollPage)")
            if let o = other {
                click(inSection(1, L(o.id)))
                check("a plain click in another track's lane opens that track in the piano roll at those bars", model.open == o.id && model.roll && model.rollPage == (1 * P) / model.rollBars, "open \(model.song.tracks.first { $0.id == model.open }?.name ?? "none"), page \(model.rollPage)")
            }
            // the smaller lanes under a track, one per version: a plain click plays that version, Shift-click still picks a section
            if let (ti, tr) = Array(model.song.tracks.enumerated()).first(where: { $0.element.takes.count > 1 }), let other = (0..<tr.takes.count).first(where: { $0 != tr.take }), let f = model.probe["take:\(tr.id):\(other)"] {
                model.selSection = nil; model.selCount = 1; pump(0.2)
                click(inSection(2, f), shift: true)
                check("Shift-click on a version's lane picks the section and does not switch version", model.selSection == 2 && model.song.tracks[ti].take == tr.take, "\(sel()), version \(model.song.tracks[ti].take)")
                click(inSection(2, f))
                check("a plain click on a version's lane still switches to that version", model.song.tracks[ti].take == other, "version \(model.song.tracks[ti].take)")
                model.undo(); pump(0.2)
            }
            model.selSection = nil; model.selCount = 1; model.open = lead.id; model.rollPage = 0; pump(0.4)
        }
        let Q = model.probe["roll"]!
        // the piano roll, first page
        let rows = model.rollRows(model.song.tracks.first { $0.id == lead.id }!), span = CGFloat(min(model.rollBars, model.song.bars) * 16)
        let cw = Q.width / span, rowH = Q.height / CGFloat(max(1, rows.count))
        func cell(_ step: CGFloat, _ row: Int, dx: CGFloat = 0.5) -> CGPoint { CGPoint(x: Q.minX + (step + dx) * cw, y: Q.minY + (CGFloat(row) + 0.5) * rowH) }
        func notes() -> [Note] { model.song.tracks.first { $0.id == lead.id }!.notes }
        // find a row with six free steps in a row on this page, and the two rows under it free there too
        var spot: (row: Int, step: Int)? = nil
        search: for r in 4..<max(4, rows.count - 6) { for st in stride(from: 2, to: Int(span) - 10, by: 1) {
            let busy = notes().contains { n in guard let p = n.n, [rows[r], rows[r + 1], rows[r + 2]].contains(p) else { return false }; return n.s < Double(st + 9) && n.s + (n.l ?? 2) > Double(st - 1) }
            if !busy { spot = (r, st); break search } } }
        if let sp = spot {
            let before = notes().count, st = CGFloat(sp.step)
            click(cell(st, sp.row))
            check("a click on an empty square adds a note there", notes().count == before + 1 && notes().contains { $0.s == Double(sp.step) && $0.n == rows[sp.row] }, "\(notes().count - before) more notes")
            check("the grid stays where it is after a note is added", model.rollRows(model.song.tracks.first { $0.id == lead.id }!) == rows && model.probe["roll"] == Q, "rows \(rows.count) -> \(model.rollRows(model.song.tracks.first { $0.id == lead.id }!).count)")
            click(cell(st, sp.row))
            check("a click on that note takes it out", notes().count == before && !notes().contains { $0.s == Double(sp.step) && $0.n == rows[sp.row] }, "\(notes().count - before) more notes")
            drag(cell(st, sp.row), cell(st + 3, sp.row))
            check("pressing on an empty square and dragging right draws a note four steps long", notes().contains { $0.s == Double(sp.step) && $0.n == rows[sp.row] && $0.l == 4 }, "\(notes().filter { $0.n == rows[sp.row] && $0.s >= Double(sp.step) - 1 && $0.s <= Double(sp.step) + 6 })")
            drag(cell(st, sp.row, dx: 0.4), cell(st + 2, sp.row + 2, dx: 0.4))
            check("dragging the note moves it two steps later and two rows down, same length", notes().contains { $0.s == Double(sp.step + 2) && $0.n == rows[sp.row + 2] && $0.l == 4 } && !notes().contains { $0.s == Double(sp.step) && $0.n == rows[sp.row] }, "\(notes().filter { $0.s >= Double(sp.step) - 1 && $0.s <= Double(sp.step) + 6 && [rows[sp.row], rows[sp.row + 1], rows[sp.row + 2]].contains($0.n ?? -1) })")
            let endX = Q.minX + (st + 2 + 4) * cw - 3
            drag(CGPoint(x: endX, y: Q.minY + (CGFloat(sp.row + 2) + 0.5) * rowH), CGPoint(x: endX + 2 * cw, y: Q.minY + (CGFloat(sp.row + 2) + 0.5) * rowH))
            check("dragging its right end makes it two steps longer", notes().contains { $0.s == Double(sp.step + 2) && $0.n == rows[sp.row + 2] && $0.l == 6 }, "\(notes().filter { $0.n == rows[sp.row + 2] && $0.s >= Double(sp.step) && $0.s <= Double(sp.step) + 6 })")
            click(cell(st + 3, sp.row + 2))
            check("one click takes it out again and the part is as it was", notes() == orig.tracks.first { $0.id == lead.id }!.notes, "\(notes().count - before) more notes")
            var undone = 0; while model.canUndo && undone < 40 { model.undo(); undone += 1 }
            check("Undo walks all of it back to the song as it was", model.song == orig, "\(undone) undos")
        } else { print("skipped the piano roll: no free spot on the first page") }
        // the keyboard: a note name on the left of the roll, then a real key press
        do {
            model.open = lead.id; model.roll = true; model.rollPage = 0; pump(0.4)
            let Q = model.probe["roll"]!, rows = model.rollRows(model.song.tracks.first { $0.id == lead.id }!), rowH = Q.height / CGFloat(max(1, rows.count)), before = model.played.count
            click(CGPoint(x: Q.minX - 28, y: Q.minY + 5.5 * rowH))
            check("a click on a note name beside the piano roll plays that note", model.played.count == before + 1 && model.played.last.flatMap { $0 } == rows[5], "\(model.played.suffix(3)), wanted \(rows[5])")
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1) { app.postEvent(e, atStart: false); pump(0.15) }
            }
            check("pressing the S key plays the second note of the key on the open track", model.played.count == before + 2 && model.played.last.flatMap { $0 } == model.keyNote("s")?.pitch, "\(model.played.suffix(3)), wanted \(String(describing: model.keyNote("s")?.pitch))")
            check("nothing was written to the track by just playing", model.song == orig)
        }
        // The right-click menu, last, because a menu holds the app until it closes. A real right mouse button event goes in through
        // the app's queue; when the menu starts, its lines are read, the result is printed and the test ends there. The window is
        // far off the screen, so nothing shows.
        if model.sectionCount >= 6, !args.contains("--no-menu") {
            let onRuler = args.contains("--menu-ruler"), k = onRuler ? 3 : 5, at = inSection(k, onRuler ? R() : L(lead.id))
            if args.contains("--where") { print("   ruler \(R().integral), lead lane \(L(lead.id).integral), right-click at \(at), open \(model.open ?? "none"), lead \(lead.id)"); for (k, v) in model.probe.sorted(by: { $0.value.minY < $1.value.minY }).prefix(6) { print("     \(k) \(v.integral)") } }
            _ = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
                let seen = (note.object as? NSMenu)?.items.map { $0.isSeparatorItem ? "-" : $0.title } ?? []
                let common = seen.first?.contains("ection \(k + 1)") == true && seen.contains("Copy this section") && seen.contains("Cut this section") && seen.contains("Paste in this section") && seen.contains("Loop it across every section") && !seen.contains("Copy this bar")
                check("a right mouse button click on \(onRuler ? "the ruler" : "a track's lane") opens the menu for section \(k + 1)", common && (onRuler ? seen.contains("Duplicate") && seen.contains("Delete") : seen.first?.hasPrefix(lead.name) == true && !seen.contains("Delete")), "\(seen)")
                print(ok ? "all passed" : "SOMETHING FAILED"); exit(ok ? 0 : 1)
            }
            if let e = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: at.x, y: H - at.y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil, eventNumber: 900, clickCount: 1, pressure: 1) { app.postEvent(e, atStart: false); pump(1.5) }
            check("a right mouse button click opens a menu", false, "no menu started within a second and a half")
        }
        print(ok ? "all passed" : "SOMETHING FAILED")
    }
    exit(0)
}
if args.contains("--holdinfo") {                                       // how each melodic sound is prepared for the Hold control
    let lib = Library()
    for s in lib.sounds where s.melodic {
        guard let buf = lib.buffer(s.id) else { continue }
        let sr = buf.format.sampleRate
        if let h = lib.sustain(s.id) { print(String(format: "%@ | %@ | loop starts %.2f s, goes round every %.2f s, ends match %.2f", s.id, s.name, (h.enter - Double(h.cycle)) / sr, Double(h.cycle) / sr, h.match)) }
        else { print("\(s.id) | \(s.name) | too short to hold") }
    }
    exit(0)
}
if args.contains("--headless") {
    let model = AppModel()
    print("Crate is running without a window. Claude connects at http://127.0.0.1:\(AppModel.port)/mcp (\(model.song.tracks.count) tracks loaded)")
    RunLoop.main.run()
} else {
    CrateApp.main()
}
