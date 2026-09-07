import SwiftUI

struct AudioRecorderView: View {
    @StateObject private var vm = AudioRecorderViewModel()
    @State private var showBirdInfo = false
    @State private var showAIReview = false
    @State private var showAnnotate = false
    @State private var pendingVerdict: AIVerdict?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                waveformSection
                controlSection
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
        .onDisappear { vm.stopLocationUpdates() }
        .onChange(of: vm.aiSuggestion) { _, species in
            guard species != nil, !vm.isAnalyzing else { return }
            showAIReview = true
        }
        .alert("Sound Submitted!", isPresented: $vm.uploadSuccess) {
            Button("Great!") { vm.reset() }
        } message: {
            Text("Your recording has been added to the map. We couldn't analyze it in time, but you can still annotate it from the sighting later.")
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
                    Text("Tap record to capture bird sounds")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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
        }
    }

    @ViewBuilder
    private var uploadSection: some View {
        VStack(spacing: 14) {
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
