// Swift side of the parity check: compiled together with ios/.../ML/GlareCorrector.swift by check_swift_parity.sh.
import Foundation

GlareCorrector.isEnabled = true     // the app ships it switched off; the parity check exercises the maths
let dir = CommandLine.arguments[1]
let meta = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "\(dir)/cases.json"))) as! [[String: Any]]

func floats(_ path: String) -> [Float] {
    let d = try! Data(contentsOf: URL(fileURLWithPath: path))
    return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

var worst: Float = 0, flagMismatch = 0, corrected = 0
for m in meta {
    let id = m["id"] as! Int
    let expectedFlags = (m["flags"] as! [String]).sorted()
    let input = floats("\(dir)/\(id).in.f32"), expected = floats("\(dir)/\(id).out.f32")
    var got: [String] = [], out = input
    if let r = GlareCorrector.corrected(input) {
        out = r.pixels; corrected += 1
        if r.applied.contains(.warm) { got.append("warm") }
        if r.applied.contains(.veil) { got.append("veil") }
        if r.applied.contains(.backlit) { got.append("backlit") }
    }
    if got.sorted() != expectedFlags { flagMismatch += 1; print("flags differ in case \(id) (\(m["cond"]!)): swift \(got) python \(expectedFlags)") }
    var d: Float = 0
    for i in 0..<out.count { d = max(d, abs(out[i] - expected[i])) }
    worst = max(worst, d)
}
print("cases: \(meta.count), corrected: \(corrected), flag mismatches: \(flagMismatch), max |swift - python| = \(worst)")
exit((flagMismatch == 0 && worst < 2e-3) ? 0 : 1)
