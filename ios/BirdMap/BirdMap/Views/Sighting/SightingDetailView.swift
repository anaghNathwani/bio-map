import SwiftUI
import CoreLocation
import AVKit

struct SightingDetailView: View {
    let sightingID: String
    @State private var detail: SightingDetail?
    @State private var isLoading = true
    @State private var showAnnotate = false
    @State private var showBirdInfo = false
    @State private var locationName: String?
    @State private var audioPlayer: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail {
                    detailContent(detail)
                }
            }
            .navigationTitle("Sighting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAnnotate = true
                    } label: {
                        Label("Annotate", systemImage: "checklist.unchecked")
                    }
                    .disabled(detail == nil)
                }
            }
            .sheet(isPresented: $showAnnotate) {
                if let detail {
                    AnnotationView(sightingID: detail.id) {
                        showAnnotate = false
                        Task { await loadDetail() }
                    }
                }
            }
            .sheet(isPresented: $showBirdInfo) {
                if let species = detail?.displaySpecies {
                    BirdInfoView(species: species)
                }
            }
            .task { await loadDetail() }
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: SightingDetail) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                photoHeader(detail)

                if !detail.additionalSpecies.isEmpty {
                    AdditionalBirdsSection(sightingID: detail.id, candidates: detail.additionalSpecies)
                }

                VStack(alignment: .leading, spacing: 16) {
                    metadataSection(detail)
                    annotationsSection(detail)
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func photoHeader(_ detail: SightingDetail) -> some View {
        ZStack(alignment: .bottom) {
            if detail.isAudio {
                // Audio sighting — show waveform placeholder + player
                Rectangle()
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.6), Color.purple.opacity(0.4)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.and.mic")
                                .font(.system(size: 56))
                                .foregroundStyle(.white.opacity(0.8))
                            if detail.audioURL != nil || detail.audioFallbackURL != nil {
                                Button {
                                    if audioPlayer == nil {
                                        let fromPrimary = detail.audioURL.flatMap { DataURI.writeTempFile($0, extension: "m4a") }
                                        let fromFallback = detail.audioFallbackURL.flatMap { URL(string: $0) }
                                        if let audioURL = fromPrimary ?? fromFallback {
                                            audioPlayer = AVPlayer(url: audioURL)
                                        }
                                    }
                                    audioPlayer?.play()
                                } label: {
                                    Label("Play Recording", systemImage: "play.circle.fill")
                                        .font(.headline)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    )
            } else if let uiImage = detail.photoURL.flatMap(DataURI.decode).flatMap(UIImage.init(data:)) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 220, maxHeight: 380)
                    .clipped()
            } else {
                AsyncImage(url: detail.photoFallbackURL.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Rectangle().fill(Color(.secondarySystemBackground))
                            .overlay(Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary))
                    default:
                        Rectangle().fill(Color(.secondarySystemBackground)).overlay(ProgressView())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220, maxHeight: 380)
                .clipped()
            }

            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

            if let species = detail.aiSpeciesSuggestion {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").symbolRenderingMode(.multicolor).font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.isAudio ? "BirdNET ID" : "AI Suggestion")
                            .font(.caption2).foregroundStyle(.white.opacity(0.72))
                        Text(species).font(.headline).foregroundStyle(.white)
                    }
                    Spacer()
                    if let conf = detail.aiConfidence {
                        Text("\(Int(conf * 100))%").font(.title3.bold()).foregroundStyle(confidenceColor(conf))
                    }
                    Button("Info") { showBirdInfo = true }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.teal.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ detail: SightingDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notes = detail.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill").symbolRenderingMode(.multicolor)
                if let name = locationName {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(String(format: "%.4f, %.4f", detail.latitude, detail.longitude))
                        .font(.caption).foregroundStyle(.secondary).monospaced()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func annotationsSection(_ detail: SightingDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Community Annotations", systemImage: "person.3.sequence.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.headline)
                Spacer()
                Text("\(detail.annotations.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.teal, in: Capsule())
            }

            if detail.annotations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.sequence")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No annotations yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Be the first to identify this bird!")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                VStack(spacing: 8) {
                    ForEach(detail.annotations) { ann in
                        annotationCard(ann)
                    }
                }
            }

            Button {
                showAnnotate = true
            } label: {
                Label("Add Your Annotation", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.teal)
                    .fontWeight(.medium)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func annotationCard(_ ann: AnnotationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(ann.username.prefix(1)).uppercased())
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.teal)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(ann.species.isEmpty ? "Marked unsure" : ann.species)
                        .font(.subheadline.bold())
                        .foregroundStyle(ann.species.isEmpty ? .secondary : .primary)
                        .italic(ann.species.isEmpty)
                    if ann.moderation == "flagged" {
                        Label("Flagged", systemImage: "flag.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85), in: Capsule())
                    }
                    Spacer()
                    confidenceBadge(ann.confidence)
                }
                if let behavior = ann.behavior {
                    Label(behavior, systemImage: "binoculars.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("by \(ann.username)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption.bold())
            .foregroundStyle(confidenceColor(confidence))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(confidenceColor(confidence).opacity(0.15), in: Capsule())
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...: return .green
        case 0.5...: return .orange
        default: return .red
        }
    }

    private func loadDetail() async {
        isLoading = true
        detail = try? await FirebaseService.shared.fetchSightingDetail(id: sightingID)
        isLoading = false
        if let d = detail {
            await reverseGeocode(lat: d.latitude, lng: d.longitude)
        }
    }

    private func reverseGeocode(lat: Double, lng: Double) async {
        let location = CLLocation(latitude: lat, longitude: lng)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        let parts = [placemark.locality, placemark.administrativeArea].compactMap { $0 }
        if !parts.isEmpty { locationName = parts.joined(separator: ", ") }
    }
}
