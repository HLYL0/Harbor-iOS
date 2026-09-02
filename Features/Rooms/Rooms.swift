import SwiftUI

// MARK: - Rooms (Phase 6–7). Real data where services exist; deferred rooms are
// explicitly labeled (development-only, replaced by their phases — spec §101).

struct MoviesRoom: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var items: [StremioMeta] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                HarborTheme.background.ignoresSafeArea()
                roomContent
            }
            .navigationTitle("Movies")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: StremioMeta.self) { ContentDetailView(item: $0) }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var roomContent: some View {
        if isLoading && items.isEmpty {
            ProgressView().tint(HarborTheme.accent)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if let errorMessage {
                        HarborCard {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HarborTheme.danger)
                        }
                    }
                    if !items.isEmpty {
                        RankedRail(title: "Top 10 Movies", items: items)
                        PosterRail(title: "Popular Movies", items: items)
                    }
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func load() async {
        do {
            items = try await environment.catalogService.cinemetaCatalog(type: "movie", skip: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ShowsRoom: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var items: [StremioMeta] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                HarborTheme.background.ignoresSafeArea()
                roomContent
            }
            .navigationTitle("Shows")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: StremioMeta.self) { ContentDetailView(item: $0) }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var roomContent: some View {
        if isLoading && items.isEmpty {
            ProgressView().tint(HarborTheme.accent)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if let errorMessage {
                        HarborCard {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HarborTheme.danger)
                        }
                    }
                    if !items.isEmpty {
                        RankedRail(title: "Top 10 Shows", items: items)
                        PosterRail(title: "Popular Shows", items: items)
                    }
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func load() async {
        do {
            items = try await environment.catalogService.cinemetaCatalog(type: "series", skip: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct LibraryRoom: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var continueWatching: [StremioMeta] = []

    var body: some View {
        NavigationStack {
            ZStack {
                HarborTheme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        if !continueWatching.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Continue Watching")
                                    .font(.system(size: 19, weight: .heavy))
                                    .foregroundStyle(HarborTheme.ink)
                                    .padding(.horizontal, 20)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 13) {
                                        ForEach(continueWatching) { item in
                                            ContinueWatchingCard(item: item, progress: 0.62)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        } else {
                            HarborCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Nothing in progress yet")
                                        .font(.headline)
                                        .foregroundStyle(HarborTheme.ink)
                                    Text("Start watching something and it will show up here.")
                                        .font(.footnote)
                                        .foregroundStyle(HarborTheme.secondaryText)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("My Library")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: StremioMeta.self) { ContentDetailView(item: $0) }
            .task {
                continueWatching = await environment.continueWatching()
            }
        }
    }
}

struct AddonsRoom: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var installURL = ""
    @State private var discovered: [DiscoveredAddon] = []
    @State private var showAdultGate = false

    var body: some View {
        NavigationStack {
            ZStack {
                HarborTheme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        // Install by URL (existing flow).
                        HarborCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Add addon")
                                    .font(.headline)
                                    .foregroundStyle(HarborTheme.ink)
                                TextField("https://…/manifest.json", text: $installURL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .padding(11)
                                    .background(HarborTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(HarborTheme.ink)
                                Button {
                                    Task { await environment.installAddon(rawURL: installURL) }
                                } label: {
                                    Text("Install")
                                        .font(.callout.weight(.bold))
                                        .foregroundStyle(HarborTheme.onAccent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(HarborTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Installed addons.
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Installed (\(environment.addons.count))")
                                .font(.system(size: 19, weight: .heavy))
                                .foregroundStyle(HarborTheme.ink)
                            ForEach(environment.addons) { addon in
                                HarborCard {
                                    HStack(spacing: 12) {
                                        HarborAsyncImage(addon.manifest.logo)
                                            .frame(width: 42, height: 42)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(addon.manifest.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(HarborTheme.ink)
                                            Text(addon.manifest.id)
                                                .font(.caption2)
                                                .foregroundStyle(HarborTheme.subtleText)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Button(role: .destructive) {
                                            Task { await environment.removeAddon(addon) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(HarborTheme.danger)
                                        }
                                    }
                                }
                            }
                            if environment.addons.isEmpty {
                                Text("No addons installed. Install one above or browse the directory.")
                                    .font(.footnote)
                                    .foregroundStyle(HarborTheme.secondaryText)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Community directory (stremio-addons.net, adult-gated).
                        if !discovered.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Top addons")
                                    .font(.system(size: 19, weight: .heavy))
                                    .foregroundStyle(HarborTheme.ink)
                                ForEach(discovered.prefix(12)) { addon in
                                    HarborCard {
                                        HStack(spacing: 12) {
                                            HarborAsyncImage(addon.logo)
                                                .frame(width: 42, height: 42)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(addon.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(HarborTheme.ink)
                                                Text("★ \(addon.stars)")
                                                    .font(.caption)
                                                    .foregroundStyle(HarborTheme.accent)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Addons")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadDiscovery() }
            .confirmationDialog("Enable adult addons?", isPresented: $showAdultGate, titleVisibility: .visible) {
                Button("Enable adult addons") {
                    Task { await loadDiscovery(allowAdult: true) }
                }
                Button("Keep hidden", role: .cancel) {}
            }
        }
    }

    private func loadDiscovery(allowAdult: Bool = false) async {
        do {
            discovered = try await environment.discoveryClient.browse(
                mode: .top, category: nil, query: nil, allowAdult: allowAdult
            )
        } catch {
            // Directory unreachable — leave empty (Harbor parity: silent degradation).
            discovered = []
        }
    }
}

/// Development placeholder — replaced by the full Anime room in Phase 12.
/// Honest by design: no fake data, no fake rails (spec §101).
struct AnimeRoomPlaceholder: View {
    var body: some View {
        NavigationStack {
            ZStack {
                HarborTheme.background.ignoresSafeArea()
                HarborCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Anime room", systemImage: "sparkles.tv")
                            .font(.headline)
                            .foregroundStyle(HarborTheme.ink)
                        Text("The full Anime room (Kitsu/AniZip/TMDB pipeline, awards, dub/sub badges) lands in Phase 12. Status: PLANNED — see docs/IOS_ANIME.md.")
                            .font(.footnote)
                            .foregroundStyle(HarborTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Anime")
        }
    }
}

/// Development placeholder — replaced by the full Live TV room in Phase 13.
struct LiveTVRoomPlaceholder: View {
    var body: some View {
        NavigationStack {
            ZStack {
                HarborTheme.background.ignoresSafeArea()
                HarborCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Live TV", systemImage: "tv")
                            .font(.headline)
                            .foregroundStyle(HarborTheme.ink)
                        Text("M3U/Xtream/XMLTV + EPG lands in Phase 13. Status: PLANNED — see docs/IOS_LIVE_TV.md.")
                            .font(.footnote)
                            .foregroundStyle(HarborTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Live TV")
        }
    }
}
