import AVFoundation
import AudioToolbox
import os

// The audio engine. Each track is: a sampler written here (it plays the notes, holds them, and runs drive, lo-fi, filters, chorus,
// flanger and phaser) feeding Apple's own audio units for compression, delay, reverb and, last, EQ. The master has
// a compressor, EQ and a peak limiter. Everything runs live, so a change is heard as it is made.

final class Transport {
    var playing = false
    var once = false              // play through one time, then nothing more (used for export)
    var start: Int64 = 0          // sample time at which the song began
    var loopLen: Int64 = 0        // length of the song in samples
    var now: Int64 = 0            // the engine's clock, written by the audio thread
    var flush = 0                 // goes up each time the play line jumps, so notes still sounding are let go
}

/// One immutable snapshot of what a track plays. The audio thread swaps to a new one between blocks.
final class Program {
    let buffer: AVAudioPCMBuffer?
    let left: UnsafePointer<Float>?
    let right: UnsafePointer<Float>?
    let frames: Int
    let starts: [Int64]           // when each note begins, in samples from the start of the song
    let rates: [Double]           // how fast the sample is read: pitch
    let gains: [Float]
    let lens: [Int]               // samples until the note is released; -1 lets it ring
    let mono: Bool
    let sustain: Sustain?         // for the Hold control; nil when the sound cannot be held

    init(buffer: AVAudioPCMBuffer?, starts: [Int64] = [], rates: [Double] = [], gains: [Float] = [], lens: [Int] = [], mono: Bool = false, sustain: Sustain? = nil) {
        self.buffer = buffer; self.sustain = sustain
        if let b = buffer, let ch = b.floatChannelData, b.frameLength > 0 {
            left = UnsafePointer(ch[0]); right = UnsafePointer(ch[b.format.channelCount > 1 ? 1 : 0]); frames = Int(b.frameLength)
        } else { left = nil; right = nil; frames = 0 }
        self.starts = starts; self.rates = rates; self.gains = gains; self.lens = lens; self.mono = mono
    }
}

struct Voice {
    var on = false
    var wait = 0                  // samples before it starts
    var pos = 0.0
    var rate = 1.0
    var gain: Float = 0
    var left = -1                 // samples until release
    var fade: Float = 1
    var fading = false
    var l: UnsafePointer<Float>? = nil
    var r: UnsafePointer<Float>? = nil
    var frames = 0
    var age = 0                   // samples since it began, for the attack
    var held = false              // this note is under the Hold control
    var looping = false           // it has run past the sound itself and is going round the prepared loop
    var q = 0.0                   // place in the loop
    var enter = 0.0, cycle = 0, table = 0
    var kl: UnsafePointer<Float>? = nil, kr: UnsafePointer<Float>? = nil, lift: UnsafePointer<Float>? = nil, shape: UnsafePointer<Float>? = nil
}

struct DSPParams {
    var vol: Float = 0.8
    var hold: Float = 0, attack: Float = 1, release: Float = 90
    var drive: Float = 0, lofi: Float = 0, cutoff: Float = 20000, lowCut: Float = 20
    var chorus: Float = 0, chorusRate: Float = 0.8, chorusDepth: Float = 0.5
    var flanger: Float = 0, flangerRate: Float = 0.3, flangerDepth: Float = 0.6, flangerFb: Float = 0.5
    var phaser: Float = 0, phaserRate: Float = 0.4, phaserDepth: Float = 0.7, phaserFb: Float = 0.4
}

/// The effects that are written here rather than borrowed from Apple. All stereo, all per sample.
struct FX {
    let sr: Float
    private let size = 8192
    private let chL: UnsafeMutablePointer<Float>, chR: UnsafeMutablePointer<Float>, flL: UnsafeMutablePointer<Float>, flR: UnsafeMutablePointer<Float>
    private let ap: UnsafeMutablePointer<Float>                   // twelve all-pass states: six per side
    private var w = 0
    private var lp1L: Float = 0, lp2L: Float = 0, lp1R: Float = 0, lp2R: Float = 0, hpL: Float = 0, hpR: Float = 0
    private var holdL: Float = 0, holdR: Float = 0, holdN = 0
    private var chPh: Float = 0, flPh: Float = 0, phPh: Float = 0
    private var phL: Float = 0, phR: Float = 0, aL: Float = 0, aR: Float = 0, tick = 0

    init(sampleRate: Float) {
        sr = sampleRate
        func line(_ n: Int) -> UnsafeMutablePointer<Float> { let p = UnsafeMutablePointer<Float>.allocate(capacity: n); p.initialize(repeating: 0, count: n); return p }
        chL = line(8192); chR = line(8192); flL = line(8192); flR = line(8192); ap = line(12)
    }

    @inline(__always) private func tap(_ buf: UnsafeMutablePointer<Float>, _ delay: Float) -> Float {
        var rp = Float(w) - delay
        if rp < 0 { rp += Float(size) }
        let i = Int(rp), f = rp - Float(i)
        let a = buf[i & (size - 1)], b = buf[(i + 1) & (size - 1)]
        return a + (b - a) * f
    }

    mutating func process(_ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>, _ n: Int, _ p: DSPParams) {
        let twoPi = Float.pi * 2
        let driveOn = p.drive > 0.001, k = 1 + p.drive * 9, norm = tanhf(k), trim = 1 - 0.35 * p.drive
        let lofiOn = p.lofi > 0.001, hold = 1 + Int(p.lofi * p.lofi * 23), q = powf(2, 15 - p.lofi * 11)
        let lpOn = p.cutoff < 19000, aLP = 1 - expf(-twoPi * min(p.cutoff, sr * 0.45) / sr)
        let hpOn = p.lowCut > 25, aHP = 1 - expf(-twoPi * p.lowCut / sr)
        let chOn = p.chorus > 0.001, chInc = twoPi * p.chorusRate / sr, chBase = 0.018 * sr, chDepth = (0.0015 + 0.0065 * p.chorusDepth) * sr
        let flOn = p.flanger > 0.001, flInc = twoPi * p.flangerRate / sr, flBase = 0.0012 * sr, flDepth = (0.0005 + 0.0045 * p.flangerDepth) * sr
        let phOn = p.phaser > 0.001, phInc = twoPi * p.phaserRate / sr
        for i in 0..<n {
            var l = L[i], r = R[i]
            if driveOn { l = tanhf(k * l) / norm * trim; r = tanhf(k * r) / norm * trim }
            if lofiOn {                                            // fewer samples and fewer bits, like an early sampler
                if holdN == 0 { holdL = (l * q).rounded() / q; holdR = (r * q).rounded() / q }
                holdN += 1; if holdN >= hold { holdN = 0 }
                l = holdL; r = holdR
            }
            if hpOn { hpL += aHP * (l - hpL); hpR += aHP * (r - hpR); l -= hpL; r -= hpR }
            if lpOn { lp1L += aLP * (l - lp1L); lp2L += aLP * (lp1L - lp2L); lp1R += aLP * (r - lp1R); lp2R += aLP * (lp1R - lp2R); l = lp2L; r = lp2R }
            if chOn {                                              // two slow, slightly different copies either side
                let wl = tap(chL, chBase + chDepth * sinf(chPh)), wr = tap(chR, chBase + chDepth * sinf(chPh + 1.5708))
                chL[w] = l; chR[w] = r
                l = l * (1 - 0.3 * p.chorus) + wl * p.chorus * 0.7; r = r * (1 - 0.3 * p.chorus) + wr * p.chorus * 0.7
                chPh += chInc; if chPh > twoPi { chPh -= twoPi }
            }
            if flOn {                                              // a very short moving echo fed back into itself
                let m = 0.5 + 0.5 * sinf(flPh), m2 = 0.5 + 0.5 * sinf(flPh + 1.0)
                let wl = tap(flL, flBase + flDepth * m), wr = tap(flR, flBase + flDepth * m2)
                flL[w] = l + wl * p.flangerFb; flR[w] = r + wr * p.flangerFb
                let mix = p.flanger * 0.7
                l = (l + wl * mix) / (1 + mix * 0.5); r = (r + wr * mix) / (1 + mix * 0.5)
                flPh += flInc; if flPh > twoPi { flPh -= twoPi }
            }
            if phOn {                                              // six all-pass stages sweeping up and down
                if tick == 0 {
                    let fl = 220 * powf(2, (0.5 + 0.5 * sinf(phPh)) * 4 * p.phaserDepth), fr = 220 * powf(2, (0.5 + 0.5 * sinf(phPh + 1.2)) * 4 * p.phaserDepth)
                    let tl = tanf(Float.pi * min(fl, sr * 0.45) / sr), tr = tanf(Float.pi * min(fr, sr * 0.45) / sr)
                    aL = (tl - 1) / (tl + 1); aR = (tr - 1) / (tr + 1)
                    phPh += phInc * 16; if phPh > twoPi { phPh -= twoPi }
                }
                tick = (tick + 1) & 15
                var xl = l + phL * p.phaserFb, xr = r + phR * p.phaserFb
                for s in 0..<6 {
                    let yl = aL * xl + ap[s]; ap[s] = xl - aL * yl; xl = yl
                    let yr = aR * xr + ap[6 + s]; ap[6 + s] = xr - aR * yr; xr = yr
                }
                phL = xl; phR = xr
                let mix = p.phaser * 0.5
                l = l * (1 - mix) + xl * mix; r = r * (1 - mix) + xr * mix
            }
            w = (w + 1) & (size - 1)
            L[i] = l * p.vol; R[i] = r * p.vol
        }
    }
}

/// The sampler for one track. `render` runs on the audio thread.
final class TrackDSP {
    var params = DSPParams()
    private let transport: Transport
    private let keepsClock: Bool
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var pending: Program?
    private var hasPending = false
    private var current: Program?
    private var last: Program?
    private var retired: [(Program, Date)] = []                  // old programs are kept alive while their notes may still ring
    private let voices: UnsafeMutablePointer<Voice>
    private let nVoices = 28
    private var nextVoice = 0
    private var flushSeen = 0
    private let liveRate: UnsafeMutablePointer<Double>, liveGain: UnsafeMutablePointer<Float>
    private var liveCount = 0
    private var fx: FX

    init(sampleRate: Double, transport: Transport, keepsClock: Bool = false) {
        self.transport = transport; self.keepsClock = keepsClock
        lock = .allocate(capacity: 1); lock.initialize(to: os_unfair_lock())
        voices = .allocate(capacity: 28); voices.initialize(repeating: Voice(), count: 28)
        liveRate = .allocate(capacity: 16); liveRate.initialize(repeating: 1, count: 16)
        liveGain = .allocate(capacity: 16); liveGain.initialize(repeating: 0, count: 16)
        fx = FX(sampleRate: Float(sampleRate))
    }

    /// Main thread: hand the sampler a new set of notes or a new sound.
    func set(_ p: Program) {
        os_unfair_lock_lock(lock); pending = p; hasPending = true; os_unfair_lock_unlock(lock)
        let now = Date()
        if let old = last { retired.append((old, now)) }
        last = p
        retired.removeAll { now.timeIntervalSince($0.1) > 30 }
    }

    /// Main thread: play the sound right now (a key press, or an audition).
    func hit(rate: Double, gain: Float) {
        os_unfair_lock_lock(lock)
        if liveCount < 16 { liveRate[liveCount] = rate; liveGain[liveCount] = gain; liveCount += 1 }
        os_unfair_lock_unlock(lock)
    }

    private func begin(_ p: Program, rate: Double, gain: Float, wait: Int, len: Int) {
        guard p.frames > 2 else { return }
        if p.mono { for i in 0..<nVoices where voices[i].on && !voices[i].fading && (voices[i].left < 0 || voices[i].left > wait) { voices[i].left = wait } }
        var slot = -1
        for i in 0..<nVoices where !voices[i].on { slot = i; break }
        if slot < 0 { slot = nextVoice; nextVoice = (nextVoice + 1) % nVoices }
        var vo = Voice(on: true, wait: wait, pos: 0, rate: rate, gain: gain, left: len < 0 ? -1 : len, fade: 1, fading: false, l: p.left, r: p.right, frames: p.frames)
        if len >= 0, params.hold > 0.001, let s = p.sustain {          // only notes with a length can be held: the length is how long
            vo.held = true; vo.enter = s.enter; vo.cycle = s.cycle; vo.table = s.table
            vo.kl = s.loopL; vo.kr = s.loopR; vo.lift = s.lift; vo.shape = s.shape
        }
        voices[slot] = vo
    }

    func render(sampleTime: Int64, frames: Int, _ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>) {
        if keepsClock { transport.now = sampleTime + Int64(frames) }
        if os_unfair_lock_trylock(lock) {
            if hasPending { current = pending; hasPending = false }
            if let p = current { for i in 0..<liveCount { begin(p, rate: liveRate[i], gain: liveGain[i], wait: 0, len: -1) } }
            liveCount = 0
            os_unfair_lock_unlock(lock)
        }
        for i in 0..<frames { outL[i] = 0; outR[i] = 0 }
        guard let prog = current else { return }
        if transport.flush != flushSeen { flushSeen = transport.flush; for i in 0..<nVoices where voices[i].on && !voices[i].fading { voices[i].left = 0 } }
        let loopLen = transport.loopLen
        if transport.playing && loopLen > 0 && sampleTime + Int64(frames) > transport.start {
            let n = prog.starts.count
            var done = 0
            var t = sampleTime
            if t < transport.start { done = Int(transport.start - t); t = transport.start }
            var pos = t - transport.start
            let finished = transport.once && pos >= loopLen
            if !finished && n > 0 {
                pos %= loopLen
                while done < frames {
                    let seg = Int(min(Int64(frames - done), loopLen - pos))
                    var lo = 0, hi = n
                    while lo < hi { let mid = (lo + hi) / 2; if prog.starts[mid] < pos { lo = mid + 1 } else { hi = mid } }
                    let end = pos + Int64(seg)
                    while lo < n && prog.starts[lo] < end {
                        begin(prog, rate: prog.rates[lo], gain: prog.gains[lo], wait: done + Int(prog.starts[lo] - pos), len: prog.lens[lo])
                        lo += 1
                    }
                    pos += Int64(seg); done += seg
                    if pos >= loopLen { if transport.once { break }; pos = 0 }
                }
            }
        }
        // The Hold controls. At rest they change nothing: a note fades the way it always has.
        let hold = min(1, max(0, params.hold))
        let fadeStep: Float = abs(params.release - 90) < 0.01 ? 0.9982 : expf(logf(0.0008) / max(1, params.release * 0.001 * fx.sr))
        let attackN = params.attack > 1.05 ? Int(params.attack * 0.001 * fx.sr) : 0
        let perHop = 1 / Double(Sustain.hop)
        for v in 0..<nVoices where voices[v].on {
            var vo = voices[v]
            guard let l = vo.l, let r = vo.r else { voices[v].on = false; continue }
            var i = vo.wait
            if i >= frames { vo.wait -= frames; voices[v] = vo; continue }
            vo.wait = 0
            while i < frames {
                let ip = Int(vo.pos)
                if !vo.held && ip >= vo.frames - 1 { vo.on = false; break }
                if vo.left == 0 { vo.fading = true }
                if vo.left > 0 { vo.left -= 1 }
                var g = vo.gain
                if vo.fading { vo.fade *= fadeStep; if vo.fade < 0.0008 { vo.on = false; break }; g *= vo.fade }
                if vo.age < attackN { g *= Float(vo.age) / Float(attackN) }
                vo.age += 1
                if vo.held, let kl = vo.kl, let kr = vo.kr, let lift = vo.lift, let shape = vo.shape {
                    // A held note is the sound with its own fade taken out, then given back by as much as Hold is turned down.
                    let tp = vo.pos * perHop, tk = Int(tp)
                    if hold < 0.999 {
                        var own: Float = 0                                  // the sound's own level here; nothing once it has run out
                        if tk < vo.table - 1 { own = shape[tk] + (shape[tk + 1] - shape[tk]) * Float(tp - Double(tk)) }
                        g *= hold + (1 - hold) * own
                    }
                    if vo.pos < vo.enter {
                        let f = Float(vo.pos - Double(ip))
                        g *= lift[tk] + (lift[tk + 1] - lift[tk]) * Float(tp - Double(tk))
                        outL[i] += (l[ip] + (l[ip + 1] - l[ip]) * f) * g
                        outR[i] += (r[ip] + (r[ip + 1] - r[ip]) * f) * g
                    } else {
                        if !vo.looping { vo.looping = true; vo.q = vo.pos - vo.enter }
                        let iq = Int(vo.q), f = Float(vo.q - Double(iq))
                        outL[i] += (kl[iq] + (kl[iq + 1] - kl[iq]) * f) * g
                        outR[i] += (kr[iq] + (kr[iq + 1] - kr[iq]) * f) * g
                        vo.q += vo.rate
                        if vo.q >= Double(vo.cycle) { vo.q -= Double(vo.cycle) }
                    }
                } else {
                    let f = Float(vo.pos - Double(ip))
                    outL[i] += (l[ip] + (l[ip + 1] - l[ip]) * f) * g
                    outR[i] += (r[ip] + (r[ip + 1] - r[ip]) * f) * g
                }
                vo.pos += vo.rate
                i += 1
            }
            voices[v] = vo
        }
        var state = fx
        state.process(outL, outR, frames, params)
        fx = state
    }
}

func appleEffect(_ subType: UInt32) -> AVAudioUnitEffect {
    AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: subType, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
}
func setParam(_ unit: AVAudioUnit, _ id: AudioUnitParameterID, _ value: Double) {
    AudioUnitSetParameter(unit.audioUnit, id, kAudioUnitScope_Global, 0, AudioUnitParameterValue(value), 0)
}
private let REVERBS: [String: AVAudioUnitReverbPreset] = [
    "Small Room": .smallRoom, "Medium Room": .mediumRoom, "Large Room": .largeRoom, "Medium Hall": .mediumHall, "Large Hall": .largeHall,
    "Plate": .plate, "Medium Chamber": .mediumChamber, "Large Chamber": .largeChamber, "Cathedral": .cathedral,
]

/// Apple's units for one track: compressor, delay, reverb, then EQ.
final class Rack {
    let eq = AVAudioUnitEQ(numberOfBands: 3)
    let comp = appleEffect(kAudioUnitSubType_DynamicsProcessor)
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()
    private var space = ""

    func apply(_ fx: Plugins, stepSeconds: Double) {
        let bands = eq.bands
        bands[0].filterType = .lowShelf; bands[0].frequency = 120; bands[0].gain = Float(fx.eqLow); bands[0].bypass = fx.eqLow == 0
        bands[1].filterType = .parametric; bands[1].frequency = Float(fx.eqMidFreq); bands[1].bandwidth = 1; bands[1].gain = Float(fx.eqMid); bands[1].bypass = fx.eqMid == 0
        bands[2].filterType = .highShelf; bands[2].frequency = 8000; bands[2].gain = Float(fx.eqHigh); bands[2].bypass = fx.eqHigh == 0
        // Dynamics processor: 0 threshold, 1 headroom, 4 attack, 5 release, 6 output gain. Headroom is how far above the
        // threshold the loudest input is allowed to end up, so threshold divided by ratio.
        comp.bypass = fx.compThreshold >= 0 && fx.compMakeup == 0
        setParam(comp, 0, fx.compThreshold < 0 ? fx.compThreshold : 0)
        setParam(comp, 1, min(40, max(0.1, fx.compThreshold < 0 ? -fx.compThreshold / max(1, fx.compRatio) : 40)))
        setParam(comp, 4, min(0.2, max(0.0001, fx.compAttack / 1000)))
        setParam(comp, 5, min(3, max(0.01, fx.compRelease / 1000)))
        setParam(comp, 6, fx.compMakeup)
        delay.bypass = fx.delay <= 0.001
        delay.delayTime = min(2, max(0.01, stepSeconds * (DELAY_STEPS[fx.delayTime] ?? 3)))
        delay.feedback = Float(fx.delayFeedback * 100); delay.lowPassCutoff = Float(fx.delayTone); delay.wetDryMix = Float(fx.delay * 50)
        reverb.bypass = fx.reverb <= 0.001
        if space != fx.reverbSpace { space = fx.reverbSpace; reverb.loadFactoryPreset(REVERBS[space] ?? .mediumHall) }
        reverb.wetDryMix = Float(fx.reverb * 60)
    }
}

final class Channel {
    let dsp: TrackDSP
    let source: AVAudioSourceNode
    let rack = Rack()

    init(format: AVAudioFormat, transport: Transport, keepsClock: Bool) {
        let d = TrackDSP(sampleRate: format.sampleRate, transport: transport, keepsClock: keepsClock)
        dsp = d
        source = AVAudioSourceNode(format: format) { _, stamp, frames, list -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(list)
            guard bufs.count >= 2, let l = bufs[0].mData?.assumingMemoryBound(to: Float.self), let r = bufs[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            d.render(sampleTime: Int64(stamp.pointee.mSampleTime), frames: Int(frames), l, r)
            return noErr
        }
    }
}

final class Engine {
    static let maxTracks = 12
    let av = AVAudioEngine()
    let offline: Bool
    let sampleRate: Double
    let format: AVAudioFormat
    let transport = Transport()
    private(set) var channels: [Channel] = []
    private let preview: Channel
    private let masterEQ = AVAudioUnitEQ(numberOfBands: 3)
    private let masterComp = appleEffect(kAudioUnitSubType_DynamicsProcessor)
    private let limiter = appleEffect(kAudioUnitSubType_PeakLimiter)
    private let ceiling = AVAudioMixerNode()                      // the last stage: nothing leaves hotter than about -1 dB true peak
    private(set) var stepSamples = 1.0

    init(offline: Bool = false) throws {
        self.offline = offline
        if offline {
            sampleRate = 44100
            format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            try av.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        } else {
            let hw = av.outputNode.outputFormat(forBus: 0).sampleRate
            sampleRate = hw > 8000 ? hw : 44100
            format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        }
        preview = Channel(format: format, transport: transport, keepsClock: false)
        for i in 0..<Engine.maxTracks { channels.append(Channel(format: format, transport: transport, keepsClock: i == 0)) }
        let mixer = av.mainMixerNode
        for c in channels {
            for node in [c.source, c.rack.eq, c.rack.comp, c.rack.delay, c.rack.reverb] as [AVAudioNode] { av.attach(node) }
            av.connect(c.source, to: c.rack.comp, format: format)           // EQ is last, so it shapes everything before it
            av.connect(c.rack.comp, to: c.rack.delay, format: format)
            av.connect(c.rack.delay, to: c.rack.reverb, format: format)
            av.connect(c.rack.reverb, to: c.rack.eq, format: format)
            av.connect(c.rack.eq, to: mixer, format: format)
            c.rack.apply(Plugins(), stepSeconds: 0.1)
        }
        av.attach(preview.source)
        av.connect(preview.source, to: mixer, format: format)
        for node in [masterEQ, masterComp, limiter, ceiling] as [AVAudioNode] { av.attach(node) }
        av.connect(mixer, to: masterComp, format: format)                 // on the master too: EQ after the compressor, then the limiter
        av.connect(masterComp, to: masterEQ, format: format)
        av.connect(masterEQ, to: limiter, format: format)
        av.connect(limiter, to: ceiling, format: format)
        av.connect(ceiling, to: av.outputNode, format: format)
        ceiling.outputVolume = 0.8                                 // -1.9 dB on the samples, which holds the true peak at about -1 dB
        av.prepare()
        try av.start()
    }

    /// Semitones a pitched drum moves when the song is not in the key the drum was built in (never more than six either way).
    static func keyShift(_ info: SoundInfo, _ key: String) -> Double {
        guard !info.melodic, let home = info.pc else { return 0 }
        let d = (((pitchClass(key) ?? 0) - home) % 12 + 12) % 12
        return Double(d > 6 ? d - 12 : d)
    }

    func rate(_ info: SoundInfo, _ buf: AVAudioPCMBuffer, pitch: Int?, song: Song, tune: Double) -> Double {
        var semis = Engine.keyShift(info, song.key) + tune
        if info.melodic, let root = info.root, let p = pitch { semis += Double(p - root) }
        return pow(2, semis / 12) * buf.format.sampleRate / sampleRate
    }

    /// Send the whole song to the audio thread. Cheap enough to call after every change.
    func load(_ song: Song, _ lib: Library) {
        let stepSeconds = 60 / song.bpm / 4
        stepSamples = stepSeconds * sampleRate
        transport.loopLen = Int64((song.steps * stepSamples).rounded())
        for (i, ch) in channels.enumerated() {
            guard i < song.tracks.count else { ch.dsp.set(Program(buffer: nil)); continue }
            let t = song.tracks[i]
            guard let info = lib.info(t.sound), let buf = lib.buffer(t.sound) else { ch.dsp.set(Program(buffer: nil)); continue }
            let notes = t.notes.filter { $0.s < song.steps && $0.s >= 0 }.sorted { $0.s < $1.s }
            var starts: [Int64] = [], rates: [Double] = [], gains: [Float] = [], lens: [Int] = []
            for (j, n) in notes.enumerated() {
                starts.append(Int64((n.s * stepSamples).rounded()))
                rates.append(rate(info, buf, pitch: n.n, song: song, tune: t.fx.tune))
                gains.append(Float(pow(min(1, max(0.05, n.v)), 1.5)))
                var len = n.l.map { Int($0 * stepSamples) } ?? -1
                if t.mono {
                    let next = notes[(j + 1)...].first { $0.s > n.s }
                    let cut = Int(((next?.s ?? notes[0].s + song.steps) - n.s) * stepSamples)
                    if len < 0 || cut < len { len = cut }
                }
                lens.append(len)
            }
            let sustain = lens.contains { $0 >= 0 } ? lib.sustain(t.sound) : nil      // ready before Hold is turned up, so the slider works live
            ch.dsp.set(Program(buffer: buf, starts: starts, rates: rates, gains: gains, lens: lens, mono: t.mono, sustain: sustain))
        }
        applyPlugins(song)
    }

    /// Only the knobs: no notes are touched, so this is safe to call while a slider is moving.
    func applyPlugins(_ song: Song) {
        let stepSeconds = 60 / song.bpm / 4
        for (i, ch) in channels.enumerated() where i < song.tracks.count {
            let t = song.tracks[i], fx = t.fx
            var p = DSPParams()
            p.vol = t.mute ? 0 : Float(t.vol)
            p.hold = Float(fx.hold); p.attack = Float(fx.attack); p.release = Float(fx.release)
            p.drive = Float(fx.drive); p.lofi = Float(fx.lofi); p.cutoff = Float(fx.cutoff); p.lowCut = Float(fx.lowCut)
            p.chorus = Float(fx.chorus); p.chorusRate = Float(fx.chorusRate); p.chorusDepth = Float(fx.chorusDepth)
            p.flanger = Float(fx.flanger); p.flangerRate = Float(fx.flangerRate); p.flangerDepth = Float(fx.flangerDepth); p.flangerFb = Float(fx.flangerFeedback)
            p.phaser = Float(fx.phaser); p.phaserRate = Float(fx.phaserRate); p.phaserDepth = Float(fx.phaserDepth); p.phaserFb = Float(fx.phaserFeedback)
            ch.dsp.params = p
            ch.rack.apply(fx, stepSeconds: stepSeconds)
        }
        let m = song.master, bands = masterEQ.bands
        bands[0].filterType = .lowShelf; bands[0].frequency = 120; bands[0].gain = Float(m.eqLow); bands[0].bypass = m.eqLow == 0
        bands[1].filterType = .parametric; bands[1].frequency = Float(m.eqMidFreq); bands[1].bandwidth = 1; bands[1].gain = Float(m.eqMid); bands[1].bypass = m.eqMid == 0
        bands[2].filterType = .highShelf; bands[2].frequency = 8000; bands[2].gain = Float(m.eqHigh); bands[2].bypass = m.eqHigh == 0
        masterComp.bypass = m.compThreshold >= 0 && m.compMakeup == 0
        setParam(masterComp, 0, m.compThreshold < 0 ? m.compThreshold : 0)
        setParam(masterComp, 1, min(40, max(0.1, m.compThreshold < 0 ? -m.compThreshold / max(1, m.compRatio) : 40)))
        setParam(masterComp, 4, min(0.2, max(0.0001, m.compAttack / 1000)))
        setParam(masterComp, 5, min(3, max(0.01, m.compRelease / 1000)))
        setParam(masterComp, 6, m.compMakeup)
        setParam(limiter, 0, 0.008); setParam(limiter, 1, 0.05); setParam(limiter, 2, m.loudness)   // attack, release, push
        av.mainMixerNode.outputVolume = 0.8
    }

    /// Start playing, from the top or from a place in the song given in steps.
    func play(fromStep s: Double = 0) { transport.start = transport.now + Int64(0.06 * sampleRate) - Int64((s * stepSamples).rounded()); transport.once = false; transport.playing = true }
    /// Jump to a place in the song while it plays. Notes that were sounding fade out.
    func seek(toStep s: Double) { transport.flush += 1; transport.start = transport.now + Int64(0.03 * sampleRate) - Int64((s * stepSamples).rounded()) }
    func stop() { transport.playing = false }

    /// Where the song is, in steps. Nil when it is not playing.
    var position: Double? {
        guard transport.playing, transport.loopLen > 0 else { return nil }
        let p = transport.now - transport.start
        return p < 0 ? 0 : Double(p % transport.loopLen) / stepSamples
    }

    /// Hear a sound from the crate without putting it on a track.
    func audition(_ info: SoundInfo, _ lib: Library, pitch: Int?, song: Song) {
        guard let buf = lib.buffer(info.id) else { return }
        preview.dsp.params = DSPParams()
        preview.dsp.set(Program(buffer: buf))
        preview.dsp.hit(rate: rate(info, buf, pitch: pitch, song: song, tune: 0), gain: 0.8)
    }

    /// Play a note on a track right now, through that track's plugins.
    func hit(track index: Int, pitch: Int?, song: Song, lib: Library, velocity: Double = 0.8) {
        guard index < channels.count, index < song.tracks.count, let info = lib.info(song.tracks[index].sound), let buf = lib.buffer(info.id) else { return }
        channels[index].dsp.hit(rate: rate(info, buf, pitch: pitch, song: song, tune: song.tracks[index].fx.tune), gain: Float(pow(velocity, 1.5)))
    }

    /// Play the song once through a separate offline engine and write it as a 16-bit WAV.
    static func export(_ song: Song, _ lib: Library, to url: URL) throws {
        let e = try Engine(offline: true)
        e.load(song, lib)
        e.transport.start = 0; e.transport.once = true; e.transport.playing = true
        let total = e.transport.loopLen + Int64(3 * e.sampleRate)          // three seconds for the last tails
        guard let buf = AVAudioPCMBuffer(pcmFormat: e.av.manualRenderingFormat, frameCapacity: e.av.manualRenderingMaximumFrameCount) else { return }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        while e.av.manualRenderingSampleTime < total {
            let n = AVAudioFrameCount(min(Int64(buf.frameCapacity), total - e.av.manualRenderingSampleTime))
            if try e.av.renderOffline(n, to: buf) != .success { break }
            try file.write(from: buf)
        }
        e.av.stop()
    }
}
