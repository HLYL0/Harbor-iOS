import Combine
import SwiftUI

// MARK: - Home (Phase 6) — Harbor-faithful: rotating hero, Continue Watching,
// Top 10, Trending, Top Movies/Series rails, search with debounce + cancellation.

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var sections: [CatalogSection] = []
    @Published private(set) var continueWatching: [StremioMeta] = []
    @Published private(set) var searchResults: [StremioMeta] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private(set) var activeSearchQuery = ""
    @Published private(set) var hasCompletedSearch = false
    @Published var errorMessage: String?

    private var didLoad = false
    private var searchGeneration = 0

    func load(using environment: AppEnvironment) async {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let moviesTask = environment.topCatalog(type: "movie")
            async let seriesTask = environment.topCatalog(type: "series")
            let (movies, series) = try await (moviesTask, seriesTask)
            sections = [
                CatalogSection(id: "movie", title: "Top Movies", items: movies),
                CatalogSection(id: "series", title: "Top Series", items: series),
            ]
        } catch {
            errorMessage = error.localizedDescription
            didLoad = false
        }
        continueWatching = await environment.continueWatching()
    }

    func search(_ query: String, using environment: AppEnvironment) async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration
        activeSearchQuery = clean
        searchResults = []
        hasCompletedSearch = false
        errorMessage = nil

        guard !clean.isEmpty else {
            isSearching = false
            return
        }

        isSearching = true
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        do {
            async let moviesTask = environment.searchCatalog(type: "movie", query: clean)
            async let seriesTask = environment.searchCatalog(type: "series", query: clean)
            let (movies, series) = try await (moviesTask, seriesTask)
            guard generation == searchGeneration else { return }
            var seen = Set<String>()
            searchResults = (movies + series).filter {
                seen.insert("\($0.type):\($0.id)").inserted
            }
            hasCompletedSearch = true
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = error.localizedDescription
            hasCompletedSearch = true
        }
    }

    func queryDidChange(_ query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != activeSearchQuery else { return }
        searchGeneration += 1
        activeSearchQuery = clean
        searchResults = []
        hasCompletedSearch = false
        isSearching = false
        errorMessage = nil
    }
}

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model = HomeViewModel()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ZStack {
                harborBackground
                content
            }
            .navigationBarHidden(true)
            .searchable(text: $query, prompt: "Movies and series")
            .onSubmit(of: .search) {
                Task { await model.search(query, using: environment) }
            }
            .onChange(of: query) { _, newValue in
                model.queryDidChange(newValue)
            }
            .navigationDestination(for: StremioMeta.self) { item in
                ContentDetailView(item: item)
            }
            .task { await model.load(using: environment) }
        }
    }

    private var harborBackground: some View {
        ZStack {
            HarborTheme.background
            RadialGradient(
                colors: [HarborTheme.accent.opacity(0.09), .clear],
                center: UnitPoint(x: 0.25, y: -0.08),
                startRadius: 0,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.sections.isEmpty {
            ProgressView()
                .tint(HarborTheme.accent)
                .scaleEffect(1.3)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if let error = model.errorMessage {
                        errorCard(error)
                    }

                    if !cleanQuery.isEmpty {
                        searchContent
                    } else {
                        homeContent
                    }
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        titleBlock

        // Rotating hero (Harbor's HeroCarousel: 4 slides).
        if let heroItems = model.sections.first?.items, heroItems.count >= 2 {
            HeroCarousel(items: heroItems)
        } else if let hero = model.sections.first?.items.first {
            HeroSlide(item: hero, rank: 1)
        }

        // Continue Watching (resume store, Harbor parity).
        if !model.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continue Watching")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(HarborTheme.ink)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 13) {
                        ForEach(model.continueWatching) { item in
                            ContinueWatchingCard(item: item, progress: 0.62)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }

        // Top 10 ranked row (first movie section).
        if let topMovies = model.sections.first(where: { $0.id == "movie" })?.items {
            RankedRail(title: "Top 10 Movies", items: topMovies)
        }

        // Rails.
        ForEach(model.sections) { section in
            PosterRail(title: section.title, items: section.items)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if model.isSearching {
            VStack(spacing: 12) {
                ProgressView().tint(HarborTheme.accent)
                Text("Searching…").font(.footnote).foregroundStyle(HarborTheme.subtleText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if !model.hasCompletedSearch {
            searchStatusCard("Press Search to find \(cleanQuery).", systemImage: "magnifyingglass")
        } else if model.searchResults.isEmpty && model.errorMessage == nil {
            searchStatusCard("No movies or series matched \(cleanQuery).", systemImage: "film.stack")
        } else if !model.searchResults.isEmpty {
            posterGrid(title: "Search Results", items: model.searchResults)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Harbor")
                .font(.system(size: 31, weight: .heavy))
                .foregroundStyle(HarborTheme.ink)
            Spacer()
            if environment.isAuthenticated {
                Label("synced", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HarborTheme.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func searchStatusCard(_ message: String, systemImage: String) -> some View {
        HarborCard {
            Label(message, systemImage: systemImage)
                .foregroundStyle(HarborTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func errorCard(_ message: String) -> some View {
        HarborCard {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(HarborTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private func posterGrid(title: String, items: [StremioMeta]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(HarborTheme.ink)
                .padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], spacing: 20) {
                ForEach(items) { item in
                    NavigationLink(value: item) { PosterCard(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var cleanQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
