import Foundation

/// Sunrise / sunset glare handling for the photo classifier.
///
/// Low sun does three things to a bird photo that the model (Google AIY Birds, trained on ordinary daylight
/// photos) copes with badly: an orange cast over the whole scene, a flat, washed-out veil when the sun is in or
/// near the frame, and a dark subject against a blown-out sky. This measures the 224x224 image the classifier is
/// about to see and, ONLY when it looks affected, produces a corrected copy. BirdClassifier then classifies both
/// and blends the results (30% original, 70% corrected), so a wrong "fix" can't take over by itself.
///
/// The maths is deliberately plain (no learned parts) and mirrors ml_pipeline/glare_eval/glare_lib.py line for
/// line: that script measures it against labelled bird photos under simulated glare, and
/// ml_pipeline/glare_eval/check_swift_parity.sh checks this file reproduces its output.
///
/// Input and output are Float32 RGB in 0...1, row-major HWC, `side` x `side` x 3.
enum GlareCorrector {
    /// OFF. The correction helped against *simulated* glare, but on 1,349 real iNaturalist photos (330 daylight, 238 golden hour,
    /// 781 with the sun within 3 degrees of the horizon) it did nothing for the photos where the model is weaker, and it slightly
    /// hurt ordinary daylight photos (-1.2 points of correct suggestions shown, interval -2.4 to -0.3; it fired on 24% of them).
    /// Real near-horizon photos are not warmer or flatter than daylight ones (cameras correct the cast themselves), so the
    /// simulation's assumptions did not hold. Kept in the code, with its parity tests, in case better evidence or a better
    /// correction turns up. See docs/GLARE_WEIGHT_PROGRAMMING.md ("What real photos showed").
    static var isEnabled = false

    static let side = 224

    // Gates: read off clean-vs-glare distributions of the measurements, not tuned on accuracy (see glare_lib.py).
    static let warmBorder: Float = 1.45     // background red/blue ratio (a red bird doesn't count: the centre is excluded)
    static let veilRange: Float = 0.65      // a flat luminance range ...
    static let veilWarm: Float = 1.25       // ... on a warm background means a veiling sun
    static let backlight: Float = 0.25      // background brighter than the subject by this much ...
    static let subjectDark: Float = 0.40    // ... and the subject is dark

    /// Blend used by the classifier when a correction was made: weight of the corrected photo's probabilities.
    static let correctedWeight: Float = 0.7

    struct Measurements {
        var borderWarmth: Float
        var range: Float
        var backlight: Float
        var centreMedian: Float
    }

    /// Which corrections were applied, for logging.
    struct Applied: OptionSet {
        let rawValue: Int
        static let warm = Applied(rawValue: 1)
        static let veil = Applied(rawValue: 2)
        static let backlit = Applied(rawValue: 4)
    }

    /// The corrected pixels and what was done, or nil when the photo looks ordinary (the common case).
    static func corrected(_ px: [Float]) -> (pixels: [Float], applied: Applied)? {
        guard isEnabled, px.count == side * side * 3 else { return nil }
        let m = measure(px)
        var y = px
        var applied: Applied = []
        if m.borderWarmth > warmBorder { y = grayWorld(y); applied.insert(.warm) }
        if m.range < veilRange && m.borderWarmth > veilWarm { y = autoLevels(y); applied.insert(.veil) }
        if m.backlight > backlight && m.centreMedian < subjectDark { y = shadowLift(y); applied.insert(.backlit) }
        return applied.isEmpty ? nil : (y, applied)
    }

    // MARK: - Measurements

    private static let centreRadius = Int(Double(side) * 0.3)          // 67
    private static var centreRange: Range<Int> { (side / 2 - centreRadius)..<(side / 2 + centreRadius) }

    private static func luminance(_ px: [Float], _ i: Int) -> Float {
        0.2126 * px[i * 3] + 0.7152 * px[i * 3 + 1] + 0.0722 * px[i * 3 + 2]
    }

    static func measure(_ px: [Float]) -> Measurements {
        var lum = [Float](repeating: 0, count: side * side)
        var centre: [Float] = [], border: [Float] = []
        centre.reserveCapacity(centreRange.count * centreRange.count)
        border.reserveCapacity(side * side)
        var borderR: Float = 0, borderB: Float = 0
        for row in 0..<side {
            for col in 0..<side {
                let i = row * side + col
                let l = luminance(px, i)
                lum[i] = l
                if centreRange.contains(row) && centreRange.contains(col) {
                    centre.append(l)
                } else {
                    border.append(l)
                    borderR += px[i * 3]
                    borderB += px[i * 3 + 2]
                }
            }
        }
        let n = Float(border.count)
        let centreMed = median(centre), borderMed = median(border)
        return Measurements(
            borderWarmth: (borderR / n) / max(borderB / n, 1e-4),
            range: percentile(lum, 99) - percentile(lum, 1),
            backlight: borderMed - centreMed,
            centreMedian: centreMed)
    }

    // MARK: - Corrections

    /// Remove an orange cast: scale channels toward equal means (clamped to 0.7...1.45, 70% strength).
    static func grayWorld(_ px: [Float], strength: Float = 0.7) -> [Float] {
        var sum: [Float] = [0, 0, 0]
        let count = px.count / 3
        for i in 0..<count { for c in 0..<3 { sum[c] += px[i * 3 + c] } }
        let means = sum.map { $0 / Float(count) }
        let overall = (means[0] + means[1] + means[2]) / 3
        let gains: [Float] = means.map {
            let g = min(max(overall / max($0, 1e-4), 0.7), 1.45)
            return 1 + strength * (g - 1)
        }
        var out = px
        for i in 0..<count { for c in 0..<3 { out[i * 3 + c] = min(max(px[i * 3 + c] * gains[c], 0), 1) } }
        return out
    }

    /// Stretch each channel's 1st...99th percentile to 0...1 (restores contrast flattened by a veiling sun).
    static func autoLevels(_ px: [Float]) -> [Float] {
        let count = px.count / 3
        var out = px
        for c in 0..<3 {
            var channel = [Float](repeating: 0, count: count)
            for i in 0..<count { channel[i] = px[i * 3 + c] }
            let lo = percentile(channel, 1), hi = percentile(channel, 99)
            let span = max(hi - lo, 0.15)
            for i in 0..<count { out[i * 3 + c] = min(max((px[i * 3 + c] - lo) / span, 0), 1) }
        }
        return out
    }

    /// Lift an underexposed subject and soften blown highlights, keeping hue (the gain is applied to RGB).
    static func shadowLift(_ px: [Float], target: Float = 0.42, knee: Float = 0.82) -> [Float] {
        let count = px.count / 3
        var centre: [Float] = []
        for row in centreRange { for col in centreRange { centre.append(luminance(px, row * side + col)) } }
        let med = median(centre)
        if med >= 0.38 { return px }
        let gamma = min(max(log(target) / log(max(med, 0.02)), 0.4), 1.0)    // < 1 brightens
        var out = px
        for i in 0..<count {
            let y = luminance(px, i)
            var y2 = pow(max(y, 1e-4), gamma)
            y2 -= 0.6 * max(y2 - knee, 0)
            let gain = min(max(y2 / max(y, 1e-4), 0), 4)
            for c in 0..<3 { out[i * 3 + c] = min(max(px[i * 3 + c] * gain, 0), 1) }
        }
        return out
    }

    // MARK: - Statistics (the same definitions numpy uses: linear interpolation, mean of the middle two)

    static func median(_ values: [Float]) -> Float {
        let s = values.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    static func percentile(_ values: [Float], _ p: Float) -> Float {
        let s = values.sorted()
        let rank = p / 100 * Float(s.count - 1)
        let lo = Int(rank.rounded(.down)), hi = min(lo + 1, s.count - 1)
        return s[lo] + (s[hi] - s[lo]) * (rank - Float(lo))
    }
}
