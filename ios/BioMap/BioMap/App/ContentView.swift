import SwiftUI

struct ContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.colorScheme) private var scheme

    init() {
        // Brand type/color on the tab bar and nav bars app-wide (paper/ink/clay — see Theme.swift),
        // set once via UIKit appearance since SwiftUI's TabView styling can't reach every state.
        let c = ThemeColors(scheme: UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light)
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(c.bg)
        tab.shadowColor = UIColor(c.rule)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(c.bg)
        nav.shadowColor = UIColor(c.rule)
        let titleFont = UIFont(name: "FrauncesBioMap-Regular", size: 19) ?? .systemFont(ofSize: 19)
        let largeFont = UIFont(name: "FrauncesBioMapDisplay-Medium", size: 32) ?? .systemFont(ofSize: 32)
        nav.titleTextAttributes = [.foregroundColor: UIColor(c.fg), .font: titleFont]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(c.fg), .font: largeFont]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }

    var body: some View {
        let c = ThemeColors(scheme: scheme)
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
        .tint(c.accent)
    }
}

struct ReportTabView: View {
    @State private var mode: ReportMode = .photo
    @Environment(\.colorScheme) private var scheme

    enum ReportMode { case photo, audio }

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    segment("Photo", systemImage: "camera.fill", isOn: mode == .photo) { mode = .photo }
                    segment("Sound", systemImage: "waveform", isOn: mode == .audio) { mode = .audio }
                }
                .padding(4)
                .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .background(c.bg)
        }
    }

    @ViewBuilder
    private func segment(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        let c = ThemeColors(scheme: scheme)
        Button(action: { withAnimation(.easeOut(duration: 0.18)) { action() } }) {
            Label(title, systemImage: systemImage)
                .font(Theme.sansSemibold(15))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(isOn ? c.bg : c.fg)
                .background(isOn ? c.fg : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}

#Preview("ContentView") {
    FirebasePreview { ContentView().environmentObject(AppEnvironment()) }
}

#Preview("ReportTabView") {
    FirebasePreview { ReportTabView() }
}
