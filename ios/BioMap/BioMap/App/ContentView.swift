import SwiftUI

struct ContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.colorScheme) private var scheme
    @State private var tab: Tab = .map
    @State private var reportMode: ReportTabView.ReportMode = .photo

    enum Tab { case map, report, leaders, profile }

    init() {
        // Brand color on the tab bar and nav bars app-wide (see Theme.swift),
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
        let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let largeFont = UIFont.systemFont(ofSize: 34, weight: .bold)
        nav.titleTextAttributes = [.foregroundColor: UIColor(c.fg), .font: titleFont]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(c.fg), .font: largeFont]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        TabView(selection: $tab) {
            SightingMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(Tab.map)

            ReportTabView(mode: $reportMode)
                .tabItem { Label("Report", systemImage: "camera.fill") }
                .tag(Tab.report)

            LeaderboardView()
                .tabItem { Label("Leaders", systemImage: "trophy.fill") }
                .tag(Tab.leaders)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(Tab.profile)
        }
        .tint(c.accent)
        .onAppear { consume(env.pendingDeepLink) }
        .onChange(of: env.pendingDeepLink) { _, link in consume(link) }
    }

    /// Jump to wherever a widget / lock-screen control asked for, then clear the request.
    private func consume(_ link: DeepLink?) {
        guard let link else { return }
        switch link {
        case .photo: reportMode = .photo; tab = .report
        case .sound: reportMode = .audio; tab = .report
        case .map: tab = .map
        }
        env.pendingDeepLink = nil
    }
}

struct ReportTabView: View {
    @Binding var mode: ReportMode
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
    FirebasePreview { ReportTabView(mode: .constant(.photo)) }
}
