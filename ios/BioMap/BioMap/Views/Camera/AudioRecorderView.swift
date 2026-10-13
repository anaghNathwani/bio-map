import SwiftUI
import UniformTypeIdentifiers

struct AudioRecorderView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var vm = AudioRecorderViewModel()
    @StateObject private var playback = AudioPlayback()
    @State private var showBirdInfo = false
    @State private var showFileImporter = false
    @State private var showAIReview = false
    @State private var showAnnotate = false
    @State private var pendingVerdict: AIVerdict?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                waveformSection
                controlSection
                if vm.isImporting {
                    HStack(spacing: 10) {
                        ProgressView().tint(ThemeColors(scheme: scheme).accent)
                        Text("Preparing your audio file…")
                            .font(Theme.sans(14))
                            .foregroundStyle(ThemeColors(scheme: scheme).fgSoft)
                        Spacer()
                    }
                    .padding(14)
                    .background(ThemeColors(scheme: scheme).bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)
                }
                if vm.recordingURL == nil, let err = vm.error {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.sans(13))
                        .foregroundStyle(ThemeColors(scheme: scheme).accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                if let notice = vm.importNotice, vm.recordingURL != nil {
                    Label(notice, systemImage: "scissors")
                        .font(Theme.sans(13))
                        .foregroundStyle(ThemeColors(scheme: scheme).fgSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                if vm.recordingURL != nil && !vm.isRecording {
                    identificationSection
                }
                if vm.recordingURL != nil {
                    uploadSection
                }
                if vm.isAnalyzing {
                    analyzingSection
                }
                if let sightingID = vm.lastUploadedSightingID {
                    AdditionalBirdsSection(sightingID: sightingID, candidates: vm.aiAdditionalSuggestions)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(ThemeColors(scheme: scheme).bg)
        .onAppear { vm.startLocationUpdates() }
        .onDisappear {
            vm.stopLocationUpdates()
            playback.stop()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                playback.stop()
                Task { await vm.importAudio(from: url) }
            case .failure(let error):
                vm.error = "Couldn't open that file: \(error.localizedDescription)"
            }
        }
        .onChange(of: vm.aiSuggestion) { _, species in
            guard species != nil, !vm.isAnalyzing else { return }
            showAIReview = true
        }
        .alert("Sound Submitted!", isPresented: $vm.uploadSuccess) {
            Button("Great!") { vm.reset() }
        } message: {
            if vm.noBirdDetected {
                Text("Your recording has been added to the map. The on-device model didn't hear a bird clearly enough to name one — you can still add your own ID from the sighting.")
            } else {
                Text("Your recording has been added to the map. Identification couldn't run on this device, so our server will fill it in the next time it processes recordings (that can take a few hours) — or add your own ID from the sighting.")
            }
        }
        .sheet(isPresented: $showBirdInfo) {
            if let species = vm.aiSuggestion {
                BirdInfoView(species: species)
            }
        }
        .sheet(isPresented: $showAIReview) {
            if let species = vm.aiSuggestion {
                aiReviewSheet(species: species, confidence: vm.aiConfidence ?? 0.5)
            }
        }
        .sheet(isPresented: $showAnnotate, onDismiss: { vm.reset() }) {
            if let sightingID = vm.lastUploadedSightingID {
                AnnotationView(
                    sightingID: sightingID,
                    initialSpecies: pendingVerdict == .confirmed ? (vm.aiSuggestion ?? "") : "",
                    initialConfidence: pendingVerdict == .confirmed ? 0.95 : 0.6,
                    reviewOfAI: pendingVerdict?.reviewOfAI
                ) {
                    showAnnotate = false
                }
            }
        }
    }

    private func aiReviewSheet(species: String, confidence: Double) -> some View {
        VStack {
            Spacer()
            AIPredictionCard(species: species, confidence: confidence) { verdict in
                pendingVerdict = verdict
                showAIReview = false
                showAnnotate = true
            }
            Spacer()
        }
        .presentationDetents([.medium])
    }

    /// What BirdNET made of the take, shown before submitting — mirrors the
    /// photo screen's on-device suggestions panel.
    @ViewBuilder
    private var identificationSection: some View {
        let c = ThemeColors(scheme: scheme)
        if vm.isIdentifying {
            HStack(spacing: 10) {
                ProgressView().tint(c.accent)
                Text("Identifying bird calls…")
                    .font(Theme.sans(14))
                    .foregroundStyle(c.fgSoft)
                Spacer()
            }
            .padding(14)
            .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
        } else if let results = vm.identification {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "On-device · BirdNET")

                if results.isEmpty {
                    Text("Couldn't confidently identify a bird")
                        .font(Theme.sansSemibold(14)).foregroundStyle(c.fg)
                    Text("No bird call in this recording was clear enough to name. Recording closer to the bird, away from wind and voices, helps. You can still submit it and add your own ID.")
                        .font(Theme.sans(12))
                        .foregroundStyle(c.fgSoft)
                } else {
                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        HStack {
                            Text(result.species)
                                .font(index == 0 ? Theme.sansSemibold(14) : Theme.sans(14))
                                .foregroundStyle(c.fg)
                            Spacer()
                            Text("\(Int(result.confidence * 100))%")
                                .font(Theme.sansMedium(13))
                                .foregroundStyle(c.fgSoft)
                        }
                    }
                }

                if !vm.identificationUsedLocation {
                    Text("No GPS fix yet, so this was matched against every species worldwide and held to a stricter standard.")
                        .font(Theme.sans(11))
                        .foregroundStyle(c.fgSoft.opacity(0.8))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
            .padding(.horizontal)
        } else if let failure = vm.identificationError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(c.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't identify this recording")
                        .font(Theme.sansSemibold(14)).foregroundStyle(c.fg)
                    Text("\(failure). You can still submit it — our server will try again later.")
                        .font(Theme.sans(12))
                        .foregroundStyle(c.fgSoft)
                }
                Spacer()
                Button("Retry") { vm.identifyRecording() }
                    .font(Theme.sansSemibold(13))
                    .foregroundStyle(c.accent)
            }
            .padding(14)
            .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
        }
    }

    private var analyzingSection: some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 10) {
            ProgressView().tint(c.accent)
            Text("Analyzing your recording…")
                .font(Theme.sans(14))
                .foregroundStyle(c.fgSoft)
        }
        .padding(14)
        .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private var waveformSection: some View {
        let c = ThemeColors(scheme: scheme)
        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(c.bgRaised)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
                .frame(height: 180)

            if vm.isRecording {
                WaveformView(level: vm.meterLevel)
                    .frame(height: 80)
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(c.accent)
                    Text(vm.hasRecording
                         ? "Recording ready · \(formatTime(vm.recordingSeconds))"
                         : "Tap record to capture bird sounds, or upload a file")
                        .font(Theme.sans(14))
                        .foregroundStyle(c.fgSoft)
                        .multilineTextAlignment(.center)
                }
            }

            if vm.hasRecording && !vm.isRecording {
                VStack {
                    HStack {
                        Button {
                            playback.stop()
                            vm.retake()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.headline)
                                .foregroundStyle(c.bg)
                                .frame(width: 40, height: 40)
                                .background(c.fg.opacity(0.72), in: Circle())
                        }
                        .disabled(vm.isUploading)
                        .accessibilityLabel("Discard recording and record again")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }

            if vm.isRecording {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(c.accent).frame(width: 8, height: 8)
                            Text("\(formatTime(vm.recordingSeconds)) / \(formatTime(AudioRecorderViewModel.maxRecordingSeconds))")
                                .font(Theme.sansMedium(12))
                                .foregroundStyle(c.bg)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(c.fg.opacity(0.8), in: Capsule())
                        .padding(12)
                    }
                    Spacer()
                }
            }
        }
        .frame(height: 180)
        .padding(.horizontal)
    }

    private var controlSection: some View {
        let c = ThemeColors(scheme: scheme)
        return VStack(spacing: 16) {
            Button {
                playback.stop()
                if vm.isRecording { vm.stopRecording() } else { vm.startRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(vm.isRecording ? c.accent : c.fg)
                        .frame(width: 72, height: 72)
                    Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(c.bg)
                }
            }
            .scaleEffect(vm.isRecording ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: vm.isRecording)

            Text(vm.isRecording ? "Recording… tap to stop" : "Tap to record")
                .font(Theme.sans(13))
                .foregroundStyle(c.fgSoft)

            if !vm.isRecording {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Upload an audio file", systemImage: "square.and.arrow.up")
                        .font(Theme.sansMedium(14))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .overlay(Capsule().strokeBorder(c.fg, lineWidth: 1.4))
                        .foregroundStyle(c.fg)
                }
                .disabled(vm.isImporting || vm.isUploading)
            }
        }
    }

    @ViewBuilder
    private var uploadSection: some View {
        let c = ThemeColors(scheme: scheme)
        VStack(spacing: 14) {
            // Listen back before submitting
            Button {
                if let url = vm.recordingURL { playback.toggle(fileURL: url) }
            } label: {
                Label(playback.isPlaying ? "Pause" : "Listen back",
                      systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(Theme.sansSemibold(15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(c.fg)
            }
            .disabled(vm.isRecording || vm.isUploading)
            .padding(.horizontal)

            if playback.failed {
                Text("Couldn't play this recording back.")
                    .font(Theme.sans(13))
                    .foregroundStyle(c.accent)
            }

            // Notes
            TextField("Notes (optional)", text: $vm.notes, axis: .vertical)
                .font(Theme.sans(15))
                .lineLimit(2...4)
                .padding(12)
                .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)

            if let err = vm.error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                }
                .font(Theme.sans(13))
                .foregroundStyle(c.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }

            Button {
                Task { await vm.upload() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isUploading { ProgressView() }
                    else { Image(systemName: "paperplane.fill") }
                    Text(vm.isUploading ? "Uploading…" : "Submit sound sighting")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(vm.isUploading || vm.isRecording)
            .padding(.horizontal)
        }
    }

    private func formatTime(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct WaveformView: View {
    @Environment(\.colorScheme) private var scheme
    let level: Float
    private let barCount = 28

    var body: some View {
        let clay = ThemeColors(scheme: scheme).accent
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                let phase = Double(i) / Double(barCount)
                let amp = max(0.08, Double(level) * (0.4 + 0.6 * abs(sin(phase * .pi * 3 + Date().timeIntervalSince1970 * 6))))
                RoundedRectangle(cornerRadius: 2)
                    .fill(clay.opacity(0.7 + 0.3 * amp))
                    .frame(width: 3, height: CGFloat(amp) * 60 + 4)
                    .animation(.easeInOut(duration: 0.05), value: level)
            }
        }
    }
}

#Preview("AudioRecorderView") {
    FirebasePreview { AudioRecorderView() }
}

#Preview("WaveformView") {
    WaveformView(level: 0.6)
        .frame(height: 60)
        .padding()
}
