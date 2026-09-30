import SwiftUI
import UserNotifications

private let baseURL = "https://birdmap-citizenscience.web.app"

struct ProfileView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var notificationsEnabled = false
    @State private var isEditingUsername = false
    @State private var draftUsername = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showLogoutConfirm = false
    @State private var safariURL: URL?

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        NavigationStack {
            List {
                // MARK: - Account header
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().strokeBorder(c.rule, lineWidth: 1.5).frame(width: 56, height: 56)
                            BirdMark()
                                .stroke(c.clay, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 26, height: 26)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(env.username ?? "No username set")
                                .font(Theme.sansSemibold(16))
                                .foregroundStyle(c.ink)
                            if let email = env.user?.email {
                                Text(email)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(c.inkSoft)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(c.paper)
                } header: {
                    Text("Account")
                }

                // MARK: - Profile
                Section {
                    Button {
                        draftUsername = env.username ?? ""
                        saveError = nil
                        isEditingUsername = true
                    } label: {
                        HStack {
                            Label("Username", systemImage: "person.fill")
                            Spacer()
                            Text(env.username ?? "Not set")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .listRowBackground(c.paper)
                } header: {
                    Text("Profile")
                }

                // MARK: - Appearance
                Section {
                    Picker(selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                    .tint(c.clay)
                    .listRowBackground(c.paper)
                } header: {
                    Text("Display")
                }

                // MARK: - Notifications
                Section {
                    HStack {
                        Label("Push Notifications", systemImage: "bell.fill")
                        Spacer()
                        Toggle("", isOn: $notificationsEnabled)
                            .labelsHidden()
                            .tint(c.clay)
                            .onChange(of: notificationsEnabled) { _, enabled in
                                if enabled {
                                    requestNotificationPermission()
                                } else {
                                    openAppSettings()
                                }
                            }
                    }
                    .listRowBackground(c.paper)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Receive alerts when your sightings are annotated by the community.")
                }

                // MARK: - About
                Section {
                    aboutRow("Citizen science bird tracking", icon: "globe", path: "/citizen-science")
                    aboutRow("Community annotations", icon: "person.3.fill", path: "/community")
                    aboutRow("On-device AI identification", icon: "sparkles", path: "/ai")
                    aboutRow("Terms of Service", icon: "doc.text.fill", path: "/terms")
                } header: {
                    Text("About")
                }

                // MARK: - Sign out
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .listRowBackground(c.paper)
                }
            }
            .scrollContentBackground(.hidden)
            .background(c.paper)
            .navigationTitle("Profile")
            .sheet(isPresented: $isEditingUsername) {
                editUsernameSheet
            }
            .sheet(item: $safariURL) { url in
                SafariView(url: url)
                    .ignoresSafeArea()
            }
            .confirmationDialog("Sign out of BirdMap?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { env.logout() }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                if let name = await FirebaseService.shared.fetchUsername() {
                    env.saveUsername(name)
                }
                await refreshNotificationStatus()
            }
        }
    }

    // MARK: - Edit username sheet

    private var editUsernameSheet: some View {
        let c = ThemeColors(scheme: scheme)
        return NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $draftUsername)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .listRowBackground(c.paper)
                } header: {
                    Text("Choose a username")
                } footer: {
                    Text("Your username appears on the leaderboard and sighting posts.")
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(c.clay)
                            .font(Theme.sans(12))
                            .listRowBackground(c.paper)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(c.paper)
            .navigationTitle("Edit Username")
            .navigationBarTitleDisplayMode(.inline)
            .tint(c.clay)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingUsername = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveUsername() }
                    }
                    .disabled(draftUsername.trimmingCharacters(in: .whitespaces).count < 2 || isSaving)
                    .overlay {
                        if isSaving { ProgressView().scaleEffect(0.8) }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func saveUsername() async {
        let trimmed = draftUsername.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            saveError = "Username must be at least 2 characters"
            return
        }
        isSaving = true
        saveError = nil
        do {
            try await FirebaseService.shared.updateUsername(trimmed)
            env.saveUsername(trimmed)
            isEditingUsername = false
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { notificationsEnabled = granted }
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @ViewBuilder
    private func aboutRow(_ title: String, icon: String, path: String) -> some View {
        Button {
            if let url = URL(string: baseURL + path) { safariURL = url }
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .listRowBackground(ThemeColors(scheme: scheme).paper)
    }
}

#Preview {
    FirebasePreview { ProfileView().environmentObject(AppEnvironment()) }
}
