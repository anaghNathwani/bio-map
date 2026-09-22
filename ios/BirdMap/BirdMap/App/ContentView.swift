import SwiftUI

struct ContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @AppStorage("hasSeenTour") private var hasSeenTour = false
    @State private var selectedTab: AppTab = .map

    var body: some View {
        TabView(selection: $selectedTab) {
            SightingMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(AppTab.map)

            ReportTabView()
                .tabItem { Label("Report", systemImage: "camera.fill") }
                .tag(AppTab.report)

            LeaderboardView()
                .tabItem { Label("Leaders", systemImage: "trophy.fill") }
                .tag(AppTab.leaders)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
        .tint(.teal)
        .overlay {
            if env.tourActive {
                GuidedTourOverlay(selectedTab: $selectedTab, onFinish: finishTour)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: env.tourActive)
        .task {
            // First launch: start the tour once the map and its permission prompt have settled.
            guard !hasSeenTour else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { env.tourActive = true }
        }
    }

    private func finishTour() {
        hasSeenTour = true
        env.tourActive = false
        selectedTab = .map
    }
}

struct ReportTabView: View {
    @State private var mode: ReportMode = .photo

    enum ReportMode { case photo, audio }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Label("Photo", systemImage: "camera.fill").tag(ReportMode.photo)
                    Label("Audio", systemImage: "waveform.and.mic").tag(ReportMode.audio)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)

                if mode == .photo {
                    CameraView()
                        .navigationTitle("Report Sighting")
                } else {
                    AudioRecorderView()
                        .navigationTitle("Record Bird Sound")
                }
            }
        }
    }
}
