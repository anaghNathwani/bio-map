import AVFoundation

/// Turns a user-picked audio file (Voice Memos export, an mp3/wav from another
/// recorder, etc.) into the same small mono AAC .m4a the in-app recorder makes.
///
/// This has to shrink the file, not just copy it: recordings are embedded as
/// base64 inside the Firestore sighting document, which is capped around 1 MiB,
/// so a multi-minute or high-bitrate file simply wouldn't upload. 30 s of mono
/// AAC at 64 kbps is ~240 KB.
enum AudioImporter {
    struct Result {
        let seconds: Double
        /// The source was longer than `maxSeconds`, so only the start was kept.
        let wasTrimmed: Bool
    }

    enum ImportError: LocalizedError {
        case unreadable, empty

        var errorDescription: String? {
            switch self {
            case .unreadable: return "that file isn't an audio format this device can read"
            case .empty: return "that file has no audio in it"
            }
        }
    }

    private static let outputSampleRate = 44_100.0
    private static let outputBitRate = 64_000

    static func convert(_ source: URL, to destination: URL, maxSeconds: Double) throws -> Result {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: source) } catch { throw ImportError.unreadable }
        guard input.length > 0 else { throw ImportError.empty }

        let inputFormat = input.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outputSampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else { throw ImportError.unreadable }

        // Read only what will be kept — never the whole file.
        let keepFrames = AVAudioFramePosition(min(Double(input.length), maxSeconds * inputFormat.sampleRate))
        let wasTrimmed = input.length > keepFrames
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(keepFrames)) else {
            throw ImportError.unreadable
        }
        try input.read(into: inBuffer, frameCount: AVAudioFrameCount(keepFrames))

        let ratio = outputSampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 4096
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else {
            throw ImportError.unreadable
        }

        var supplied = false
        var conversionError: NSError?
        converter.convert(to: outBuffer, error: &conversionError) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return inBuffer
        }
        if let conversionError { throw conversionError }
        guard outBuffer.frameLength > 0 else { throw ImportError.empty }

        // Scoped so the file is finalized (closed) before the caller reads it.
        do {
            let output = try AVAudioFile(forWriting: destination, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: outputSampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: outputBitRate,
            ])
            try output.write(from: outBuffer)
        }

        return Result(seconds: Double(outBuffer.frameLength) / outputSampleRate, wasTrimmed: wasTrimmed)
    }
}
