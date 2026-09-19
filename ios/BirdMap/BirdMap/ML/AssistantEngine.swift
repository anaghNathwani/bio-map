import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Something that can answer a question, entirely on this device. Yields the
/// reply as progressively longer snapshots of its full text.
protocol AssistantEngine: AnyObject {
    func reply(to prompt: String) -> AsyncThrowingStream<String, Error>
    /// Forget the conversation so far.
    func reset()
}

enum AssistantError: LocalizedError {
    case blocked

    var errorDescription: String? {
        "I couldn't answer that one — try rephrasing it, or ask about birds or about using BirdMap."
    }
}

/// What the assistant knows about the app. Kept short: the on-device model's
/// context window is small (~4k tokens) and this is re-sent with every session.
enum AssistantKnowledge {
    static let instructions = """
    You are BirdMap Assistant, a friendly helper inside BirdMap, a citizen-science app where people \
    report bird sightings and help identify them. Everything you say runs privately on this phone.

    Answer briefly — two to four sentences unless asked for more. You may answer general bird \
    questions (identification tips, behavior, habitat, diet, migration, feeding, safety) and \
    questions about using BirdMap. If you aren't sure, say so; never invent facts, species, or \
    sightings. You cannot see the user's photos, recordings, or the map.

    For general bird questions, answer from your own knowledge with concrete, useful details. Only \
    when explaining how BirdMap itself works, stick to the facts listed below and do not invent \
    features that aren't listed.

    Stay on topic: if a question is not about birds, wildlife, or BirdMap, reply with just one \
    short sentence saying you can only help with birds and BirdMap, and do not answer it at all.

    How BirdMap works:
    - Map tab: one pin per place where sightings were reported. A number on a pin means several \
    sightings there; tap it to pick one. Tap a single pin to open its sighting. The bookmark in a \
    sighting saves it; the bookmark button on the map lists saved sightings. Use the search bar to \
    find a species or a place.
    - Report tab, Photo: take or choose a photo and the app suggests a species on the device \
    (Google's AIY Birds model, about 960 species). If it isn't confident it says so instead of \
    guessing. The circular arrow at the photo's top-left retakes it.
    - Report tab, Audio: record up to 30 seconds, or upload an existing audio file. Cornell's \
    BirdNET identifies bird calls on the device, using the phone's location to rule out species \
    that don't live nearby. Use Listen back to replay and the circular arrow to record again. \
    Recording close to the bird, away from wind and voices, helps.
    - After submitting, the AI's guess can be confirmed, marked wrong, or marked unsure. Anyone can \
    add their own ID (an annotation) to a sighting; annotations count toward the Leaders board. \
    Joke or spam annotations are flagged.
    - Location access makes audio identification more accurate.
    """
}

// MARK: - Apple's on-device language model

#if canImport(FoundationModels)
@available(iOS 26.0, *)
final class FoundationModelsEngine: AssistantEngine {
    private var session = LanguageModelSession(instructions: AssistantKnowledge.instructions)

    private enum Failure { case contextOverflow, blocked, other }

    /// iOS 27 replaced GenerationError with LanguageModelError; the running OS
    /// decides which one gets thrown, so both have to be recognised.
    private static func classify(_ error: Error) -> Failure {
        if #available(iOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .contextOverflow
            case .guardrailViolation, .refusal: return .blocked
            default: return .other
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .contextOverflow
            case .guardrailViolation, .refusal: return .blocked
            default: return .other
            }
        }
        return .other
    }

    func reply(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                func run() async throws {
                    for try await snapshot in self.session.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                }
                do {
                    try await run()
                    continuation.finish()
                } catch {
                    print("[AssistantEngine] generation failed: \(error)")
                    switch Self.classify(error) {
                    case .contextOverflow:
                        // Long chats outgrow the model's small window: start fresh and retry once.
                        self.reset()
                        do { try await run(); continuation.finish() }
                        catch { continuation.finish(throwing: error) }
                    case .blocked:
                        continuation.finish(throwing: AssistantError.blocked)
                    case .other:
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func reset() {
        session = LanguageModelSession(instructions: AssistantKnowledge.instructions)
    }
}
#endif

// MARK: - Fallback for devices without Apple Intelligence

/// Answers questions about *using the app* from a fixed FAQ by keyword match —
/// no general bird knowledge, and it says so. Used when the on-device language
/// model isn't available (older iPhones, Apple Intelligence switched off).
final class OfflineHelpEngine: AssistantEngine {
    private struct Entry {
        let keywords: Set<String>
        let answer: String
    }

    private let entries: [Entry] = [
        Entry(keywords: ["report", "submit", "post", "add", "sighting", "photo", "picture", "take"],
              answer: "Open the Report tab, choose Photo, then take or pick a picture. The app suggests a species on your phone; add notes if you like and tap Submit Sighting."),
        Entry(keywords: ["retake", "redo", "again", "restart", "discard", "wrong", "delete"],
              answer: "Tap the circular arrow in the top-left corner of the photo (or of the recording card on the Audio screen) to throw it away and start over."),
        Entry(keywords: ["audio", "record", "recording", "sound", "call", "song", "noise", "birdnet"],
              answer: "Report tab → Audio. Tap the mic to record up to 30 seconds; BirdNET then names the bird right on your phone. Use Listen back to replay it, or the circular arrow to record again."),
        Entry(keywords: ["upload", "file", "import", "existing", "voice", "memo"],
              answer: "On the Audio screen tap \"Upload an audio file\" and choose any audio file. It's converted to a small clip and trimmed to the first 30 seconds, then identified like a fresh recording."),
        Entry(keywords: ["identify", "identification", "species", "ai", "guess", "confident", "accurate", "model"],
              answer: "Photos use Google's AIY Birds model and recordings use Cornell's BirdNET, both running on your phone. If they aren't confident enough they say so rather than guess. You can confirm, correct, or mark the guess unsure after submitting."),
        Entry(keywords: ["map", "pin", "pins", "multiple", "several", "same", "place", "number"],
              answer: "The map shows one pin per place. A number on a pin means several sightings were reported there — tap it to see the list and pick one. A pin with no number opens its sighting directly."),
        Entry(keywords: ["save", "saved", "bookmark", "favorite", "keep"],
              answer: "Tap the bookmark in a sighting to save it. The bookmark button at the top-left of the map lists everything you've saved. Saved sightings are stored on this device."),
        Entry(keywords: ["search", "find", "look", "location", "where"],
              answer: "Use the search bar on the Map tab to find a species (or a note or username) among sightings, or a place to jump the map to."),
        Entry(keywords: ["annotate", "annotation", "id", "identify", "correct", "leaderboard", "leaders", "points", "rank"],
              answer: "Open any sighting and tap the checklist button to add your own ID (an annotation). Annotations count toward your total on the Leaders tab."),
        Entry(keywords: ["flagged", "flag", "spam", "joke", "shitpost", "moderation"],
              answer: "Annotations that look like jokes or spam are flagged automatically, using a small text model that compares them to examples of genuine and silly entries. Flagged ones are labelled but not deleted."),
        Entry(keywords: ["gps", "permission", "allow", "accuracy"],
              answer: "Allow Location for BirdMap in Settings. It pins your sighting on the map and lets audio identification rule out species that don't live near you."),
    ]

    func reply(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(answer(for: prompt))
            continuation.finish()
        }
    }

    func reset() {}

    private func answer(for prompt: String) -> String {
        let words = Set(prompt.lowercased().split { !$0.isLetter }.map(String.init))
        let best = entries
            .map { (entry: $0, score: $0.keywords.intersection(words).count) }
            .max { $0.score < $1.score }
        if let best, best.score > 0 { return best.entry.answer }
        return "I can help with using BirdMap — reporting a photo or recording, the map and saving sightings, or how identification and annotations work. General bird questions need Apple Intelligence, which isn't available on this device."
    }
}

// MARK: - Choosing an engine

enum AssistantFactory {
    /// The best engine this device supports, plus a note to show the user when
    /// it's the limited fallback (nil when the full model is running).
    static func make() -> (engine: AssistantEngine, note: String?) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return (FoundationModelsEngine(), nil)
            case .unavailable(let reason):
                let note: String
                switch reason {
                case .deviceNotEligible:
                    note = "This iPhone doesn't support Apple Intelligence, so I can only answer questions about using BirdMap."
                case .appleIntelligenceNotEnabled:
                    note = "Turn on Apple Intelligence in Settings to ask me general bird questions. Until then I can only answer questions about using BirdMap."
                case .modelNotReady:
                    note = "Apple's on-device model is still getting ready. For now I can only answer questions about using BirdMap."
                @unknown default:
                    note = "The on-device language model isn't available, so I can only answer questions about using BirdMap."
                }
                return (OfflineHelpEngine(), note)
            }
        }
        #endif
        return (OfflineHelpEngine(), "General bird questions need Apple Intelligence (iOS 26 or later). I can still answer questions about using BirdMap.")
    }
}
