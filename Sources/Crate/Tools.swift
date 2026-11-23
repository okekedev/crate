import Foundation

// What Claude can do, over MCP. Each tool changes the same song the window shows.

private func P(_ type: String, _ description: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    var d: [String: Any] = ["type": type, "description": description]
    for (k, v) in extra { d[k] = v }
    return d
}
private func num(_ v: Any?) -> Double? { if let n = v as? NSNumber { return n.doubleValue }; if let s = v as? String { return Double(s) }; return nil }
private func flag(_ v: Any?) -> Bool? { (v as? NSNumber)?.boolValue }
private func str(_ v: Any?) -> String? { if let s = v as? String { return s }; if let n = v as? NSNumber { return n.stringValue }; return nil }
private let HITS: [Character: Double] = ["x": 0.8, "X": 1, "o": 0.45]

let RULES = """
You are the engineer inside Crate, a Mac app. It has a crate of finished sounds in six folders and a song made of tracks. Each track plays one sound through its own plugins, in this order: hold, tone, chorus, flanger, phaser, compressor, delay, reverb, and last EQ. The master has a compressor, EQ and a limiter over the whole song. Patterns are written by you from what they describe, played in by them on the typing keyboard, or edited by them note by note in a piano roll inside an open track. They change things by hand while you work, so read the session again before you build on a part. They listen and decide; you work the controls. You cannot hear, so never say how something sounds. Say what you did.

How it works
- The song can be 1 to 256 bars. A bar has 16 steps (sixteenth notes), numbered 1 to 16; the beats fall on 1, 5, 9 and 13.
- A track whose sound is in 808s or Synths is melodic: each note has a pitch such as E1 or F#4 (C4 is middle C). Other tracks just trigger their sound.
- write_pattern puts notes in. Rows are for drums, notes for melodic tracks; several notes on one step make a chord.
- copy_bars repeats a section. Use it to loop a part for more bars or to lay out a whole song (intro, verse, chorus) from sections.
- set_plugins shapes a track by name, or the whole song with the target "master".

Working rules
- Do what was asked with as few tool calls as you can, then reply in one or two short plain sentences. No lists, no markdown.
- Never clear or rewrite a track nobody asked about. Adding a part means a new track or new bars; everything already shaped stays as it is.
- A song can be kept as a project file (Name.crate in Music/Crate): save_project, open_project, list_projects. Save when the person asks or says they are done. Never open another project over unsaved work without telling them.
- Mastering comes as choices too: offer_masters with three clearly different directions (the settings in use stay as the first line), and choose_master when they pick one. Change the master in place only for a specific tweak they ask for.
- New parts and changes come as choices, not replacements. A new part: offer_variations with three clearly different versions. A change to a part that exists: offer_variations with two, and the one playing stays as the original. The person clicks the sub-tracks to compare. If they ask to go back, use choose_take.
- Stay in the key and scale of the song unless told otherwise. If they name a key or a length, set it with set_song first.
- A melody needs a track with a melodic sound. If none fits, add one with set_track using a sound from the crate.
- Melodies: chord tones on beats 1 and 3, mostly steps with a few leaps, leave rests, and make the last bar lead back to the first.
- Bass: turn mono on, give each note a len, sit it on or just after the kicks, and lean on the root, fifth and octave.
- Drums: kick and snare carry the bar, hats fill the eighths or sixteenths, rolls (2, 3 or 4) belong at the ends of bars.
- Building a full song: write the sections first (4, 8 or 16 bars each), then lay them out with copy_bars and thin or mute parts with clear_bars so sections differ.
- Hold shapes each note before anything else. hold 1 keeps a note at full level for its whole written length, even past the end of the sound, so a pluck or an 808 can be stretched; 0 lets it fade the way the sound does. It only works on notes that have a len. attack fades notes in (ms) and release is how long they take to fade after they end (ms).
- Lo-fi: lofi 0.25 to 0.5, cutoff 2000 to 6000, a little drive. Darker: lower cutoff. Punchier: compressor with attack 20 to 40. Wider or thicker: chorus. Movement: phaser or flanger. Space: reverb or delay.
- If a request is unclear, make the most likely change instead of asking. The person can press Undo.
"""

extension AppModel {
    func rpc(_ msg: [String: Any]) -> [String: Any]? {
        claudeSeen = true
        let id: Any = msg["id"] ?? NSNull()
        let params = msg["params"] as? [String: Any] ?? [:]
        func ok(_ result: Any) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        switch msg["method"] as? String ?? "" {
        case "initialize":
            return ok(["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18", "capabilities": ["tools": [String: Any]()], "serverInfo": ["name": "crate", "version": "1.0"], "instructions": RULES])
        case "ping": return ok([String: Any]())
        case "tools/list": return ok(["tools": toolList()])
        case "tools/call":
            do {
                let out = try call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
                return ok(["content": [["type": "text", "text": out]], "isError": false])
            } catch { return ok(["content": [["type": "text", "text": "Crate: \(error.localizedDescription)"]], "isError": true]) }
        default: return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]]
        }
    }

    private func toolList() -> [[String: Any]] {
        var plug: [String: Any] = [
            "target": P("string", "A track name or number, or \"master\" for the whole song. Leave out for the open track."),
            "reset": P("boolean", "Switch every plugin off first."),
            "delay_time": P("string", "One of \(DELAY_TIMES.joined(separator: ", ")) at the song's tempo."),
            "reverb_space": P("string", "One of \(SPACES.joined(separator: ", "))."),
        ]
        for k in ALL_KNOBS { plug[k.key] = P("number", "\(k.label), \(k.range.lowerBound) to \(k.range.upperBound) \(k.unit == "%" ? "(0 to 1)" : k.unit). At \(k.rest) it does nothing.") }
        var masterProps: [String: Any] = ["name": P("string", "One or two words, e.g. \"Warm\"."), "from_current": P("boolean", "Start from the master settings in use instead of from clean.")]
        for k in modules(master: true).flatMap({ $0.knobs }) { masterProps[k.key] = P("number", "\(k.label): \(k.range.lowerBound) to \(k.range.upperBound) \(k.unit).") }
        var colorProps: [String: Any] = ["randomize": P("boolean", "A whole new palette."), "reset": P("boolean", "Back to the original colours.")]
        for (key, _) in Palette.fields { colorProps[key] = P("string", "Hex colour for \(key.replacingOccurrences(of: "_", with: " ")).") }
        func tool(_ name: String, _ about: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
            ["name": name, "description": about, "inputSchema": ["type": "object", "properties": props, "required": required] as [String: Any]]
        }
        let trackRef = P("string", "Track name or number. Leave out for the open track.")
        let pattern: [String: [String: Any]] = [
            "bar": P("integer", "First bar the rows go to, from 1. Default 1."),
            "rows": P("array", "One string of 16 characters per bar: . rest, x hit, X accent, o ghost, 2 3 4 a roll of that many hits.", ["items": ["type": "string"]]),
            "notes": P("array", "Single notes.", ["items": ["type": "object", "properties": [
                "bar": P("integer", "Bar, from 1."), "step": P("number", "Step in the bar, 1 to 16. 1.5 is halfway to step 2."),
                "note": P("string", "Pitch such as E1, F#3 or Bb4. Melodic tracks only."), "len": P("number", "Length in steps. Leave out to let the sound ring."),
                "vel": P("number", "Loudness 0 to 1, default 0.8."), "off": P("boolean", "Remove what is on this step (only this pitch if a note is given)."),
            ] as [String: Any], "required": ["bar", "step"]] as [String: Any]]),
        ]
        return [
            tool("get_session", "Read the whole song: tempo, key, length, every track with its sound, plugins and pattern, the master, and every sound in the crate with its id. Call this first.", [:]),
            tool("set_song", "Settings for the whole song: tempo, key and scale, length in bars, and starting or stopping playback.", [
                "bpm": P("number", "50 to 220."), "key": P("string", "Key note such as E, F# or Bb."), "scale": P("string", "One of \(SCALE_NAMES.joined(separator: ", "))."),
                "bars": P("integer", "Length of the song, 1 to \(MAX_BARS)."), "transpose": P("integer", "Move every melodic note by this many semitones."),
                "play": P("boolean", "true starts playback from the top, false stops it."),
                "from_bar": P("integer", "With play true: the bar to start from instead of the top."),
            ]),
            tool("set_track", "Add or change one track: the sound it plays, its level, mute, and whether notes cut each other. A track name that does not exist yet makes a new track if you also give a sound. Changing the sound keeps the track's pattern and plugins.", [
                "track": trackRef, "sound": P("string", "A sound from the crate, by id or name."), "rename": P("string", "New name for the track."),
                "vol": P("number", "Level, 0 to 1.5."), "mute": P("boolean", "Silence the track."), "mono": P("boolean", "One note at a time: each new note cuts the last. Use for 808s and bass."),
                "remove": P("boolean", "Delete the track. Only when the person asks."),
            ]),
            tool("write_pattern", "Edit the version of a part that is playing, in place. Rows are for drums: each row replaces one whole bar. Notes are for melodic tracks and single hits: each is added to what is there. Writing past the end makes the song longer. For a new part, or a change the person will want to compare, use offer_variations instead.", [
                "track": trackRef, "bar": pattern["bar"]!, "rows": pattern["rows"]!, "notes": pattern["notes"]!,
                "clear": P("boolean", "Empty the track first. Only when the person wants the part replaced."),
            ]),
            tool("offer_variations", "Offer versions of a part for the person to choose between. Each one becomes a sub-track under the track; they click one to hear it in place, and the others stay. Give three for a new part, two when changing a part that exists (the current one is kept beside them as the original). Each variation is a whole part written with rows or notes.", [
                "track": trackRef,
                "current_name": P("string", "A short name for the version that is playing now, e.g. \"Walking\"."),
                "variations": P("array", "The versions to add.", ["items": ["type": "object", "properties": [
                    "name": P("string", "One or two words, e.g. \"Steady\" or \"Busy\"."), "from_current": P("boolean", "Start from the playing version instead of from empty."),
                    "bar": pattern["bar"]!, "rows": pattern["rows"]!, "notes": pattern["notes"]!,
                ] as [String: Any], "required": ["name"]] as [String: Any]]),
            ], required: ["variations"]),
            tool("choose_take", "Switch which version of a part plays. Use when the person asks to go back to one, or picks one by name.", [
                "track": trackRef, "take": P("string", "The version's name or number."),
            ], required: ["take"]),
            tool("copy_bars", "Repeat a section: copy some bars to another place, once or several times in a row, on every track or only the ones named. What was at the destination is replaced. The song grows to fit.", [
                "from_bar": P("integer", "First bar of the section to copy."), "bars": P("integer", "How many bars the section is. Default 1."),
                "to_bar": P("integer", "Where the first copy starts."), "times": P("integer", "How many copies, end to end. Default 1."),
                "tracks": P("array", "Track names to copy. Leave out for all tracks.", ["items": ["type": "string"]]),
            ], required: ["from_bar", "to_bar"]),
            tool("clear_bars", "Empty some bars, on every track or only the ones named. Use it to drop parts out of a section.", [
                "from_bar": P("integer", "First bar to empty."), "bars": P("integer", "How many bars. Default 1."),
                "tracks": P("array", "Track names. Leave out for all tracks.", ["items": ["type": "string"]]),
            ], required: ["from_bar"]),
            tool("set_plugins", "Set the plugins on a track or on the master: hold (how long notes are held, and how they come in and let go), tone, EQ, compressor, chorus, flanger, phaser, delay, reverb, and for the master the limiter. Only the fields you pass change.", plug),
            tool("save_project", "Save the song as a project file (Name.crate in Music/Crate) the person can reopen later. With no name it saves over the project that is open.", ["name": P("string", "Project name, when saving for the first time or as a copy."), "replace": P("boolean", "Overwrite another project of that name. Only when the person says so.")]),
            tool("open_project", "Open a saved project in place of the song that is open. Undo brings the previous song back. Save first if the person wants to keep changes.", ["name": P("string", "A project name from list_projects, or a full path to a .crate file.")], required: ["name"]),
            tool("list_projects", "List the saved projects and say which one is open.", [:]),
            tool("new_project", "Start a new, empty song in place of the one that is open. Undo brings the previous song back. Save the open one first if the person wants to keep changes.", [
                "name": P("string", "Save it straight away under this project name."), "key": P("string", "Key note such as F or C#."), "scale": P("string", "One of \(SCALE_NAMES.joined(separator: ", "))."),
                "bpm": P("number", "50 to 220. Default: the tempo of the song that was open."), "bars": P("integer", "Length to start with. Default 8.")]),
            tool("set_colors", "Change the colours of the window. Pass hex colours (#RRGGBB) for the parts to change, or randomize for a whole new readable palette, or reset for the original look.", colorProps),
            tool("offer_masters", "Offer mastering choices for the person to compare. Each becomes a line under Master; they click one to hear the song through it, and the settings in use stay as the first line. Give three clearly different directions. Each option sets the master EQ, compressor and limiter from a clean start.", [
                "current_name": P("string", "A short name for the master settings in use now. Default \"Current\"."),
                "options": P("array", "The choices.", ["items": ["type": "object", "properties": masterProps, "required": ["name"]] as [String: Any]]),
            ], required: ["options"]),
            tool("choose_master", "Switch which mastering choice is in use.", ["option": P("string", "Its name or number.")], required: ["option"]),
            tool("quantize", "Pull a track's notes onto the grid.", ["track": trackRef, "grid": P("string", "1/16 (default), 1/8 or 1/4.")]),
        ]
    }

    private func findTrack(_ ref: Any?) throws -> Int {
        guard let r = str(ref), !r.isEmpty else {
            guard let i = index(open) else { throw Oops("No track is open. Name the track. Tracks: \(trackNames).") }
            return i
        }
        let s = r.lowercased().trimmingCharacters(in: .whitespaces)
        if let i = song.tracks.firstIndex(where: { $0.id == r || $0.name.lowercased() == s }) { return i }
        if let n = Int(s), n >= 1, n <= song.tracks.count { return n - 1 }
        if let i = song.tracks.firstIndex(where: { $0.name.lowercased().contains(s) }) { return i }
        throw Oops("No track called \"\(r)\". Tracks: \(trackNames).")
    }
    private var trackNames: String { song.tracks.isEmpty ? "none yet" : song.tracks.enumerated().map { "\($0 + 1) \"\($1.name)\"" }.joined(separator: ", ") }
    private func pick(_ refs: Any?) throws -> [Int] {
        guard let list = refs as? [Any], !list.isEmpty else { return Array(song.tracks.indices) }
        return try list.map { try findTrack($0) }
    }
    private func grow(toBar b: Int) throws { if b > MAX_BARS { throw Oops("A song can be \(MAX_BARS) bars at most.") }; if b > song.bars { song.bars = b } }

    private func call(_ name: String, _ a: [String: Any]) throws -> String {
        if name == "get_session" { return sessionText() }
        if name == "list_projects" || name == "set_colors" { return try run(name, a) }
        pushUndo()
        do { let out = try run(name, a); commit(); return out }
        catch { if let s = undoStack_popForFailedCall() { song = s }; throw error }
    }

    private func run(_ name: String, _ a: [String: Any]) throws -> String {
        switch name {
        case "set_song":
            if let v = num(a["bpm"]) { song.bpm = min(220, max(50, v.rounded())) }
            if let k = str(a["key"]) { guard let pc = pitchClass(k) else { throw Oops("\"\(k)\" is not a key. Use a note name such as E or Bb.") }; song.key = KEYS[pc] }
            if let s = str(a["scale"])?.lowercased() { guard SCALES[s] != nil else { throw Oops("Unknown scale. Use one of: \(SCALE_NAMES.joined(separator: ", ")).") }; song.scale = s }
            if let b = num(a["bars"]) { song.bars = min(MAX_BARS, max(1, Int(b))) }
            if let t = num(a["transpose"]), t != 0 { for i in song.tracks.indices { for j in song.tracks[i].notes.indices { if let n = song.tracks[i].notes[j].n { song.tracks[i].notes[j].n = min(127, max(0, n + Int(t))) } } } }
            if let p = flag(a["play"]) { if p { cue = Double(min(song.bars - 1, max(0, Int(num(a["from_bar"]) ?? 1) - 1)) * 16); engine?.load(song, lib); engine?.stop(); engine?.play(fromStep: cue); playing = true } else { stopAll() } }
            return "\(song.bars) bars at \(Int(song.bpm)) bpm (\(Int(song.seconds)) seconds), \(song.key) \(song.scale), \(playing ? "playing" : "stopped")."

        case "set_track":
            var i: Int
            if let found = try? findTrack(a["track"]) { i = found }
            else {
                guard let s = str(a["sound"]) else { throw Oops("No track called \"\(str(a["track"]) ?? "")\". Tracks: \(trackNames). Give a sound to make a new one.") }
                guard let info = lib.find(s) else { throw Oops("No sound \"\(s)\" in the crate. Use an id from get_session.") }
                i = try addTrack(sound: info.id, name: str(a["rename"]) ?? str(a["track"]))
            }
            if flag(a["remove"]) == true { let n = song.tracks[i].name; song.tracks.remove(at: i); return "Removed \"\(n)\"." }
            if let s = str(a["sound"]), let info = lib.find(s), song.tracks[i].sound != info.id {
                song.tracks[i].sound = info.id
                if let home = homeNote(info) { for j in song.tracks[i].notes.indices where song.tracks[i].notes[j].n == nil { song.tracks[i].notes[j].n = home } }
            } else if let s = str(a["sound"]), lib.find(s) == nil { throw Oops("No sound \"\(s)\" in the crate. Use an id from get_session.") }
            if let r = str(a["rename"]) { song.tracks[i].name = String(r.prefix(24)) }
            if let v = num(a["vol"]) { song.tracks[i].vol = min(1.5, max(0, v)) }
            if let m = flag(a["mute"]) { song.tracks[i].mute = m }
            if let m = flag(a["mono"]) { song.tracks[i].mono = m }
            open = song.tracks[i].id
            return trackLine(i) + "\n   " + patternText(song.tracks[i])

        case "write_pattern":
            let i = try findTrack(a["track"])
            let melodic = isMelodic(song.tracks[i]), home = lib.info(song.tracks[i].sound).flatMap { homeNote($0) }
            if flag(a["clear"]) == true { song.tracks[i].notes = [] }
            var notes = song.tracks[i].notes
            try write(&notes, a, melodic: melodic, home: home)
            song.tracks[i].notes = notes
            open = song.tracks[i].id
            return "\"\(song.tracks[i].name)\"\n   " + patternText(song.tracks[i])

        case "offer_variations":
            let i = try findTrack(a["track"])
            let melodic = isMelodic(song.tracks[i]), home = lib.info(song.tracks[i].sound).flatMap { homeNote($0) }
            guard let list = a["variations"] as? [Any], !list.isEmpty else { throw Oops("Give at least one variation.") }
            let wasEmpty = song.tracks[i].notes.isEmpty
            if song.tracks[i].takes.isEmpty { if !wasEmpty { song.tracks[i].takes = [Take(id: UUID().uuidString, name: String((str(a["current_name"]) ?? "Original").prefix(20)), notes: song.tracks[i].notes)]; song.tracks[i].take = 0 } }
            else { stash(i); if let n = str(a["current_name"]) { song.tracks[i].takes[song.tracks[i].take].name = String(n.prefix(20)) } }
            guard song.tracks[i].takes.count + list.count <= 10 else { throw Oops("A track holds ten versions at most. Ask the person which to discard first.") }
            for (k, item) in list.enumerated() {
                guard let v = item as? [String: Any] else { continue }
                var notes: [Note] = flag(v["from_current"]) == true ? song.tracks[i].notes : []
                try write(&notes, v, melodic: melodic, home: home)
                song.tracks[i].takes.append(Take(id: UUID().uuidString, name: String((str(v["name"]) ?? "Version \(song.tracks[i].takes.count + 1)").prefix(20)), notes: notes))
                if wasEmpty && k == 0 { song.tracks[i].take = song.tracks[i].takes.count - 1; song.tracks[i].notes = notes }
            }
            if song.tracks[i].takes.count < 2 { song.tracks[i].takes = []; song.tracks[i].take = 0 }
            return "\"\(song.tracks[i].name)\" versions: " + takeList(i) + ". They show as sub-tracks; the person clicks one to hear it in place."

        case "choose_take":
            let i = try findTrack(a["track"])
            guard let ref = str(a["take"]) else { throw Oops("Say which version: its name or number.") }
            let takes = song.tracks[i].takes
            guard let k = Int(ref).flatMap({ $0 >= 1 && $0 <= takes.count ? $0 - 1 : nil }) ?? takes.firstIndex(where: { $0.name.lowercased() == ref.lowercased() }) ?? takes.firstIndex(where: { $0.name.lowercased().contains(ref.lowercased()) })
            else { throw Oops("\"\(song.tracks[i].name)\" has no version called \"\(ref)\". It has: \(takes.isEmpty ? "only one version" : takeList(i)).") }
            stash(i)
            song.tracks[i].take = k; song.tracks[i].notes = song.tracks[i].takes[k].notes
            return "\"\(song.tracks[i].name)\" now plays \(takes[k].name). Versions: " + takeList(i)

        case "copy_bars":
            let from = Int(num(a["from_bar"]) ?? 1) - 1, n = max(1, Int(num(a["bars"]) ?? 1)), to = Int(num(a["to_bar"]) ?? 1) - 1, times = max(1, Int(num(a["times"]) ?? 1))
            guard from >= 0, to >= 0 else { throw Oops("Bars count from 1.") }
            try grow(toBar: to + n * times)
            let which = try pick(a["tracks"])
            for i in which {
                let lo = Double(from * 16), hi = Double((from + n) * 16)
                let src = song.tracks[i].notes.filter { $0.s >= lo && $0.s < hi }
                for k in 0..<times {
                    let start = Double((to + k * n) * 16)
                    song.tracks[i].notes.removeAll { $0.s >= start && $0.s < start + Double(n * 16) }
                    song.tracks[i].notes.append(contentsOf: src.map { var c = $0; c.s = $0.s - lo + start; return c })
                }
                song.tracks[i].notes.sort { $0.s < $1.s }
            }
            return "Copied bars \(from + 1) to \(from + n) onto bars \(to + 1) to \(to + n * times) on \(which.count) track\(which.count == 1 ? "" : "s"). The song is \(song.bars) bars, \(Int(song.seconds)) seconds."

        case "clear_bars":
            let from = Int(num(a["from_bar"]) ?? 1) - 1, n = max(1, Int(num(a["bars"]) ?? 1))
            let which = try pick(a["tracks"])
            for i in which { song.tracks[i].notes.removeAll { $0.s >= Double(from * 16) && $0.s < Double((from + n) * 16) } }
            return "Emptied bars \(from + 1) to \(from + n) on \(which.map { song.tracks[$0].name }.joined(separator: ", "))."

        case "set_plugins":
            let t = str(a["target"])?.lowercased().trimmingCharacters(in: .whitespaces)
            let master = t.map { ["master", "mix", "the master", "the mix", "song", "the song"].contains($0) } ?? (open == "master")
            let i = master ? -1 : try findTrack(a["target"])
            var fx = master ? song.master : song.tracks[i].fx
            if flag(a["reset"]) == true { let keep = fx.loudness; fx = Plugins(); fx.loudness = keep }
            for k in ALL_KNOBS { if let v = num(a[k.key]) { fx[keyPath: k.path] = min(k.range.upperBound, max(k.range.lowerBound, v)) } }
            if let d = str(a["delay_time"]) { guard DELAY_STEPS[d] != nil else { throw Oops("delay_time must be one of \(DELAY_TIMES.joined(separator: ", ")).") }; fx.delayTime = d }
            if let s = str(a["reverb_space"]) { guard let match = SPACES.first(where: { $0.lowercased() == s.lowercased() }) else { throw Oops("reverb_space must be one of \(SPACES.joined(separator: ", ")).") }; fx.reverbSpace = match }
            if master { song.master = fx; open = "master" } else { song.tracks[i].fx = fx; open = song.tracks[i].id }
            return "\(master ? "Master" : song.tracks[i].name) plugins: \(chainText(fx, master: master).isEmpty ? "all off" : chainText(fx, master: master))."

        case "save_project":
            var url = projectURL
            if let n = str(a["name"])?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
                let clean = (n.lowercased().hasSuffix(".crate") ? String(n.dropLast(6)) : n).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                url = AppModel.projectsURL.appendingPathComponent(clean + ".crate")
            }
            guard let to = url else { throw Oops("This song has no project file yet. Give it a name.") }
            if to != projectURL, FileManager.default.fileExists(atPath: to.path), flag(a["replace"]) != true { throw Oops("There is already a project called \(to.deletingPathExtension().lastPathComponent). Pick another name, or pass replace true if the person wants it overwritten.") }
            try writeProject(to: to)
            return "Saved as \(to.path)."

        case "open_project":
            guard let n = str(a["name"]), !n.isEmpty else { throw Oops("Say which project. list_projects shows them.") }
            let url = n.hasPrefix("/") ? URL(fileURLWithPath: n) : AppModel.projectsURL.appendingPathComponent(n.lowercased().hasSuffix(".crate") ? n : n + ".crate")
            guard FileManager.default.fileExists(atPath: url.path) else { throw Oops("There is no project at \(url.path). Projects here: \(projectNames().joined(separator: ", ")).") }
            let hadChanges = unsaved && !song.tracks.isEmpty
            try loadProject(url)
            return "Opened \(projectName)\(hadChanges ? ". The song that was open had unsaved changes; Undo brings it back" : "").\n" + sessionText()

        case "new_project":
            let hadChanges = unsaved && !song.tracks.isEmpty
            var fresh = Song()
            fresh.bpm = num(a["bpm"]).map { min(220, max(50, $0.rounded())) } ?? song.bpm
            if let k = str(a["key"]) { guard let pc = pitchClass(k) else { throw Oops("\"\(k)\" is not a key. Use a note name such as F or C#.") }; fresh.key = KEYS[pc] }
            if let sc = str(a["scale"])?.lowercased() { guard SCALES[sc] != nil else { throw Oops("Unknown scale. Use one of: \(SCALE_NAMES.joined(separator: ", ")).") }; fresh.scale = sc }
            fresh.bars = min(MAX_BARS, max(1, Int(num(a["bars"]) ?? 8)))
            var to: URL? = nil
            if let n = str(a["name"])?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
                to = AppModel.projectsURL.appendingPathComponent(n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".crate")
                if FileManager.default.fileExists(atPath: to!.path) { throw Oops("There is already a project called \(n). Pick another name.") }
            }
            if playing { stopAll() }
            song = fresh; open = nil; cue = 0; head = -1
            setProject(nil)
            if let url = to { try writeProject(to: url) }
            return "New song\(to == nil ? "" : " saved as \(to!.path)"): \(fresh.bars) bars at \(Int(fresh.bpm)) bpm, \(fresh.key) \(fresh.scale)\(hadChanges ? ". The song that was open had unsaved changes; Undo brings it back" : "")."

        case "set_colors":
            var p = palette
            if flag(a["reset"]) == true { p = .standard }
            if flag(a["randomize"]) == true { p = Palette.random(seed: UInt64.random(in: 0...UInt64.max)) }
            for (key, path) in Palette.fields { if let v = str(a[key]) { guard let c = RGB(hex: v) else { throw Oops("\"\(v)\" is not a colour. Write colours like #1A1C1B.") }; p[keyPath: path] = c.hex } }
            if p != palette { let was = palette; palette = p; paletteBefore = was }
            let low = palette.lowestTextContrast
            return "Colours: " + Palette.fields.map { "\($0.0) \(palette[keyPath: $0.1])" }.joined(separator: ", ") + String(format: ". Lowest text contrast %.1f to 1", low) + (low < 4.5 ? ", which is hard to read; aim for 4.5 or more." : ".")

        case "list_projects":
            let names = projectNames()
            return (names.isEmpty ? "No projects saved yet in \(AppModel.projectsURL.path)." : "Projects in \(AppModel.projectsURL.path): " + names.joined(separator: ", ") + ".") + " Open now: \(projectName)\(unsaved ? (projectURL == nil ? " (never saved)" : " (unsaved changes)") : " (saved)")."

        case "offer_masters":
            guard let list = a["options"] as? [Any], !list.isEmpty else { throw Oops("Give at least one option.") }
            if song.masters == nil { song.masters = [MasterOption(id: UUID().uuidString, name: String((str(a["current_name"]) ?? "Current").prefix(20)), fx: song.master)]; song.masterPick = 0 }
            else { stashMaster(); if let n = str(a["current_name"]), let p = song.masterPick { song.masters![p].name = String(n.prefix(20)) } }
            guard song.masters!.count + list.count <= 8 else { throw Oops("The master holds eight choices at most. Ask the person which to discard first.") }
            for item in list {
                guard let v = item as? [String: Any] else { continue }
                var fx = flag(v["from_current"]) == true ? song.master : Plugins()
                for k in modules(master: true).flatMap({ $0.knobs }) { if let x = num(v[k.key]) { fx[keyPath: k.path] = min(k.range.upperBound, max(k.range.lowerBound, x)) } }
                song.masters!.append(MasterOption(id: UUID().uuidString, name: String((str(v["name"]) ?? "Option \(song.masters!.count + 1)").prefix(20)), fx: fx))
            }
            return "Master choices: " + masterList() + ". They show as lines under Master; the person clicks one to hear the song through it."

        case "choose_master":
            guard let list = song.masters else { throw Oops("There is only one master setting. Use offer_masters first.") }
            guard let ref = str(a["option"]) else { throw Oops("Say which choice: its name or number.") }
            guard let k = Int(ref).flatMap({ $0 >= 1 && $0 <= list.count ? $0 - 1 : nil }) ?? list.firstIndex(where: { $0.name.lowercased() == ref.lowercased() }) ?? list.firstIndex(where: { $0.name.lowercased().contains(ref.lowercased()) })
            else { throw Oops("There is no master choice called \"\(ref)\". There are: \(masterList()).") }
            stashMaster()
            song.masterPick = k; song.master = song.masters![k].fx
            return "The master now uses \(list[k].name). Choices: " + masterList()

        case "quantize":
            let i = try findTrack(a["track"])
            let grid: Double = ["1/8": 2, "1/4": 4][str(a["grid"]) ?? ""] ?? 1
            for j in song.tracks[i].notes.indices { var s = (song.tracks[i].notes[j].s / grid).rounded() * grid; if s >= song.steps { s = 0 }; song.tracks[i].notes[j].s = s }
            song.tracks[i].notes.sort { $0.s < $1.s }
            return "\"\(song.tracks[i].name)\" is on the grid.\n   " + patternText(song.tracks[i])

        default: throw Oops("Crate has no tool called \(name).")
        }
    }

    private func projectNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: AppModel.projectsURL.path)) ?? []).filter { $0.lowercased().hasSuffix(".crate") }.map { String($0.dropLast(6)) }.sorted()
    }

    private func masterList() -> String {
        (song.masters ?? []).enumerated().map { "\($0 + 1) \($1.name)\($0 == song.masterPick ? " (in use)" : "")" }.joined(separator: ", ")
    }

    private func takeList(_ i: Int) -> String {
        let t = song.tracks[i]
        return t.takes.enumerated().map { "\($0 + 1) \($1.name)\($0 == t.take ? " (playing)" : "")" }.joined(separator: ", ")
    }

    /// Rows and single notes, as write_pattern takes them, applied to a list of notes.
    private func write(_ notes: inout [Note], _ a: [String: Any], melodic: Bool, home: Int?) throws {
        let first = Int(num(a["bar"]) ?? 1) - 1
        for (r, row) in ((a["rows"] as? [Any]) ?? []).enumerated() {
            let b = first + r
            try grow(toBar: b + 1)
            let chars = Array((str(row) ?? "").filter { !$0.isWhitespace && $0 != "|" })
            notes.removeAll { Int($0.s / 16) == b }
            for j in 0..<min(16, chars.count) {
                let at = Double(b * 16 + j), c = chars[j]
                if let v = HITS[c] { notes.append(Note(s: at, n: melodic ? home : nil, l: nil, v: v)) }
                else if let k = c.wholeNumberValue, k >= 2, k <= 4 { for h in 0..<k { notes.append(Note(s: at + Double(h) / Double(k), n: melodic ? home : nil, l: nil, v: 0.6 + 0.25 * Double(h) / Double(k - 1))) } }
            }
        }
        for item in (a["notes"] as? [Any]) ?? [] {
            guard let n = item as? [String: Any] else { continue }
            let b = Int(num(n["bar"]) ?? Double(first + 1)) - 1
            try grow(toBar: b + 1)
            let at = (Double(b * 16) + min(16.99, max(1, num(n["step"]) ?? 1)) - 1)
            var pitch: Int? = nil
            if let name = str(n["note"]) { guard let p = parseNote(name) else { throw Oops("\"\(name)\" is not a note name. Write notes like E1, F#3 or Bb4.") }; pitch = p }
            notes.removeAll { abs($0.s - at) < 0.01 && (!melodic || pitch == nil || $0.n == pitch) }
            if flag(n["off"]) == true { continue }
            notes.append(Note(s: at, n: melodic ? (pitch ?? home) : nil, l: num(n["len"]).map { max(0.1, $0) }, v: min(1, max(0.05, num(n["vel"]) ?? 0.8))))
        }
        notes.sort { $0.s < $1.s }
    }

    private func trackLine(_ i: Int) -> String {
        let t = song.tracks[i], info = lib.info(t.sound), chain = chainText(t.fx, master: false)
        return "\(i + 1). \"\(t.name)\" plays \(info?.name ?? "nothing") [\(t.sound)]\(info?.melodic == true ? " (melodic)" : ""); level \(t.vol)\(t.mono ? ", one note at a time" : "")\(t.mute ? ", muted" : ""); plugins: \(chain.isEmpty ? "none" : chain)\(t.takes.count > 1 ? "; versions: " + takeList(i) : "")"
    }

    /// A track's pattern, bar by bar, with bars that are identical listed together.
    func patternText(_ t: Track) -> String {
        let melodic = isMelodic(t)
        var groups: [(sig: String, bars: [Int])] = []
        for b in 0..<song.bars {
            let ns = t.notes.filter { Int($0.s / 16) == b }
            if ns.isEmpty { continue }
            var sig = ""
            if melodic {
                sig = ns.map { n in "\(trim(n.s - Double(b * 16) + 1)) \(n.n.map { noteName($0, flats: flats) } ?? "?")\(n.l.map { " len \(trim($0))" } ?? "")\(n.v != 0.8 ? " vel \(trim(n.v))" : "")" }.joined(separator: "; ")
            } else {
                for i in 0..<16 { let here = ns.filter { Int($0.s) == b * 16 + i }; sig += here.isEmpty ? "." : here.count > 1 ? String(min(4, here.count)) : here[0].v >= 0.95 ? "X" : here[0].v <= 0.5 ? "o" : "x" }
            }
            if let g = groups.firstIndex(where: { $0.sig == sig }) { groups[g].bars.append(b + 1) } else { groups.append((sig, [b + 1])) }
        }
        if groups.isEmpty { return "no pattern yet" }
        return groups.map { "bars \(ranges($0.bars)): \($0.sig)" }.joined(separator: "\n   ")
    }
    private func trim(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
    private func ranges(_ bars: [Int]) -> String {
        var out: [String] = [], start = bars[0], prev = bars[0]
        for b in bars.dropFirst() + [Int.max] { if b != prev + 1 { out.append(start == prev ? "\(start)" : "\(start)-\(prev)"); start = b }; prev = b }
        return out.joined(separator: ",")
    }

    func sessionText() -> String {
        var L = ["[The session right now]"]
        let names = scaleClasses(key: song.key, scale: song.scale).map { noteName(60 + $0, flats: flats).dropLast() }.map(String.init).joined(separator: " ")
        L.append("Song: \(song.bars) bars at \(Int(song.bpm)) bpm (\(Int(song.seconds)) seconds), key \(song.key) \(song.scale) (\(names)), \(playing ? "playing" : "stopped").")
        L.append("Project: \(projectName)\(unsaved ? (projectURL == nil ? " (never saved)" : " (unsaved changes)") : " (saved)")")
        L.append("Tracks:")
        for i in song.tracks.indices { L.append(trackLine(i)); L.append("   " + patternText(song.tracks[i])) }
        if song.tracks.isEmpty { L.append("(none yet)") }
        let m = chainText(song.master, master: true)
        L.append("Master plugins: \(m.isEmpty ? "none" : m)" + (song.masters == nil ? "" : "; mastering choices: " + masterList()))
        L.append("Open in front of the person: \(open == "master" ? "the master" : index(open).map { "track \"\(song.tracks[$0].name)\"" } ?? "nothing")")
        L.append("Crate (id | name | kit | folder | root):")
        for s in lib.sounds where !hidden.contains(s.id) { L.append("\(s.id) | \(s.name) | \(s.kit) | \(s.folder)\(s.sub.isEmpty ? "" : "/" + s.sub)\(s.root.map { " | root " + noteName($0, flats: flats) } ?? "")") }
        return L.joined(separator: "\n")
    }
}
