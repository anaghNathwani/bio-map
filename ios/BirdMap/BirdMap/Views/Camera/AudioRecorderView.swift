import SwiftUI
import UniformTypeIdentifiers

struct AudioRecorderView: View {
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
                        ProgressView()
                        Text("Preparing your audio file…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                if vm.recordingURL == nil, let err = vm.error {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                if let notice = vm.importNotice, vm.recordingURL != nil {
                    Label(notice, systemImage: "scissors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        if vm.isIdentifying {
            HStack(spacing: 10) {
                ProgressView()
                Text("Identifying bird calls…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        } else if let results = vm.identification {
            VStack(alignment: .leading, spacing: 10) {
                Label("On-Device AI · BirdNET", systemImage: "cpu.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.indigo)

                if results.isEmpty {
                    Label("Couldn't confidently identify a bird", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Text("No bird call in this recording was clear enough to name. Recording closer to the bird, away from wind and voices, helps. You can still submit it and add your own ID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        HStack {
                            Text(result.species)
                                .font(index == 0 ? .subheadline.weight(.semibold) : .subheadline)
                            Spacer()
                            Text("\(Int(result.confidence * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !vm.identificationUsedLocation {
                    Text("No GPS fix yet, so this was matched against every species worldwide and held to a stricter standard.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        } else if let failure = vm.identificationError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't identify this recording")
                        .font(.subheadline.weight(.semibold))
                    Text("\(failure). You can still submit it — our server will try again later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Retry") { vm.identifyRecording() }
                    .font(.caption.weight(.semibold))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private var analyzingSection: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Analyzing your recording…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var waveformSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(
                    colors: [Color.indigo.opacity(0.13), Color.purple.opacity(0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(height: 180)

            if vm.isRecording {
                WaveformView(level: vm.meterLevel)
                    .frame(height: 80)
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.indigo.opacity(0.6))
                        .symbolEffect(.pulse)
                    Text(vm.hasRecording
                         ? "Recording ready · \(formatTime(vm.recordingSeconds))"
                         : "Tap record to capture bird sounds, or upload a file")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
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
                            Circle().fill(.red).frame(width: 8, height: 8)
                                .symbolEffect(.pulse)
                            Text("\(formatTime(vm.recordingSeconds)) / \(formatTime(AudioRecorderViewModel.maxRecordingSeconds))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
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
        VStack(spacing: 16) {
            Button {
                playback.stop()
                if vm.isRecording { vm.stopRecording() } else { vm.startRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(vm.isRecording ? Color.red : Color.indigo)
                        .frame(width: 72, height: 72)
                        .shadow(color: (vm.isRecording ? Color.red : Color.indigo).opacity(0.4), radius: 10, y: 4)
                    Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(vm.isRecording ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: vm.isRecording)

            Text(vm.isRecording ? "Recording… tap to stop" : "Tap to record")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !vm.isRecording {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Upload an audio file", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.indigo.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.indigo)
                }
                .disabled(vm.isImporting || vm.isUploading)
            }
        }
    }

    @ViewBuilder
    private var uploadSection: some View {
        VStack(spacing: 14) {
            // Listen back before submitting
            Button {
                if let url = vm.recordingURL { playback.toggle(fileURL: url) }
            } label: {
                Label(playback.isPlaying ? "Pause" : "Listen back",
                      systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.indigo)
            }
            .disabled(vm.isRecording || vm.isUploading)
            .padding(.horizontal)

            if playback.failed {
                Text("Couldn't play this recording back.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Notes
            TextField("Notes (optional)", text: $vm.notes, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

            if let err = vm.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    Text(err)
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }

            Button {
                Task { await vm.upload() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isUploading { ProgressView().tint(.white) }
                    else { Image(systemName: "paperplane.fill") }
                    Text(vm.isUploading ? "Uploading…" : "Submit Sound Sighting")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(vm.isUploading ? Color.gray : Color.indigo, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(vm.isUploading || vm.isRecording)
            .padding(.horizontal)
        }
    }

    private func formatTime(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct WaveformView: View {
    let level: Float
    private let barCount = 28

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                let phase = Double(i) / Double(barCount)
                let amp = max(0.08, Double(level) * (0.4 + 0.6 * abs(sin(phase * .pi * 3 + Date().timeIntervalSince1970 * 6))))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.indigo.opacity(0.7 + 0.3 * amp))
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
