import Combine
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var sections: [CatalogSection] = []
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
                CatalogSection(id: "movies", title: "Top Movies", items: movies),
                CatalogSection(id: "series", title: "Top Series", items: series),
            ]
        } catch {
            errorMessage = error.localizedDescription
            didLoad = false
        }
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
                HarborTheme.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Harbor")
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

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.sections.isEmpty {
            ProgressView("Loading Harbor…")
                .tint(HarborTheme.accent)
                .foregroundStyle(.white)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let error = model.errorMessage {
                        errorCard(error)
                    }

                    if !cleanQuery.isEmpty {
                        if model.isSearching {
                            ProgressView("Searching…")
                                .tint(HarborTheme.accent)
                        } else if !model.hasCompletedSearch {
                            searchStatusCard("Press Search to find \(cleanQuery).", systemImage: "magnifyingglass")
                        } else if model.searchResults.isEmpty && model.errorMessage == nil {
                            searchStatusCard("No movies or series matched \(cleanQuery).", systemImage: "film.stack")
                        } else if !model.searchResults.isEmpty {
                            posterGrid(title: "Search Results", items: model.searchResults)
                        }
                    } else {
                        if let hero = model.sections.first?.items.first {
                            HeroCard(item: hero)
                        }
                        ForEach(model.sections) { section in
                            PosterRail(title: section.title, items: section.items)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var cleanQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchStatusCard(_ message: String, systemImage: String) -> some View {
        HarborCard {
            Label(message, systemImage: systemImage)
                .foregroundStyle(HarborTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private func errorCard(_ message: String) -> some View {
        HarborCard {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private func posterGrid(title: String, items: [StremioMeta]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold()).padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 18) {
                ForEach(items) { item in
                    NavigationLink(value: item) { PosterCard(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct HeroCard: View {
    let item: StremioMeta

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                HarborAsyncImage(item.background ?? item.poster)
                    .frame(height: 330)
                    .clipped()
                LinearGradient(
                    colors: [.clear, HarborTheme.background.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    HStack(spacing: 10) {
                        if let release = item.releaseInfo { Text(release) }
                        if let rating = item.imdbRating {
                            Label(rating, systemImage: "star.fill").foregroundStyle(.yellow)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HarborTheme.secondaryText)
                }
                .padding(22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24).stroke(HarborTheme.border)
            }
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
    }
}

private struct PosterRail: View {
    let title: String
    let items: [StremioMeta]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { PosterCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct PosterCard: View {
    let item: StremioMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HarborAsyncImage(item.poster)
                .frame(width: 142, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(HarborTheme.border) }
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
            Text(item.releaseInfo ?? item.type.capitalized)
                .font(.caption)
                .foregroundStyle(HarborTheme.secondaryText)
        }
        .frame(width: 142, alignment: .leading)
    }
}
