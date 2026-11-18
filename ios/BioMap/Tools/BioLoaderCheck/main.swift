// Checks BioLoaderTimeline without a device: both modes must visit every organism, change shape soon after a loader appears
// (short loads used to see only the bird), and the cross-fade must never move or leave a gap.
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) { print((ok ? "ok    " : "FAIL  ") + what); if !ok { failures += 1 } }

let all = OrganismData.all.map { $0.name }
for reduce in [false, true] {
    let mode = reduce ? "Reduce Motion (cross-fade)" : "normal (morph)"
    var seen = Set<String>(), firstChange: Double?, firstName: String?
    var worstGap = 0.0, maxLayers = 0
    var t = 0.0
    while t < 30 {
        let f = BioLoaderTimeline.frame(at: t, reduceMotion: reduce)
        if firstName == nil { firstName = f.name }
        if firstChange == nil, f.name != firstName { firstChange = t }
        seen.insert(f.name)
        maxLayers = max(maxLayers, f.layers.count)
        if reduce { worstGap = max(worstGap, abs(f.layers.map { $0.alpha }.reduce(0, +) - 1)) }
        t += 0.02
    }
    check(seen.count == all.count, "\(mode): shows all \(all.count) organisms within 30 s (saw \(seen.count))")
    check((firstChange ?? 99) <= 1.5, "\(mode): the first shape change is visible by \(String(format: "%.2f", firstChange ?? 99)) s (<= 1.5 s)")
    if reduce {
        check(maxLayers == 2 && worstGap < 1e-9, "Reduce Motion: only opacity changes (two fixed outlines, alphas always sum to 1)")
        let f = BioLoaderTimeline.frame(at: 0.3, reduceMotion: true)
        check(f.layers[0].radii == OrganismData.all[0].r, "Reduce Motion: outlines are the stored shapes, not interpolated")
    }
}
// the old behaviour for contrast: the bird alone for 1.1 s before anything changed
check(BioLoaderTimeline.hold + BioLoaderTimeline.morph < 1.3 + 0.0001 || BioLoaderTimeline.hold < 1.1, "pause on the first shape is shorter than the old 1.1 s")
print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) FAILED")
exit(failures == 0 ? 0 : 1)
