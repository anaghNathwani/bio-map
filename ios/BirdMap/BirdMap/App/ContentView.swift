import SwiftUI

struct ContentView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        TabView {
            SightingMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }

            CameraView()
                .tabItem { Label("Report", systemImage: "camera.fill") }

            LeaderboardView()
                .tabItem { Label("Leaders", systemImage: "trophy.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Text(env.username ?? "Unknown")
                }
                Section {
                    Button("Sign Out", role: .destructive) { env.logout() }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
