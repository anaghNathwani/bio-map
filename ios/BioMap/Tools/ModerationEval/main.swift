import Foundation

// Usage: run.sh — measures AnnotationModerator against cases.json plus every name
// in the bundled bird lists (which must all pass).
struct Cases: Decodable { let genuine: [String]; let silly: [String]; let known_misses: [String] }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let bundled = URL(fileURLWithPath: CommandLine.arguments[2])
func names(_ file: String) -> [String] {
    (try? JSONDecoder().decode([String].self, from: Data(contentsOf: bundled.appendingPathComponent(file)))) ?? []
}
let known = names("BundledBirdNETLabels.json").filter { !$0.isEmpty }
    + names("BundledBirdLabels.json").filter { $0 != "Unknown / Not a Bird" }
let cases = try JSONDecoder().decode(Cases.self, from: Data(contentsOf: dir.appendingPathComponent("cases.json")))
let moderator = AnnotationModerator(knownNames: known)

let missedNames = known.filter { moderator.verdict(species: $0).isFlagged }
let falsePositives = cases.genuine.filter { moderator.verdict(species: $0).isFlagged }
let falseNegatives = cases.silly.filter { !moderator.verdict(species: $0).isFlagged }
print("bundled bird names flagged:   \(missedNames.count)/\(known.count)"); missedNames.prefix(10).forEach { print("   \($0)") }
print("genuine entries flagged:      \(falsePositives.count)/\(cases.genuine.count)"); falsePositives.forEach { print("   \($0)") }
print("silly entries let through:    \(falseNegatives.count)/\(cases.silly.count)"); falseNegatives.forEach { print("   \($0)") }
print("known limitations (not counted): \(cases.known_misses.joined(separator: ", "))")
exit(missedNames.isEmpty && falsePositives.isEmpty && falseNegatives.isEmpty ? 0 : 1)
