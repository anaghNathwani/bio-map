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

struct ProfileView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var showSignOutConfirm = false

    private var initials: String {
        guard let name = env.username, !name.isEmpty else { return "?" }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.teal, Color.teal.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                            Text(initials)
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(env.username ?? "Unknown")
                                .font(.title3.bold())
                            Text("BirdMap member")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("About") {
                    Label("Citizen science bird tracking", systemImage: "globe")
                    Label("Community annotations", systemImage: "person.3")
                    Label("On-device AI identification", systemImage: "sparkles")
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog("Sign out of BirdMap?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { env.logout() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
