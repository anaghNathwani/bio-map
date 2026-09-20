import Foundation

/// Decides whether a community annotation looks like a genuine attempt at
/// naming a bird or like a joke/spam entry — entirely on the device.
///
/// This replaces the server-side text-similarity filter (ml_pipeline/
/// live_poll.py), which compared the text to ten "genuine" and ten "silly"
/// example sentences with a tiny margin and so both flagged real species
/// ("Iceland Gull") and passed nonsense ("banana", "Pikachu"). The species
/// field is the only free text in an annotation (behavior and age come from
/// fixed chips), so the real question is "is this a bird name?" — which can be
/// answered against the ~7,000 bird names the app already ships for identification.
///
/// Layers, cheapest first:
///  1. blank / "unsure" annotations are always fine (product rule);
///  2. an exact match with a known bird name is fine;
///  3. a near-miss of a known name (a typo) is fine;
///  4. a known name inside a longer phrase ("Northern Cardinal, male") is fine;
///  5. a generic bird word ("sparrow", "hawk sp.", "little brown bird") is fine
///     *unless* it contains a joke word ("fake bird", "lol") or is a known joke
///     ("Big Bird", "Angry Birds");
///  6. anything else is flagged — a label, never a deletion.
///
/// Deliberately no text-embedding "does this sound silly" step: tried and
/// measured, it flagged real single words ("hawk", "duck", "eagle") as jokes.
struct AnnotationModerator {
    struct Verdict: Equatable {
        let isFlagged: Bool
        let reason: String
    }

    private let knownNames: Set<String>
    private let namesByLength: [Int: [String]]
    private let familyWords: Set<String>

    /// Words that name a bird without naming a species. The family words
    /// ("sparrow", "warbler"...) are also derived from the name lists below.
    private static let genericWords: Set<String> = [
        "bird", "birds", "songbird", "shorebird", "seabird", "waterbird", "waterfowl", "raptor",
        "passerine", "fowl", "gamebird", "wader", "hummer", "lbj", "sp", "spp", "unknown", "unidentified",
        "seagull", "chicken", "hen", "rooster", "turkey", "peacock", "peafowl", "goose", "geese", "pigeon",
        "parrot", "eagle", "hawk", "owl", "duck", "swan", "crane", "stork", "dove",
        // Iconic birds the bundled lists only carry under longer names (or not at all).
        "emu", "ostrich", "rhea", "cassowary", "kiwi", "puffin", "roadrunner", "flamingo", "kookaburra",
    ]

    /// Whole-entry jokes that contain a legitimate bird word.
    private static let jokePhrases: Set<String> = [
        "big bird", "angry birds", "angry bird", "flappy bird", "tweety", "tweety bird", "twitter bird",
        "donald duck", "daffy duck", "rubber duck", "woodstock", "road runner", "chicken nugget",
        "chicken nuggets", "rotisserie chicken", "duck face", "bird is the word", "pterodactyl",
        "dragon bird", "batman bird", "not a bird", "no bird", "fake bird", "bird box",
    ]

    /// Any of these in an entry marks it as a joke, even next to a bird word.
    private static let jokeWords: Set<String> = [
        "lol", "lmao", "lmfao", "rofl", "haha", "hahaha", "hehe", "idk", "bruh", "bro", "sus", "fake", "joke",
        "test", "testing", "poop", "fart", "butt", "wtf", "yeet", "meme", "troll", "trolling", "vibes", "asdf",
        "asdfgh", "qwerty", "lmk", "nothing", "whatever", "random", "dragon", "batman", "pikachu",
        // Titles bolted onto a bird word ("Mr. Bird", "Sir Chirps-a-lot") and game/cartoon references.
        "mr", "mrs", "sir", "lord", "captain", "minecraft", "fortnite", "roblox", "mario", "sonic", "zelda",
    ]

    init(knownNames rawNames: [String]) {
        var names = Set<String>()
        var byLength: [Int: [String]] = [:]
        var lastWordCounts: [String: Int] = [:]
        for raw in rawNames {
            let name = Self.normalize(raw)
            guard !name.isEmpty, names.insert(name).inserted else { continue }
            byLength[name.count, default: []].append(name)
            if let last = name.split(separator: " ").last { lastWordCounts[String(last), default: 0] += 1 }
        }
        knownNames = names
        namesByLength = byLength
        // The last word of any bird name is a bird word on its own ("puffin" from
        // "Atlantic Puffin", "roadrunner" from "Greater Roadrunner", "sparrow", "gull").
        // Short ones must be common ("jay", "tit") so an odd one-off can't qualify.
        familyWords = Set(lastWordCounts.filter { ($0.key.count >= 4 && $0.value >= 2) || ($0.key.count == 3 && $0.value >= 3) }.keys)
    }

    // MARK: - Verdict

    func verdict(species rawSpecies: String, reviewOfAI: String? = nil) -> Verdict {
        let species = Self.normalize(rawSpecies)
        if reviewOfAI == "unsure" { return Verdict(isFlagged: false, reason: "No species given") }
        if species.isEmpty {
            // Truly blank is fine; "???" or "!!!" (text with no letters or digits) is not.
            return rawSpecies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Verdict(isFlagged: false, reason: "No species given")
                : Verdict(isFlagged: true, reason: "No letters in the species name")
        }

        if Self.jokePhrases.contains(species) { return Verdict(isFlagged: true, reason: "Looks like a joke") }
        if knownNames.contains(species) { return Verdict(isFlagged: false, reason: "Known bird") }
        if isNearKnownName(species) { return Verdict(isFlagged: false, reason: "Close to a known bird") }

        let tokens = species.split(separator: " ").map(String.init)
        if tokens.contains(where: Self.jokeWords.contains) { return Verdict(isFlagged: true, reason: "Looks like a joke") }
        if containsKnownName(species) { return Verdict(isFlagged: false, reason: "Names a known bird") }
        if usesBirdWord(tokens) { return Verdict(isFlagged: false, reason: "Generic bird description") }
        return Verdict(isFlagged: true, reason: "Not a bird name we recognise")
    }

    // MARK: - Matching

    /// Lowercase, accent-free, apostrophes dropped, other punctuation to spaces —
    /// applied identically to the bundled names and to user input so
    /// "Cooper's Hawk" and "coopers hawk" agree.
    static func normalize(_ raw: String) -> String {
        var text = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        text = text.replacingOccurrences(of: "['’`]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    private func isNearKnownName(_ text: String) -> Bool {
        let tolerance = text.count >= 12 ? 2 : (text.count >= 5 ? 1 : 0)
        guard tolerance > 0 else { return false }
        for length in max(1, text.count - tolerance)...(text.count + tolerance) {
            for name in namesByLength[length] ?? [] where Self.editDistance(text, name, limit: tolerance) <= tolerance {
                return true
            }
        }
        return false
    }

    /// A known name appearing as whole words inside the text ("northern
    /// cardinal male", "female mallard", "coopers hawk or sharp shinned hawk").
    /// Single-word names must be 5+ letters so short ones can't match by accident.
    private func containsKnownName(_ text: String) -> Bool {
        let padded = " \(text) "
        for name in knownNames where (name.contains(" ") || name.count >= 5) && padded.contains(" \(name) ") {
            return true
        }
        return false
    }

    private func usesBirdWord(_ tokens: [String]) -> Bool {
        tokens.contains { word in
            let singular = word.hasSuffix("s") ? String(word.dropLast()) : word
            return Self.genericWords.contains(word) || familyWords.contains(word) || familyWords.contains(singular)
        }
    }

    // MARK: - Math

    /// Optimal-string-alignment edit distance, abandoned early once it exceeds `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous2 = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(a.count, 1) where i <= a.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...max(b.count, 1) where j <= b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { value = min(value, previous2[j - 2] + 1) }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return limit + 1 }
            (previous2, previous, current) = (previous, current, previous2)
        }
        return previous[b.count]
    }
}

// MARK: - App-wide instance

extension AnnotationModerator {
    /// Built once from the bird names already bundled for identification: the
    /// BirdNET list (~6,500 species, blank entries are non-bird sounds) and the
    /// photo classifier's list (~960).
    static let shared: AnnotationModerator = {
        func names(_ resource: String) -> [String] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return list
        }
        let photo = names("BundledBirdLabels").filter { $0 != "Unknown / Not a Bird" }
        return AnnotationModerator(knownNames: names("BundledBirdNETLabels") + photo)
    }()
}
