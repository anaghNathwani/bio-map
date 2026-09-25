import SwiftUI

struct ContentView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        TabView {
            SightingMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }

            ReportTabView()
                .tabItem { Label("Report", systemImage: "camera.fill") }

            LeaderboardView()
                .tabItem { Label("Leaders", systemImage: "trophy.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(.teal)
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

#Preview("ContentView") {
    FirebasePreview { ContentView().environmentObject(AppEnvironment()) }
}

#Preview("ReportTabView") {
    FirebasePreview { ReportTabView() }
}
