import AVFoundation

/// What the sampler needs to hold a sound at a steady level for as long as a note lasts. Two things, worked out once
/// per sound: a gain curve that takes the sound's own fade out of it, and a stretch of the sound after its attack,
/// prepared so that it can go round and round without a seam.
final class Sustain {
    static let hop = 32                            // frames between entries in the two curves
    let enter: Double                              // frame where reading moves from the sound itself to the loop
    let cycle: Int                                 // frames in the loop
    let loopL: UnsafePointer<Float>, loopR: UnsafePointer<Float>
    let lift: UnsafePointer<Float>          // gain per hop that flattens the sound's own level
    let shape: UnsafePointer<Float>         // the sound's own level per hop: 1 where its body begins, falling as it fades
    let table: Int                                 // entries in lift and shape
    let match: Double                              // how alike the two ends of the loop are, 0 to 1 (for checks)

    /// Nil when the sound is too short or too quiet to hold (most drums).
    init?(_ buf: AVAudioPCMBuffer) {
        let n = Int(buf.frameLength), sr = buf.format.sampleRate, hop = Sustain.hop
        guard n > Int(0.35 * sr), buf.format.channelCount >= 2, let ch = buf.floatChannelData else { return nil }
        let l = ch[0], r = ch[1]

        // The level of the sound over time: its power, smoothed twice over 60 ms so that even a low bass note reads as steady.
        let m = n / hop + 1
        var power = [Double](repeating: 0, count: m)
        for k in 0..<m {
            let a = k * hop, b = min(n, a + hop)
            if a < b { var s = 0.0; for i in a..<b { s += Double(l[i] * l[i] + r[i] * r[i]) }; power[k] = s / Double(2 * (b - a)) }
        }
        func smooth(_ x: [Double], _ half: Int) -> [Double] {
            var sum = [Double](repeating: 0, count: x.count + 1)
            for i in 0..<x.count { sum[i + 1] = sum[i] + x[i] }
            return (0..<x.count).map { i in let a = max(0, i - half), b = min(x.count, i + half + 1); return (sum[b] - sum[a]) / Double(b - a) }
        }
        let half = max(1, Int(0.03 * sr) / hop)
        let env = smooth(smooth(power, half), half).map { $0.squareRoot() }
        guard let peak = env.max(), peak > 1e-4, let k0 = env.firstIndex(where: { $0 >= 0.9 * peak }) else { return nil }
        let ref = env[k0]                                              // the level a held note stays at

        // The loop starts once the attack (and any drop in pitch at the front) is over, and ends before the sound has faded far.
        var b = max(k0 * hop + Int(0.06 * sr), Int(0.2 * sr))

        // Some sounds are still sliding in pitch after their attack (a diving 808). Looping that would hold the note sharp. So
        // count the wave's cycles in two windows side by side and move the start later until they agree. Where the cycles
        // never come out even anywhere (noise, a thick detuned pad), the start stays where it is.
        var low = [Float](repeating: 0, count: n)
        do {
            let a = Float(1 - exp(-2 * Double.pi * 120 / sr))
            var y1: Float = 0, y2: Float = 0
            for i in 0..<n { y1 += a * ((l[i] + r[i]) * 0.5 - y1); y2 += a * (y1 - y2); low[i] = y2 }
        }
        func pitch(_ from: Int, _ len: Int) -> Double? {
            var first = -1.0, last = -1.0, count = 0, sum = 0.0, squares = 0.0
            for i in max(1, from)..<min(n, from + len) where low[i - 1] < 0 && low[i] >= 0 {
                let at = Double(i - 1) + Double(-low[i - 1] / (low[i] - low[i - 1]))
                if count > 0 { let gap = at - last; sum += gap; squares += gap * gap } else { first = at }
                last = at; count += 1
            }
            guard count >= 4 else { return nil }
            let gaps = Double(count - 1), mean = sum / gaps, spread = max(0, squares / gaps - mean * mean).squareRoot()
            return spread < 0.05 * mean ? gaps / (last - first) : nil
        }
        let window = Int(0.15 * sr), latest = min(Int(0.45 * Double(n)), n - Int(0.5 * sr))
        var settled = b, found = false
        while settled <= latest {
            if let p1 = pitch(settled, window), let p2 = pitch(settled + window, window), abs(p1 / p2 - 1) < 0.0012 { found = true; break }
            settled += Int(0.05 * sr)                       // uneven cycles this early usually mean the pitch is still moving: look later
        }
        if found { b = settled }

        func end(_ drop: Double) -> Int {
            let floor = env[min(m - 1, b / hop)] * pow(10, -drop / 20)
            var k = b / hop + 1
            while k < m && env[k] >= floor { k += 1 }
            return min(k * hop, n - Int(0.02 * sr) - 4, b + Int(4 * sr))
        }
        var u = end(10)
        if u - b < Int(0.15 * sr) { u = end(24) }
        guard u - b >= Int(0.12 * sr) else { return nil }

        let liftCurve = UnsafeMutablePointer<Float>.allocate(capacity: m + 2), shapeCurve = UnsafeMutablePointer<Float>.allocate(capacity: m + 2)
        for k in 0..<(m + 2) {
            let e = env[min(k, m - 1)]
            liftCurve[k] = k < k0 ? 1 : Float(min(60, ref / max(e, 1e-9)))
            shapeCurve[k] = k < k0 ? 1 : Float(e / ref)
        }
        func flat(_ src: UnsafeMutablePointer<Float>, _ i: Int) -> Float {      // the sound with its fade taken out
            let k = i / hop, f = Float(i - k * hop) / Float(hop)
            return src[i] * (liftCurve[k] + (liftCurve[k + 1] - liftCurve[k]) * f)
        }

        // The end of the loop is blended into its start. Pick the loop length, within one slow cycle of a bass note, at which
        // the two line up best, so the blend is between two copies of the same wave and nothing cancels.
        let x = min(Int(0.6 * sr), max(Int(0.03 * sr), (u - b) * 35 / 100))
        let d0 = u - x - b, span = min(Int(0.03 * sr), d0 / 4), win = min(Int(0.05 * sr), x)
        var a2 = 0.0
        for i in stride(from: 0, to: win, by: 2) { let p = Double(flat(l, b + i)), q = Double(flat(r, b + i)); a2 += p * p + q * q }
        var best = d0, bestScore = -2.0
        var d = d0 - span
        while d <= d0 {
            var ac = 0.0, c2 = 0.0
            var i = 0
            while i < win {
                let p = Double(flat(l, b + i)), q = Double(flat(r, b + i)), p2 = Double(flat(l, b + d + i)), q2 = Double(flat(r, b + d + i))
                ac += p * p2 + q * q2; c2 += p2 * p2 + q2 * q2
                i += 2
            }
            let score = ac / (a2 * c2 + 1e-18).squareRoot()
            if score > bestScore { bestScore = score; best = d }
            d += 1
        }
        let c = best, rho = min(1, max(0, bestScore))
        let outL = UnsafeMutablePointer<Float>.allocate(capacity: c + 2), outR = UnsafeMutablePointer<Float>.allocate(capacity: c + 2)
        for t in x..<c { outL[t] = flat(l, b + t); outR[t] = flat(r, b + t) }
        // The blend. Two copies of a thick sound never line up all the way through, and where they disagree a plain blend
        // goes quiet. So measure how loud the blend came out against how loud its two halves were, and make up the difference.
        var pa = [Double](repeating: 0, count: x), pb = pa, py = pa
        for t in 0..<x {
            let w = Float(t) / Float(x), fi = 0.5 - 0.5 * cosf(.pi * w), fo = 1 - fi
            let al = flat(l, b + c + t), ar = flat(r, b + c + t), bl = flat(l, b + t), br = flat(r, b + t)
            outL[t] = fo * al + fi * bl; outR[t] = fo * ar + fi * br
            pa[t] = Double(al * al + ar * ar); pb[t] = Double(bl * bl + br * br); py[t] = Double(outL[t] * outL[t] + outR[t] * outR[t])
        }
        let reach = max(1, min(Int(0.03 * sr), x / 4))
        pa = smooth(smooth(pa, reach), reach); pb = smooth(smooth(pb, reach), reach); py = smooth(smooth(py, reach), reach)
        for t in 0..<x {
            let w = Double(t) / Double(x), fi = 0.5 - 0.5 * cos(.pi * w), edge = min(1, Double(min(t, x - t)) / Double(reach))
            let want = (1 - fi) * pa[t] + fi * pb[t]
            let gain = min(2.5, max(0.5, (want / max(py[t], 1e-12)).squareRoot()))
            let g = Float(1 + (gain - 1) * edge)                                    // eases to no change at both ends, so it joins cleanly
            outL[t] *= g; outR[t] *= g
        }
        outL[c] = outL[0]; outL[c + 1] = outL[1]; outR[c] = outR[0]; outR[c + 1] = outR[1]
        table = m; lift = UnsafePointer(liftCurve); shape = UnsafePointer(shapeCurve)
        cycle = c; enter = Double(b + c); match = rho
        loopL = UnsafePointer(outL); loopR = UnsafePointer(outR)
    }

    deinit { loopL.deallocate(); loopR.deallocate(); lift.deallocate(); shape.deallocate() }
}
