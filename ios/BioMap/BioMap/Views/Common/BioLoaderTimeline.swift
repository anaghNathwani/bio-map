import Foundation

/// What BioLoader shows at a given moment: one or two outlines (with how opaque each is), the nucleus dot's opacity, and the
/// organism's name. Kept free of SwiftUI so the timing can be tested without a device (see Tools/BioLoaderCheck).
///
/// Two modes, both cycling through every organism in OrganismData:
///  - morph: each outline flows into the next (the normal animation);
///  - fade:  the outlines cross-dissolve and never move. Used when Reduce Motion is on, so people who ask the system for less
///           movement still get the whole carousel (it used to show one still bird, which read as a broken loader).
enum BioLoaderTimeline {
    struct Layer { let radii: [Double]; let alpha: Double }
    struct Frame { let layers: [Layer]; let nucleus: Double; let name: String }

    /// A short pause on each shape, then the change. Deliberately brief: most loads last only a second or two, and a long
    /// pause on the first shape (the bird) meant short loads never got past it.
    static let hold = 0.45
    static let morph = 0.8
    static let fadeHold = 0.9
    static let fade = 0.6
    /// Amoeba onward are single cells and get a nucleus.
    static let nucleusFrom = 5

    static func frame(at time: TimeInterval, reduceMotion: Bool) -> Frame {
        let all = OrganismData.all
        let pause = reduceMotion ? fadeHold : hold
        let change = reduceMotion ? fade : morph
        let cycle = pause + change
        let step = Int(max(time, 0) / cycle)
        let within = max(time, 0) - Double(step) * cycle
        let fromIdx = step % all.count, toIdx = (step + 1) % all.count
        let raw = within < pause ? 0 : (within - pause) / change
        let t = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2          // ease in-out cubic
        let a = fromIdx >= nucleusFrom ? 1.0 : 0.0, b = toIdx >= nucleusFrom ? 1.0 : 0.0
        let nucleus = a + (b - a) * t
        let name = all[t > 0.5 ? toIdx : fromIdx].name
        if reduceMotion {
            return Frame(layers: [Layer(radii: all[fromIdx].r, alpha: 1 - t), Layer(radii: all[toIdx].r, alpha: t)],
                         nucleus: nucleus, name: name)
        }
        let radii = zip(all[fromIdx].r, all[toIdx].r).map { $0 + ($1 - $0) * t }
        return Frame(layers: [Layer(radii: radii, alpha: 1)], nucleus: nucleus, name: name)
    }
}
