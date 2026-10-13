import SwiftUI
import CoreLocation
import AVKit
import AVFoundation

struct SightingDetailView: View {
    @Environment(\.colorScheme) private var scheme
    let sightingID: String
    /// True when pushed from a list inside an existing NavigationStack (the
    /// pin's sightings list, the saved list) — nesting a second stack there
    /// breaks the back button, so the stack is only created when standalone.
    var embedded = false
    @State private var detail: SightingDetail?
    @State private var isLoading = true
    @State private var showAnnotate = false
    @State private var showBirdInfo = false
    @State private var locationName: String?
    @StateObject private var playback = AudioPlayback()
    @ObservedObject private var saved = SavedSightings.shared

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        Group {
            if isLoading {
                BioLoader(size: 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ThemeColors(scheme: scheme).bg)
            } else if let detail {
                detailContent(detail)
            }
        }
        .navigationTitle("Sighting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    saved.toggle(sightingID)
                } label: {
                    Label(saved.isSaved(sightingID) ? "Unsave" : "Save",
                          systemImage: saved.isSaved(sightingID) ? "bookmark.fill" : "bookmark")
                }
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
        .onDisappear { playback.stop() }
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
        .background(ThemeColors(scheme: scheme).bg)
    }

    @ViewBuilder
    private func photoHeader(_ detail: SightingDetail) -> some View {
        let c = ThemeColors(scheme: scheme)
        ZStack(alignment: .bottom) {
            if detail.isAudio {
                // Audio sighting — show waveform placeholder + player
                Rectangle()
                    .fill(c.fg)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundStyle(c.accent)
                            if detail.audioURL != nil || detail.audioFallbackURL != nil {
                                Button {
                                    Task { await togglePlayback(detail) }
                                } label: {
                                    Label(playback.isPlaying ? "Pause" : "Play recording",
                                          systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(Theme.sansSemibold(15))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .overlay(Capsule().strokeBorder(c.bg.opacity(0.5), lineWidth: 1.4))
                                        .foregroundStyle(c.bg)
                                }
                                if playback.failed {
                                    Text("Couldn't play this recording.")
                                        .font(Theme.sans(12))
                                        .foregroundStyle(c.bg.opacity(0.85))
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
                        Rectangle().fill(c.bgRaised)
                            .overlay(Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).foregroundStyle(c.fgSoft))
                    default:
                        Rectangle().fill(c.bgRaised).overlay(ProgressView().tint(c.accent))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220, maxHeight: 380)
                .clipped()
            }

            LinearGradient(colors: [.clear, Color.black.opacity(0.5)], startPoint: .center, endPoint: .bottom)

            if let species = detail.aiSpeciesSuggestion {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.isAudio ? "BirdNET ID" : "Suggestion")
                            .font(Theme.sansSemibold(10)).tracking(1.2).foregroundStyle(c.accent)
                        Text(species).font(Theme.display(18, medium: true)).foregroundStyle(c.bg)
                    }
                    Spacer()
                    if let conf = detail.aiConfidence {
                        Text("\(Int(conf * 100))%").font(Theme.display(19, medium: true)).foregroundStyle(confidenceColor(conf))
                    }
                    Button("Info") { showBirdInfo = true }
                        .font(Theme.sansSemibold(12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(c.bg.opacity(0.5), lineWidth: 1.4))
                        .foregroundStyle(c.bg)
                }
                .padding(14)
                .background(c.fg.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(12)
            } else if detail.isAudio {
                // New recordings are identified on-device at submission, so
                // "analyzed but nothing found" is a real answer; anything not yet
                // analyzed (older sightings, or a device where analysis couldn't
                // run) waits for the scheduled server job (ml_pipeline/live_poll.py,
                // which GitHub runs every few hours, not on a tight interval).
                HStack(spacing: 10) {
                    Image(systemName: detail.aiAnalyzed ? "questionmark.circle" : "clock.arrow.circlepath")
                        .foregroundStyle(c.bg.opacity(0.85))
                    Text(detail.aiAnalyzed
                         ? "No bird was identified with confidence in this recording."
                         : "Identification pending — our server processes recordings every few hours.")
                        .font(Theme.sansMedium(12))
                        .foregroundStyle(c.bg)
                    Spacer()
                }
                .padding(14)
                .background(c.fg.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ detail: SightingDetail) -> some View {
        let c = ThemeColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 12) {
            if let notes = detail.notes, !notes.isEmpty {
                Text(notes)
                    .font(Theme.sans(15))
                    .foregroundStyle(c.fg)
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill").foregroundStyle(c.accent)
                if let name = locationName {
                    Text(name).font(Theme.sans(12)).foregroundStyle(c.fgSoft)
                } else {
                    Text(String(format: "%.4f, %.4f", detail.latitude, detail.longitude))
                        .font(Theme.sans(12)).foregroundStyle(c.fgSoft).monospaced()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(c.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
    }

    @ViewBuilder
    private func annotationsSection(_ detail: SightingDetail) -> some View {
        let c = ThemeColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Community annotations").font(Theme.display(17, medium: true)).foregroundStyle(c.fg)
                Spacer()
                Text("\(detail.annotations.count)")
                    .font(Theme.sansSemibold(12))
                    .foregroundStyle(c.bg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(c.fg, in: Capsule())
            }

            if detail.annotations.isEmpty {
                VStack(spacing: 10) {
                    BirdMark()
                        .stroke(c.fgSoft, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 40, height: 40)
                    Text("No annotations yet")
                        .font(Theme.sansMedium(14))
                        .foregroundStyle(c.fgSoft)
                    Text("Be the first to identify this bird.")
                        .font(Theme.sans(12))
                        .foregroundStyle(c.fgSoft.opacity(0.8))
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
                Label("Add your annotation", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
        }
        .padding(16)
        .background(c.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
    }

    private func annotationCard(_ ann: AnnotationItem) -> some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().strokeBorder(c.rule, lineWidth: 1.5).frame(width: 36, height: 36)
                Text(String(ann.username.prefix(1)).uppercased())
                    .font(Theme.sansSemibold(14))
                    .foregroundStyle(c.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(ann.species.isEmpty ? "Marked unsure" : ann.species)
                        .font(Theme.sansSemibold(14))
                        .foregroundStyle(ann.species.isEmpty ? c.fgSoft : c.fg)
                        .italic(ann.species.isEmpty)
                    // Judged on this device (see AnnotationModerator), not by the server.
                    if AnnotationModerator.shared.verdict(species: ann.species, reviewOfAI: ann.reviewOfAI).isFlagged {
                        Label("Flagged", systemImage: "flag.fill")
                            .font(Theme.sansSemibold(10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85), in: Capsule())
                    }
                    Spacer()
                    confidenceBadge(ann.confidence)
                }
                if let behavior = ann.behavior {
                    Label(behavior, systemImage: "binoculars")
                        .font(Theme.sans(12))
                        .foregroundStyle(c.fgSoft)
                }
                Text("by \(ann.username)")
                    .font(Theme.sans(11))
                    .foregroundStyle(c.fgSoft.opacity(0.75))
            }
        }
        .padding(12)
        .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    /// Plays the embedded recording, or downloads the Supabase fallback copy
    /// if the embedded one is missing/undecodable.
    private func togglePlayback(_ detail: SightingDetail) async {
        if playback.isPlaying { playback.stop(); return }
        if let embedded = detail.audioURL, let data = DataURI.decode(embedded) {
            playback.play(data: data)
        } else if let fallback = detail.audioFallbackURL, let url = URL(string: fallback),
                  let (data, _) = try? await URLSession.shared.data(from: url) {
            playback.play(data: data)
        } else {
            playback.play(data: Data())     // surfaces the "couldn't play" message
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

#Preview {
    FirebasePreview { SightingDetailView(sightingID: "preview") }
}
