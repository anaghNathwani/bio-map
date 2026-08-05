import SwiftUI
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject var env: AppEnvironment
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var notificationsEnabled = false
    @State private var isEditingUsername = false
    @State private var draftUsername = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showLogoutConfirm = false
    @State private var showTerms = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Account header
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.teal.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "bird.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.teal)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(env.username ?? "No username set")
                                .font(.headline)
                            if let email = env.user?.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
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
                            .onChange(of: notificationsEnabled) { _, enabled in
                                if enabled {
                                    requestNotificationPermission()
                                } else {
                                    openAppSettings()
                                }
                            }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Receive alerts when your sightings are annotated by the community.")
                }

                // MARK: - About
                Section {
                    Button {
                        showTerms = true
                    } label: {
                        HStack {
                            Label("Terms of Service", systemImage: "doc.text.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
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
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $isEditingUsername) {
                editUsernameSheet
            }
            .sheet(isPresented: $showTerms) {
                termsSheet
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
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $draftUsername)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Choose a username")
                } footer: {
                    Text("Your username appears on the leaderboard and sighting posts.")
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Username")
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Terms sheet

    private var termsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("By using BirdMap, you agree to the following terms:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        termSection("1. Data Use", body: "Sightings and photos you submit are shared with the BirdMap community to support citizen science research. Location data is stored with each sighting.")

                        termSection("2. Conduct", body: "You agree to submit accurate sightings and not misuse the platform. Spam, offensive content, or intentionally false reports may result in account removal.")

                        termSection("3. Privacy", body: "Your email address is never shared publicly. Your username and sightings are visible to other users.")

                        termSection("4. Content", body: "You retain ownership of photos you upload. By uploading, you grant BirdMap a license to display them within the app.")

                        termSection("5. Changes", body: "These terms may be updated at any time. Continued use of the app constitutes acceptance of the updated terms.")
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTerms = false }
                }
            }
        }
    }

    private func termSection(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.body).foregroundStyle(.secondary)
        }
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
}
