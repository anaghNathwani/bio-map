import SwiftUI
import AVFoundation

/// Incognito live view: the camera with a green, pixelated, terminal-style box and tag on every bird. Tap a bird to
/// pick it out. Nothing is recorded, saved or uploaded.
struct LiveScopeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scope = LiveBirdScope()

    private static let green = Color(red: 0, green: 1, blue: 0.255)

