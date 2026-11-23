import AVFoundation

struct SoundInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kit: String
    let folder: String
    let sub: String
    let root: Int?           // the note a melodic sound was built at
    let melodic: Bool
    let pc: Int?             // the key a pitched drum was built in (0 is C); it moves with the song's key
    let file: String
    let seconds: Double?
}

/// The crate: a folder of WAV files and an index. Audio is read the first time a sound is needed.
final class Library {
    let dir: URL
    private(set) var sounds: [SoundInfo] = []
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var holds: [String: Sustain?] = [:]

    init() {
        dir = Library.find()
        if let data = try? Data(contentsOf: dir.appendingPathComponent("index.json")), let list = try? JSONDecoder().decode([SoundInfo].self, from: data) { sounds = list }
    }

    static func find() -> URL {
        let fm = FileManager.default
        var places: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CRATE_SOUNDS"] { places.append(URL(fileURLWithPath: env)) }
        if let res = Bundle.main.resourceURL { places.append(res.appendingPathComponent("Sounds")) }
        var up = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 { places.append(up.appendingPathComponent("Sounds")); up = up.deletingLastPathComponent() }
        return places.first { fm.fileExists(atPath: $0.appendingPathComponent("index.json").path) } ?? places.last ?? URL(fileURLWithPath: "Sounds")
    }

    func info(_ id: String) -> SoundInfo? { sounds.first { $0.id == id } }

    func find(_ ref: String) -> SoundInfo? {
        let s = ref.lowercased().trimmingCharacters(in: .whitespaces)
        return info(ref) ?? sounds.first { $0.name.lowercased() == s } ?? sounds.first { $0.name.lowercased().contains(s) }
    }

    /// What the Hold control needs for this sound. Worked out the first time and then kept for as long as the app runs,
    /// because notes that are sounding read straight from it. Nil for sounds too short to hold.
    func sustain(_ id: String) -> Sustain? {
        if let known = holds[id] { return known }
        let made = buffer(id).flatMap { Sustain($0) }
        holds[id] = .some(made)
        return made
    }

    /// Stereo, 32-bit float, at the file's own sample rate.
    func buffer(_ id: String) -> AVAudioPCMBuffer? {
        if let b = cache[id] { return b }
        guard let info = info(id), let file = try? AVAudioFile(forReading: dir.appendingPathComponent(info.file)) else { return nil }
        let src = file.processingFormat
        guard let raw = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(file.length)), (try? file.read(into: raw)) != nil,
              let fmt = AVAudioFormat(standardFormatWithSampleRate: src.sampleRate, channels: 2),
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: raw.frameLength + 2), let from = raw.floatChannelData, let to = out.floatChannelData else { return nil }
        let n = Int(raw.frameLength)
        for c in 0..<2 {
            let a = from[min(c, Int(src.channelCount) - 1)]
            for i in 0..<n { to[c][i] = a[i] }
            to[c][n] = 0; to[c][n + 1] = 0                       // two samples of silence so the reader never runs off the end
        }
        out.frameLength = AVAudioFrameCount(n)
        cache[id] = out
        return out
    }
}
