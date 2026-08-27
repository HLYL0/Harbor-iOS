import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var email = ""
    @State private var password = ""
    @State private var manifestURL = ""
    @State private var debridKey = ""

    var body: some View {
        NavigationStack {
            List {
                accountSection
                debridSection
                addonInstallSection
                installedAddonsSection
                compatibilitySection
            }
            .scrollContentBackground(.hidden)
            .background(HarborTheme.background)
            .navigationTitle("Settings")
            .overlay(alignment: .bottom) { statusOverlay }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Stremio Account") {
            if environment.isAuthenticated {
                Label(environment.user?.email ?? "Stremio connected", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(HarborTheme.accent)
                Button("Sync Addons") { Task { await environment.syncAddons() } }
                    .disabled(environment.isWorking)
                Button("Sign Out", role: .destructive) {
                    Task { await environment.logout() }
                }
                .disabled(environment.isWorking)
            } else {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Button {
                    let submittedPassword = password
                    password = ""
                    Task { await environment.login(email: email, password: submittedPassword) }
                } label: {
                    HStack {
                        if environment.isWorking { ProgressView().tint(HarborTheme.accent) }
                        Text("Sign In & Sync")
                    }
                }
                .disabled(environment.isWorking)
            }
        }
        .listRowBackground(HarborTheme.card)
    }

    private var debridSection: some View {
        Section("Debrid · Real-Debrid") {
            if environment.hasDebridKey {
                Label("API key saved in Keychain", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Button("Remove Key", role: .destructive) {
                    Task { await environment.clearDebridAPIKey() }
                }
            } else {
                SecureField("Real-Debrid API Key", text: $debridKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Key") {
                    let submitted = debridKey
                    debridKey = ""
                    Task { await environment.saveDebridAPIKey(submitted) }
                }
                .disabled(debridKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Torrent sources resolve through Real-Debrid so they can play on iOS. The key never leaves your device.")
                .font(.caption)
                .foregroundStyle(HarborTheme.secondaryText)
        }
        .listRowBackground(HarborTheme.card)
    }

    private var addonInstallSection: some View {
        Section("Install Addon") {
            TextField("https://…/manifest.json", text: $manifestURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Install Manifest") {
                let submitted = manifestURL
                Task {
                    await environment.installAddon(rawURL: submitted)
                    if environment.actionError == nil { manifestURL = "" }
                }
            }
            .disabled(environment.isWorking || manifestURL.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .listRowBackground(HarborTheme.card)
    }

    @ViewBuilder
    private var installedAddonsSection: some View {
        Section("Installed Addons · \(environment.addons.count)") {
            if environment.addons.isEmpty {
                Text("Sync Stremio or paste a manifest URL. Catalog browsing still works through Cinemeta.")
                    .foregroundStyle(HarborTheme.secondaryText)
            } else {
                ForEach(environment.addons) { addon in
                    HStack(spacing: 12) {
                        HarborAsyncImage(addon.manifest.logo)
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(addon.manifest.name).font(.subheadline.weight(.semibold))
                            Text(addon.manifest.id)
                                .font(.caption2)
                                .foregroundStyle(HarborTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            Task { await environment.removeAddon(addon) }
                        }
                    }
                }
            }
        }
        .listRowBackground(HarborTheme.card)
    }

    private var compatibilitySection: some View {
        Section("Playback") {
            Label("Native HLS / MP4 through AVPlayer", systemImage: "checkmark.circle.fill")
                .foregroundStyle(HarborTheme.accent)
            Label("Torrent-only sources are shown but need a resolver", systemImage: "link.badge.plus")
                .foregroundStyle(.orange)
        }
        .listRowBackground(HarborTheme.card)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let error = environment.actionError {
            statusPill(error, color: .red)
        } else if let notice = environment.notice {
            statusPill(notice, color: HarborTheme.accent)
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(color.opacity(0.92), in: Capsule())
            .padding(.bottom, 14)
            .onTapGesture {
                environment.actionError = nil
                environment.notice = nil
            }
    }
}
