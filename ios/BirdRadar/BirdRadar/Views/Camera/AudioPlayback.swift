import AVFoundation

/// Play/pause playback of a recording, used both to preview a take before
/// submitting and to listen to a sighting's audio afterwards.
///
/// The audio session is switched to .playback every time: the recorder leaves
/// it in .record (input-only), which makes any player created afterwards
/// completely silent. .playback also ignores the ring/silent switch, which is
/// what someone tapping "play" expects.
@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var failed = false

    private var player: AVAudioPlayer?

    func play(data: Data) {
        stop()
        start { try AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue) }
    }

    func play(fileURL: URL) {
        stop()
        start { try AVAudioPlayer(contentsOf: fileURL) }
    }

    func toggle(fileURL: URL) {
        if isPlaying { stop() } else { play(fileURL: fileURL) }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func start(_ make: () throws -> AVAudioPlayer) {
        failed = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try make()
            player.delegate = self
            player.volume = 1.0
            guard player.prepareToPlay(), player.play() else { throw CocoaError(.fileReadCorruptFile) }
            self.player = player
            isPlaying = true
        } catch {
            print("[AudioPlayback] Could not play: \(error)")
            failed = true
            isPlaying = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.isPlaying = false
        }
    }
}
