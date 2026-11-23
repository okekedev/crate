import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

/// A dark hardware faceplate: charcoal case, amber display, four key colours.
/// The colours the window is drawn in. They come from the palette the person has set (see Colors.swift).
enum Theme {
    static var look = Look(Palette.standard)
    static var caseBG: Color { look.caseBG }
    static var plate: Color { look.plate }
    static var key: Color { look.key }
    static var keyInk: Color { look.keyInk }
    static var edge: Color { look.edge }
    static var ink: Color { look.ink }
    static var soft: Color { look.soft }
    static var line: Color { look.line }
    static var lcd: Color { look.lcd }
    static var lcdInk: Color { look.lcdInk }
    static var lcdDim: Color { look.lcdDim }
    static var accentInk: Color { look.accentInk }
    static var hues: [Color] { look.hues }
    static var padInk: [Color] { look.padInk }
    static var dark: Bool { look.dark }
    static let mono = Font.system(size: 14, design: .monospaced)
}

/// Whether Shift is held for the click being handled.
func shiftHeld() -> Bool { (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.shift) }

struct KeyStyle: ButtonStyle {
    var on = false
    var hot = false
    var pad: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold)).tracking(0.8).textCase(.uppercase).lineLimit(1)
            .padding(.horizontal, pad).frame(minHeight: 30)
            .background(hot && on ? Theme.hues[0] : on ? Theme.keyInk : Theme.key)
            .foregroundStyle(hot && on ? Theme.accentInk : on ? Theme.key : Theme.keyInk)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.edge, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A scrolling area in the window; laid out flat when the window is being drawn into a picture.
struct Scroller<Content: View>: View {
    @EnvironmentObject var m: AppModel
    @ViewBuilder var content: () -> Content
    var body: some View { if m.flat && !m.scrolls { content() } else { ScrollView { content() } } }
}

struct Tag: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.soft).lineLimit(1).fixedSize() }
}

extension AppModel {
    func setTempo(_ v: Double) { song.bpm = min(220, max(50, v.rounded())); commit() }
    func setBars(_ v: Int) { pushUndo(); song.bars = min(MAX_BARS, max(1, v)); commit() }
}

struct CrateApp: App {
    @StateObject private var model = AppModel()
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("Crate", id: "main") {
            ContentView().environmentObject(model).onAppear { NSApp.activate(ignoringOtherApps: true) }
                .onOpenURL { url in if url.pathExtension.lowercased() == "crate" { model.openProject(url) } }      // a project double-clicked in the Finder
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Song") { model.newSong() }.keyboardShortcut("n")
                Button("Open…") { model.openProjectPanel() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.saveProject() }.keyboardShortcut("s")
                Button("Save As…") { model.saveProjectAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        Window("Colors", id: "colors") { ColorsEditor().environmentObject(model) }
            .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    private let clock = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 12) {
            TopBar()
            HStack(alignment: .top, spacing: 12) {
                SoundsPanel().frame(width: 280)
                TracksPanel()
            }
        }
        .id(m.paletteStamp)                      // new colours redraw everything
        .padding(14)
        .frame(minWidth: 1000, minHeight: 640)
        .background(Theme.caseBG)
        .foregroundStyle(Theme.ink)
        .tint(Theme.hues[0])
        .preferredColorScheme(Theme.dark ? .dark : .light)
        .onReceive(clock) { _ in m.tick() }
    }
}

struct TopBar: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CRATE").font(.system(size: 28, weight: .heavy)).tracking(7).lineLimit(1).fixedSize()
                HStack(spacing: 6) {
                    Circle().fill(m.claudeSeen ? Theme.hues[0] : Theme.key).frame(width: 9, height: 9)
                    Tag(m.claudeSeen ? "Claude connected" : "Claude: port \(AppModel.port)")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text((m.projectName + (m.unsaved ? " •" : "")).uppercased()).lineLimit(1); Spacer()
                    Text("\(Int(m.song.bpm)) BPM"); Spacer()
                    Text("\(m.song.key) \(m.song.scale)".uppercased()); Spacer()
                    Text(m.head >= 0 ? "BAR \(min(m.song.bars, Int(m.head * Double(m.song.bars)) + 1))/\(m.song.bars)" : "\(m.song.bars) BARS")
                }.font(Theme.mono)
                Text(m.status.uppercased()).font(.system(size: 20, weight: .medium, design: .monospaced)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lcd).foregroundStyle(Theme.lcdInk)
            .clipShape(RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.edge, lineWidth: 2))
            Button(m.playing ? "Stop" : "Play") { m.togglePlay() }.buttonStyle(KeyStyle(on: m.playing, hot: true)).keyboardShortcut(.space, modifiers: [])
            Button(m.recording ? "Recording" : "Record") { m.toggleRecord() }.buttonStyle(KeyStyle(on: m.recording, hot: true))
            Button("Undo") { m.undo() }.buttonStyle(KeyStyle()).disabled(!m.canUndo).opacity(m.canUndo ? 1 : 0.45)
            Button("Open") { m.openProjectPanel() }.buttonStyle(KeyStyle()).help("Open a saved project")
            Button("Save") { m.saveProject() }.buttonStyle(KeyStyle()).help("Save this song as a project file")
            Button("Export") { m.export() }.buttonStyle(KeyStyle()).help("Write the song to a WAV file")
            Button { openWindow(id: "colors") } label: { Image(systemName: "paintpalette").font(.system(size: 14)) }.buttonStyle(KeyStyle()).help("Colors")
        }
        .padding(12).background(Theme.plate).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SoundsPanel: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Tag("Sounds"); Spacer()
                Picker("Kit", selection: $m.kit) { ForEach(m.kits, id: \.self) { Text($0 == "All" ? "All kits" : $0).tag($0) } }.labelsHidden().frame(width: 130)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(FOLDERS, id: \.self) { f in
                    Button { m.folder = f } label: { HStack(spacing: 2) { Text(f).lineLimit(1).fixedSize(); Spacer(minLength: 0); Text("\(m.count(f))").opacity(0.7).fixedSize() }.font(.system(size: 10.5, weight: .semibold)).tracking(0).frame(maxWidth: .infinity) }
                        .buttonStyle(KeyStyle(on: m.folder == f, pad: 6))
                }
            }
            Scroller {
                LazyVStack(spacing: 0) {
                    ForEach(m.shown) { s in SoundRow(sound: s) }
                    if m.shown.isEmpty { Text("Nothing in this folder for this kit.").font(Theme.mono).foregroundStyle(Theme.lcdDim).padding(10) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.lcd).clipShape(RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.edge, lineWidth: 2))
            Text("Click to hear. Drag onto a track to use it there.").font(.system(size: 11)).foregroundStyle(Theme.soft)
        }
        .padding(12).background(Theme.plate).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SoundRow: View {
    @EnvironmentObject var m: AppModel
    let sound: SoundInfo
    var body: some View {
        let on = m.picked == sound.id
        HStack(spacing: 6) {
            Text(sound.name).lineLimit(1)
            Spacer(minLength: 4)
        }
        .font(.system(size: 15, design: .monospaced))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(on ? Theme.lcdInk : Color.clear).foregroundStyle(on ? Theme.lcd : Theme.lcdInk)
        .contentShape(Rectangle())
        .onTapGesture { m.pick(sound.id) }
        .draggable(sound.id)
        .contextMenu { Button("Remove from the crate") { m.hide(sound.id) } }
    }
}

struct TracksPanel: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group { if m.selSection != nil { SectionBar() } else { SongRow() } }.frame(height: 32)
            Scroller {
                VStack(spacing: 6) {
                    RulerRow()
                    ForEach(m.song.tracks) { t in TrackRow(target: t.id) }
                    TrackRow(target: "master")
                    Text(m.song.tracks.isEmpty ? "No tracks yet. Drag a sound over here, then tell Claude what it should play." : "Drag a sound here for a new track.")
                        .font(.system(size: 12)).foregroundStyle(Theme.soft).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(12).background(Theme.plate).clipShape(RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            m.drop(sound: id, on: nil); return true
        }
    }
}

struct SongRow: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack(spacing: 14) {
            Tag("Tracks")
            HStack(spacing: 4) {
                Tag("Tempo")
                Button("−") { m.setTempo(m.song.bpm - 2) }.buttonStyle(KeyStyle())
                Text("\(Int(m.song.bpm))").font(.system(size: 17, design: .monospaced)).frame(width: 44).padding(.vertical, 4).background(Theme.lcd).foregroundStyle(Theme.lcdInk).clipShape(RoundedRectangle(cornerRadius: 4))
                Button("+") { m.setTempo(m.song.bpm + 2) }.buttonStyle(KeyStyle())
            }
            HStack(spacing: 4) {
                Tag("Key")
                Picker("Key", selection: Binding(get: { m.song.key }, set: { m.song.key = $0; m.commit() })) { ForEach(KEYS, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 64)
            }
            HStack(spacing: 4) {
                Tag("Scale")
                Picker("Scale", selection: Binding(get: { m.song.scale }, set: { m.song.scale = $0; m.commit() })) { ForEach(SCALE_NAMES, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 160)
            }
            HStack(spacing: 4) {
                Tag("Bars")
                Button("−") { m.setBars(m.song.bars > 8 ? m.song.bars - 4 : m.song.bars - 1) }.buttonStyle(KeyStyle())
                Text("\(m.song.bars)").font(.system(size: 17, design: .monospaced)).frame(width: 44).padding(.vertical, 4).background(Theme.lcd).foregroundStyle(Theme.lcdInk).clipShape(RoundedRectangle(cornerRadius: 4))
                Button("+") { m.setBars(m.song.bars >= 8 ? m.song.bars + 4 : m.song.bars + 1) }.buttonStyle(KeyStyle())
                Text(String(format: "%d:%02d", Int(m.song.seconds) / 60, Int(m.song.seconds) % 60)).font(Theme.mono).foregroundStyle(Theme.soft)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Shows in place of the tempo and key row while a section is picked (Shift-click or right-click): play from it, copy it, paste, duplicate or delete, one click each.
struct SectionBar: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        if let k = m.selSection {
            let n = m.selCount, per = m.sectionBars, first = k * per + 1, last = min(m.song.bars, (k + n) * per)
            HStack(spacing: 8) {
                Text((m.sectionLabel(k, n) + (per > 1 || n > 1 ? ": bars \(first) to \(last)" : "")).uppercased()).font(.system(size: 12, weight: .bold)).tracking(1).lineLimit(1).fixedSize()
                Button("Play") { m.seek(bar: first - 1); if !m.playing { m.togglePlay() } }.buttonStyle(KeyStyle()).help("Play from here")
                Button("Copy") { m.copySection(k, count: n) }.buttonStyle(KeyStyle()).help("Copy (Cmd-C)")
                Button("Cut") { m.cutSection(k, count: n) }.buttonStyle(KeyStyle()).help("Copy it and empty it; the bars stay (Cmd-X)")
                Button("Paste") { m.pasteSection(k, insert: false) }.buttonStyle(KeyStyle()).disabled(m.clip == nil).opacity(m.clip == nil ? 0.45 : 1).help("Paste over this (Cmd-V)")
                Button("Insert") { m.pasteSection(k, insert: true) }.buttonStyle(KeyStyle()).disabled(m.clip == nil).opacity(m.clip == nil ? 0.45 : 1).help("Paste in front of this as new bars (Shift-Cmd-V)")
                Button("Duplicate") { m.duplicateSection(k, count: n) }.buttonStyle(KeyStyle()).help("Put a copy right after this (Cmd-D)")
                Button("Delete") { m.deleteSection(k, count: n) }.buttonStyle(KeyStyle()).disabled(m.song.bars <= n * per).opacity(m.song.bars <= n * per ? 0.45 : 1).help("Take these bars out of the song")
                Spacer(minLength: 0)
                Button("Done") { m.selSection = nil; m.selCount = 1 }.buttonStyle(KeyStyle()).help("Let go of the section and bring back tempo, key and bars (Esc)")
            }
        }
    }
}

/// The right-click menu on a lane. It works on whole sections. On the ruler it copies and pastes every track; on a track's
/// lane, or the lane of one of its versions, only that part. What was copied can go into the section clicked, or be looped
/// across every section of the song. A right-click inside a pick that covers several sections acts on all of them.
struct SectionItems: View {
    @ObservedObject var m: AppModel
    let k: Int
    var track: String? = nil
    var take: Int? = nil
    var body: some View {
        let inside = m.selSection.map { k >= $0 && k < $0 + m.selCount } ?? false
        let a = inside ? (m.selSection ?? k) : k, n = inside ? m.selCount : 1, per = m.sectionBars
        let first = a * per + 1, last = min(m.song.bars, (a + n) * per), span = last - first + 1
        let name = track.flatMap { m.index($0) }.map { m.song.tracks[$0].name }
        let word = per == 1 ? "bar" : "section", these = n > 1 ? "these \(word)s" : "this \(word)"
        let label = m.sectionLabel(a, n), title = label.prefix(1).uppercased() + label.dropFirst() + (per > 1 || n > 1 ? ", bars \(first) to \(last)" : "")
        let copied = m.clip?.bars ?? 0, whole = (m.song.bars / per) * per                  // whole: the bars covered by full sections, so a short last bar is left alone
        Button(name.map { "\($0): \(title.prefix(1).lowercased() + title.dropFirst())" } ?? title) {}.disabled(true)
        Button("Play from here") { m.seek(bar: first - 1); if !m.playing { m.togglePlay() } }
        Divider()
        Button("Copy \(these)") { m.copyBars(first - 1, count: span, track: track, take: take) }
        Button("Cut \(these)") { m.cutBars(first - 1, count: span, track: track, take: take) }
        Button("Paste in \(these)") { m.pasteBars(first - 1, fill: n > 1 ? span : nil, track: track, take: take) }.disabled(copied == 0)
        Button(n > 1 ? "Loop it across these \(word)s" : "Loop it across every \(word)") { m.pasteBars(n > 1 ? first - 1 : 0, fill: n > 1 ? span : max(whole, copied), track: track, take: take) }.disabled(copied == 0)
        if track == nil {
            Divider()
            Button("Paste before, as new bars") { m.pasteSection(a, insert: true) }.disabled(copied == 0)
            Button("Duplicate") { m.duplicateSection(a, count: n) }
            Divider()
            Button("Delete", role: .destructive) { m.deleteSection(a, count: n) }.disabled(m.song.bars <= n * per)
        }
    }
}

/// The song from start to end, numbered by section and lined up with the track lanes. Click or drag in it to move the play line.
struct RulerRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Button {} label: { Image(systemName: "pencil").font(.system(size: 14, weight: .semibold)).frame(width: 18) }.buttonStyle(KeyStyle()).hidden()
            Button {} label: { Image(systemName: "dice").font(.system(size: 14)).frame(width: 18) }.buttonStyle(KeyStyle()).hidden()
            Color.clear.frame(width: 132, height: 1)
            Lane(notes: nil, ruler: true, seek: true).frame(height: 22)
            Color.clear.frame(width: 34, height: 1)
        }
        .padding(.horizontal, 6)
    }
}

struct TrackRow: View {
    @EnvironmentObject var m: AppModel
    let target: String
    var body: some View {
        let master = target == "master", track = m.index(target).map { m.song.tracks[$0] }, isOpen = m.open == target
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { m.toggleOpen(target) } label: { Image(systemName: isOpen ? "chevron.up" : "pencil").font(.system(size: 14, weight: .semibold)).frame(width: 18) }
                    .buttonStyle(KeyStyle(on: isOpen)).help(isOpen ? "Close" : master ? "Edit the master: its plugins" : "Edit this track: notes, level and plugins")
                Button { m.rollTrack(target) } label: { Image(systemName: "dice").font(.system(size: 14)).frame(width: 18) }.buttonStyle(KeyStyle())
                    .help(master ? "Randomize the master's effects" : "A random sound of the same kind, with random effects. To roll only the effects, open the track and use Randomize effects.")
                Button { if master { m.togglePlay() } else { m.toggleOpen(target) } } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text((master ? "Master" : track?.name ?? "").uppercased()).font(.system(size: 14, weight: .bold)).tracking(1).lineLimit(1)
                        Text(master ? "The whole song" : track.map { m.soundName($0) } ?? "").font(.system(size: 11)).foregroundStyle(Theme.soft).lineLimit(1)
                    }.frame(width: 132, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(master ? "Play or stop" : isOpen ? "Close" : "Edit this track")
                Lane(notes: track?.notes, dim: track?.mute ?? false, seek: true, track: master ? nil : target).frame(height: 32)
                if master { Color.clear.frame(width: 34, height: 30) }
                else { Button("M") { m.toggleMute(target) }.buttonStyle(KeyStyle(on: track?.mute ?? false)).help("Mute") }
            }
            .padding(6)
            if let t = track, t.takes.count > 1 { TakeRows(track: t).padding(.horizontal, 6).padding(.bottom, 6) }
            if master, (m.song.masters?.count ?? 0) > 1 { MasterRows().padding(.horizontal, 6).padding(.bottom, 6) }
            if isOpen { Detail(target: target).padding(.horizontal, 10).padding(.bottom, 10) }
        }
        .background(Theme.key.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOpen ? Theme.soft : Theme.line, lineWidth: 1))
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            m.drop(sound: id, on: master ? nil : target); return true
        }
    }
}

/// What a track plays across the whole song, at a glance. Notes are edited in the piano roll inside an open track.
struct Lane: View {
    @EnvironmentObject var m: AppModel
    let notes: [Note]?
    var dim = false
    var ruler = false        // number the sections along the song instead of drawing notes
    var seek = false         // a click here shows the bars in the piano roll and a drag moves the play line
    var pick = false         // Shift-click and right-click work on sections here even though a plain click does something else
    var track: String? = nil // the track this lane belongs to, so a click can open it in the piano roll and its menu works on that track
    var take: Int? = nil     // which of the track's versions this lane shows, when it is not just the one playing
    var tag: String? = nil   // a name for the click test to find it by
    var body: some View {
        Canvas { g, size in
            let bars = m.song.bars, steps = m.song.steps
            let every = m.sectionBars
            for b in stride(from: every, to: bars, by: every) {
                g.fill(Path(CGRect(x: (Double(b) / Double(bars) * size.width).rounded(), y: 0, width: 1, height: size.height)), with: .color(Theme.lcdDim.opacity(0.55)))
            }
            if let k = m.selSection {                                   // the picked sections, bright on the ruler and faint down the lanes
                let x = Double(k * every) / Double(bars) * size.width, w = Double(min(m.selCount * every, bars - k * every)) / Double(bars) * size.width
                g.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(Theme.hues[0].opacity(ruler ? 0.45 : 0.14)))
            }
            if let all = notes {
                let pitched = all.compactMap { $0.n }, lo = pitched.min() ?? 0, hi = pitched.max() ?? 0
                let ink = Theme.lcdInk.opacity(dim ? 0.35 : 1)
                for n in all where n.s < steps {
                    let x = n.s / steps * size.width
                    if let p = n.n {
                        let y = hi > lo ? 3 + (1 - Double(p - lo) / Double(hi - lo)) * (size.height - 9) : size.height / 2 - 1
                        g.fill(Path(CGRect(x: x, y: y, width: max(2, (n.l ?? 1) / steps * size.width - 1), height: 3)), with: .color(ink))
                    } else {
                        let h = (size.height - 8) * (0.4 + 0.6 * n.v)
                        g.fill(Path(CGRect(x: x, y: size.height - 4 - h, width: max(2, 0.4 / steps * size.width), height: h)), with: .color(ink))
                    }
                }
            }
            if ruler {
                for (k, b) in stride(from: 0, to: bars, by: every).enumerated() {
                    let x = Double(b) / Double(bars) * size.width, w = Double(min(every, bars - b)) / Double(bars) * size.width
                    if w >= 14 { g.draw(Text("\(k + 1)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.lcdInk), at: CGPoint(x: x + 4, y: size.height / 2), anchor: .leading) }
                }
            }
            if m.head >= 0 {
                g.fill(Path(CGRect(x: m.head * size.width, y: 0, width: 2, height: size.height)), with: .color(Theme.hues[0]))
                if ruler { g.fill(Path(roundedRect: CGRect(x: m.head * size.width - 4, y: 0, width: 10, height: 6), cornerRadius: 2), with: .color(Theme.hues[0])) }
            }
        }
        .background(Theme.lcd).clipShape(RoundedRectangle(cornerRadius: 3)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.edge, lineWidth: 1))
        .overlay {
            if seek || pick {
                GeometryReader { geo in
                    let bars = m.song.bars, per = m.sectionBars, width = max(1, geo.size.width)
                    let name = tag ?? (ruler ? "ruler" : "lane:" + (track ?? "master"))
                    let barAt: (CGFloat) -> Int = { x in min(bars - 1, max(0, Int(Double(x / width) * Double(bars)))) }
                    // One clear cell per section, each with its own right-click menu, so the menu never depends on where things sit on the screen.
                    HStack(spacing: 0) {
                        ForEach(0..<m.sectionCount, id: \.self) { k in
                            Color.clear.contentShape(Rectangle()).frame(width: CGFloat(min(per, bars - k * per)) / CGFloat(bars) * width)
                                .contextMenu { SectionItems(m: m, k: k, track: track, take: take) }
                        }
                    }
                    .help(ruler ? "Click a section to see it in the piano roll. Shift-click or right-click to copy, paste or duplicate it. Drag to move the play line." : seek ? "Click to see these bars in the piano roll. Shift-click or right-click to copy or paste the section. Drag to move the play line." : "Click to play this version. Shift-click or right-click to copy or paste the section.")
                    .gesture(DragGesture(minimumDistance: 0).modifiers(.shift)                               // Shift-click: pick the section and bring up copy and paste
                        .onEnded { v in if abs(v.translation.width) < 4 { m.pickSection(barAt(v.location.x) / per) } })
                    .gesture(seek ? DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if m.dragBar < 0 && abs(v.translation.width) < 4 { return }                     // not a drag yet: wait and see whether it is a click
                            let bar = barAt(v.location.x)
                            if bar != m.dragBar { m.dragBar = bar; m.seek(bar: bar) }
                        }
                        .onEnded { v in
                            if m.dragBar < 0 {
                                let bar = barAt(v.location.x)
                                if shiftHeld() { m.pickSection(bar / per) }
                                else { m.seek(bar: ruler ? (bar / per) * per : bar); m.showInRoll(bar: bar, track: track) }
                            }
                            m.dragBar = -1
                        } : nil)
                    .onAppear { if m.probing || ruler { m.probe[name] = geo.frame(in: .global) } }          // the ruler's place gives a right-click its bar
                    .onChange(of: geo.frame(in: .global)) { _, f in if m.probing || ruler { m.probe[name] = f } }
                }
            }
        }
    }
}

/// The mastering choices, one line each. Click one to hear the song through it.
struct MasterRows: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array((m.song.masters ?? []).enumerated()), id: \.element.id) { k, opt in
                let on = k == m.song.masterPick
                HStack(spacing: 8) {
                    Color.clear.frame(width: 84, height: 1)
                    Button { m.chooseMaster(k) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(on ? Theme.hues[0] : Theme.edge).frame(width: 9, height: 9)
                            Text(opt.name.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1).lineLimit(1)
                            Spacer(minLength: 0)
                        }.frame(width: 132, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(on ? "The song is playing through this" : "Hear the song through this instead")
                    Button { m.chooseMaster(k) } label: {
                        Text(chainText(on ? m.song.master : opt.fx, master: true)).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).frame(height: 20)
                            .background(Theme.lcd).foregroundStyle(on ? Theme.lcdInk : Theme.lcdDim).clipShape(RoundedRectangle(cornerRadius: 3)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button("x") { m.dropMaster(k) }.buttonStyle(.plain).frame(width: 34).opacity(on ? 0 : 0.6).disabled(on).help("Discard this choice")
                }
                .foregroundStyle(on ? Theme.ink : Theme.soft)
            }
        }
    }
}

/// The versions of a part, one line each. Click one to make it the one that plays; the song keeps going.
struct TakeRows: View {
    @EnvironmentObject var m: AppModel
    let track: Track
    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(track.takes.enumerated()), id: \.element.id) { k, take in
                let on = k == track.take
                HStack(spacing: 8) {
                    Color.clear.frame(width: 84, height: 1)
                    Button { m.chooseTake(track.id, k) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(on ? Theme.hues[0] : Theme.edge).frame(width: 9, height: 9)
                            Text(take.name.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1).lineLimit(1)
                            Spacer(minLength: 0)
                        }.frame(width: 132, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(on ? "This version is playing" : "Play this version instead")
                    Lane(notes: on ? track.notes : take.notes, dim: !on, pick: true, track: track.id, take: k, tag: "take:\(track.id):\(k)").frame(height: 20).onTapGesture { m.chooseTake(track.id, k) }
                    Button("x") { m.dropTake(track.id, k) }.buttonStyle(.plain).frame(width: 34).opacity(on ? 0 : 0.6).disabled(on).help("Discard this version")
                }
                .foregroundStyle(on ? Theme.ink : Theme.soft)
            }
        }
    }
}

/// Inside an open track: its buttons, the level, the piano roll when it is switched on, and the plugins.
struct Detail: View {
    @EnvironmentObject var m: AppModel
    let target: String
    var body: some View {
        let master = target == "master", track = m.index(target).map { m.song.tracks[$0] }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Randomize effects") { m.randomize(target) }.buttonStyle(KeyStyle())
                Button("Back") { m.back(target) }.buttonStyle(KeyStyle()).disabled((m.backs[target] ?? 0) == 0).opacity((m.backs[target] ?? 0) == 0 ? 0.45 : 1)
                if track != nil {
                    Button("Piano roll") { m.roll.toggle() }.buttonStyle(KeyStyle(on: m.roll)).help(m.roll ? "Hide the piano roll" : "Edit this track's notes by hand")
                    Button(m.recording ? "Stop recording" : "Record") { m.toggleRecord() }.buttonStyle(KeyStyle(on: m.recording, hot: true)).help("Record what you play on the letter keys onto this track")
                    Button("Remove track") { m.removeTrack(target) }.buttonStyle(KeyStyle())
                }
                Spacer(minLength: 0)
            }
            if track != nil {
                HStack(spacing: 8) {
                    Tag("Level")
                    Slider(value: m.volume(target), in: 0...1.5, onEditingChanged: { began in if began { m.pushUndo() } }).frame(width: 170).tint(Theme.hues[1])
                    Text("\(Int(((track?.vol ?? 0) * 100).rounded()))%").font(Theme.mono).frame(width: 48, alignment: .leading)
                    Spacer(minLength: 0)
                }
            }
            if let t = track, m.roll { Roll(track: t) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(modules(master: master), id: \.id) { mod in ModuleBox(target: target, module: mod) }
            }
        }
    }
}

/// The open track's notes on a grid, up to eight bars at a time, for the version that is playing.
/// Click an empty square for a note; click a note to take it out; drag a note to move it; drag its right end to change how
/// long it lasts. Rows are the notes of the key, so nothing lands out of key. Drums get one row of hits.
struct Roll: View {
    @EnvironmentObject var m: AppModel
    let track: Track
    @State private var grab: Grab? = nil
    @State private var pressed: Int? = nil       // the note name being held down on the left, to light it up
    struct Grab { var note: Int; var length: Bool; var fresh: Bool; var from: CGPoint; var s0: Double; var l0: Double; var moved = false }

    var body: some View {
        let rows = m.rollRows(track), melodic = !rows.isEmpty
        let rowH: CGFloat = melodic ? (rows.count > 28 ? 10 : 13) : 46, height = melodic ? CGFloat(rows.count) * rowH : rowH
        let firstBar = m.rollFirstBar, barsShown = min(m.rollBars, m.song.bars - firstBar)
        let first = Double(firstBar * 16), span = Double(max(1, barsShown) * 16)
        let rootPC = pitchClass(m.song.key) ?? 0, letters = m.keyLetters(track)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Tag("Piano roll")
                if m.rollPages > 1 {
                    Button("◀") { m.rollPage = max(0, m.rollPage - 1) }.buttonStyle(KeyStyle(pad: 7)).disabled(firstBar == 0).opacity(firstBar == 0 ? 0.45 : 1)
                    Text("BARS \(firstBar + 1) TO \(firstBar + barsShown)").font(.system(size: 12, design: .monospaced)).frame(width: 118)
                    Button("▶") { m.rollPage = min(m.rollPages - 1, m.rollPage + 1) }.buttonStyle(KeyStyle(pad: 7)).disabled(firstBar + barsShown >= m.song.bars).opacity(firstBar + barsShown >= m.song.bars ? 0.45 : 1)
                }
                Spacer(minLength: 0)
                Text(melodic ? "Click to add or remove a note. Drag to move it, drag its end to stretch it. Note names and letter keys play." : "Click to add or remove a hit. Drag to move it. HIT and the letter keys play.").font(.system(size: 11)).foregroundStyle(Theme.soft).lineLimit(1)
            }
            HStack(alignment: .top, spacing: 4) {
                // The left edge is a keyboard: press a note name to hear it (and, with Record on, to put it on the grid).
                // The small letter is the key on the typing keyboard that plays the same note.
                VStack(spacing: 0) {
                    ForEach(melodic ? rows : [-1], id: \.self) { p in
                        HStack(spacing: 3) {
                            Text(melodic ? (letters[p] ?? "") : "").font(.system(size: rowH > 11 ? 8.5 : 7.5, weight: .bold, design: .monospaced)).foregroundStyle(Theme.hues[1]).frame(width: 9)
                            Text(melodic ? noteName(p, flats: m.flats) : "HIT").font(.system(size: melodic ? (rowH > 11 ? 9.5 : 8) : 11, weight: melodic ? .regular : .bold, design: .monospaced)).lineLimit(1)
                                .foregroundStyle(!melodic || p % 12 == rootPC ? Theme.ink : Theme.soft).frame(width: 32, alignment: .trailing)
                        }
                        .frame(width: 48, height: rowH, alignment: .trailing)
                        .background(pressed == p ? Theme.hues[0].opacity(0.55) : Theme.key.opacity(melodic ? 0.35 : 0.8))
                        .overlay(alignment: .bottom) { Theme.lcdDim.opacity(0.35).frame(height: 0.5) }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in if pressed != p { pressed = p; m.keyDown(melodic ? p : nil) } }
                            .onEnded { _ in pressed = nil; m.keyUp(melodic ? p : nil) })
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3)).help(melodic ? "Click a note to hear it" : "Click to hear the hit")
                GeometryReader { geo in
                    let cw = max(0.5, geo.size.width / span)
                    Canvas { g, size in
                        let rowOf = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1, $0) })
                        if melodic {
                            for (r, p) in rows.enumerated() {
                                if p % 12 == rootPC { g.fill(Path(CGRect(x: 0, y: Double(r) * rowH, width: size.width, height: rowH)), with: .color(Theme.lcdInk.opacity(0.10))) }
                                g.fill(Path(CGRect(x: 0, y: Double(r + 1) * rowH - 0.5, width: size.width, height: 0.5)), with: .color(Theme.lcdDim.opacity(0.35)))
                            }
                        }
                        for st in 0...Int(span) {
                            let bar = st % 16 == 0, beat = st % 4 == 0
                            if !beat && cw < 4 { continue }
                            g.fill(Path(CGRect(x: (Double(st) * cw).rounded(), y: 0, width: bar ? 1.5 : 1, height: size.height)), with: .color(Theme.lcdDim.opacity(bar ? 0.9 : beat ? 0.45 : 0.18)))
                            if bar && st < Int(span) { g.draw(Text("\(firstBar + st / 16 + 1)").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundColor(Theme.lcdDim), at: CGPoint(x: Double(st) * cw + 3, y: 6), anchor: .leading) }
                        }
                        for (k, n) in track.notes.enumerated() where n.s < first + span && n.s + (n.l ?? 1) > first {
                            let x = (n.s - first) * cw, held = grab?.note == k
                            let ink = held ? Theme.hues[0] : Theme.lcdInk.opacity(0.45 + 0.55 * n.v)
                            if melodic {
                                guard let p = n.n, let r = rowOf[p] else { continue }
                                let w = max(3, (n.l ?? 2) * cw - 1)
                                g.fill(Path(roundedRect: CGRect(x: x + 0.5, y: Double(r) * rowH + 1.5, width: w, height: rowH - 3), cornerRadius: 2), with: .color(ink))
                            } else {
                                let h = (size.height - 10) * (0.4 + 0.6 * n.v)
                                g.fill(Path(roundedRect: CGRect(x: x + 0.5, y: size.height - 4 - h, width: max(2, cw - 1.5), height: h), cornerRadius: 1.5), with: .color(ink))
                            }
                        }
                        if m.head >= 0 {
                            let at = m.head * m.song.steps
                            if at >= first && at < first + span { g.fill(Path(CGRect(x: (at - first) * cw, y: 0, width: 2, height: size.height)), with: .color(Theme.hues[0])) }
                        }
                    }
                    .background(Theme.lcd).clipShape(RoundedRectangle(cornerRadius: 3)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.edge, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onAppear { if m.probing { m.probe["roll"] = geo.frame(in: .global) } }
                    .onChange(of: geo.frame(in: .global)) { _, f in if m.probing { m.probe["roll"] = f } }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard let i = m.index(track.id) else { return }
                            let stepAt: (CGFloat) -> Double = { x in first + min(span - 1, max(0, (Double(x) / cw).rounded(.down))) }
                            let pitchAt: (CGFloat) -> Int? = { y in melodic ? rows[min(rows.count - 1, max(0, Int(y / rowH)))] : nil }
                            if grab == nil {                                   // the press: is there a note under the pointer?
                                let notes = m.song.tracks[i].notes, at = v.startLocation
                                var found: Int? = nil, onEnd = false
                                for (k, n) in notes.enumerated().reversed() {
                                    let x0 = (n.s - first) * cw, w = melodic ? max(3, (n.l ?? 2) * cw - 1) : max(2, cw - 1.5)
                                    guard at.x >= x0, at.x <= x0 + w else { continue }
                                    if melodic && n.n != pitchAt(at.y) { continue }
                                    found = k; onEnd = melodic && w >= 10 && at.x >= x0 + w - 5; break
                                }
                                m.pushUndo()
                                if let k = found { grab = Grab(note: k, length: onEnd, fresh: false, from: at, s0: notes[k].s, l0: notes[k].l ?? 2) }
                                else if let k = m.rollAdd(track.id, step: stepAt(at.x), pitch: pitchAt(at.y)) { grab = Grab(note: k, length: melodic, fresh: true, from: at, s0: stepAt(at.x), l0: m.rollLen) }
                                else { m.undo(); return }
                            }
                            guard var gr = grab else { return }
                            if abs(v.location.x - gr.from.x) > 3 || abs(v.location.y - gr.from.y) > 3 { gr.moved = true }
                            if gr.moved {
                                let across = (Double(v.location.x - gr.from.x) / cw).rounded()
                                if gr.length { m.rollChange(track.id, gr.note, len: gr.fresh ? max(1, stepAt(v.location.x) - gr.s0 + 1) : max(1, gr.l0 + across)) }
                                else { m.rollChange(track.id, gr.note, step: gr.s0 + across, pitch: pitchAt(v.location.y)) }
                            }
                            grab = gr
                        }
                        .onEnded { _ in
                            if let gr = grab {
                                if !gr.moved && !gr.fresh { m.rollRemove(track.id, gr.note) }       // a plain click on a note takes it out
                                m.rollDone(track.id)
                            }
                            grab = nil
                        })
                }
                .frame(height: height)
            }
        }
    }
}

struct ModuleBox: View {
    @EnvironmentObject var m: AppModel
    let target: String
    let module: Module
    var body: some View {
        let fx = m.plugins(target), on = !summary(module, fx).isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(on ? Theme.hues[0] : Theme.edge).frame(width: 9, height: 9)
                Text(module.name.uppercased()).font(.system(size: 13, weight: .bold)).tracking(1.2)
                Spacer()
            }
            ForEach(module.knobs, id: \.key) { k in KnobRow(target: target, knob: k) }
            if module.id == "delay" {
                Picker("Time", selection: m.text(target, \.delayTime)) { ForEach(DELAY_TIMES, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            }
            if module.id == "reverb" {
                Picker("Space", selection: m.text(target, \.reverbSpace)) { ForEach(SPACES, id: \.self) { Text($0).tag($0) } }.labelsHidden()
            }
        }
        .padding(10).background(Theme.plate).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct KnobRow: View {
    @EnvironmentObject var m: AppModel
    let target: String
    let knob: Knob
    var body: some View {
        HStack(spacing: 8) {
            Text(knob.label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Theme.soft).frame(width: 74, alignment: .leading)
            Slider(value: m.knob(target, knob), in: 0...1, onEditingChanged: { began in if began { m.pushUndo() } }).tint(Theme.hues[1])
            Text(knob.show(m.plugins(target)[keyPath: knob.path])).font(.system(size: 12, design: .monospaced)).frame(width: 72, alignment: .trailing)
        }
    }
}
