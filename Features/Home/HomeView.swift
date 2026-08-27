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
                CatalogSection(id: "movie", title: "Top Movies", items: movies),
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
    @State private var chip = "all"

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
                LazyVStack(alignment: .leading, spacing: 24) {
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
        chipRow
        if let hero = model.sections.first?.items.first {
            HeroCard(item: hero)
                .padding(.horizontal, 20)
        }
        ForEach(model.sections.filter { chip == "all" || $0.id == chip }) { section in
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

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(["all", "movie", "series"], id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { chip = option }
                } label: {
                    Text(option.capitalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(chip == option ? HarborTheme.accent : HarborTheme.secondaryText)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(
                            chip == option ? HarborTheme.accentSoft : HarborTheme.card,
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(
                            chip == option ? HarborTheme.accent : HarborTheme.border,
                            lineWidth: 1
                        ))
                }
            }
        }
        .padding(.horizontal, 20)
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

private struct HeroCard: View {
    let item: StremioMeta

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                HarborAsyncImage(item.background ?? item.poster)
                    .frame(height: 352)
                    .clipped()
                LinearGradient(
                    colors: [.clear, HarborTheme.background.opacity(0.55), HarborTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text("TOP MOVIE")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(HarborTheme.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(HarborTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                        if let rating = item.imdbRating {
                            Label(rating, systemImage: "star.fill")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(HarborTheme.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(HarborTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Text(item.name)
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        if let release = item.releaseInfo {
                            Text(release.prefix(4))
                        }
                        if let genres = item.genres {
                            Text(genres.prefix(2).joined(separator: " · "))
                        }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HarborTheme.secondaryText)
                }
                .padding(16)
            }
            .frame(height: 352)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(HarborTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
    }
}

private struct PosterRail: View {
    let title: String
    let items: [StremioMeta]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(HarborTheme.ink)
                Text("\(items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HarborTheme.subtleText)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 13) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { PosterCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct PosterCard: View {
    let item: StremioMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                HarborAsyncImage(item.poster)
                    .frame(width: 108, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                if let rating = item.imdbRating {
                    Text("★ \(rating)")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(HarborTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 7))
                        .padding(6)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(HarborTheme.border, lineWidth: 1))
            Text(item.name)
                .font(.caption)
                .foregroundStyle(HarborTheme.secondaryText)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)
        }
        .frame(width: 108)
    }
}
