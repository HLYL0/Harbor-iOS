import Combine
import SwiftUI

@MainActor
final class ContentDetailViewModel: ObservableObject {
    @Published private(set) var metadata: StremioMeta
    @Published private(set) var streams: [AttributedStream] = []
    @Published private(set) var isLoadingMetadata = false
    @Published private(set) var isLoadingStreams = false
    @Published var selectedVideo: StremioVideo?
    @Published var playbackSelection: PlaybackSelection?
    @Published var resolvingStreamID: String?
    @Published var errorMessage: String?

    private var streamRequestGeneration = 0

    init(item: StremioMeta) {
        metadata = item
    }

    var episodes: [StremioVideo] {
        (metadata.videos ?? []).sorted {
            let lhs = ($0.season ?? 0, $0.episode ?? $0.number ?? 0)
            let rhs = ($1.season ?? 0, $1.episode ?? $1.number ?? 0)
            return lhs < rhs
        }
    }

    func loadMetadata(using environment: AppEnvironment) async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }
        do {
            metadata = try await environment.metadata(type: metadata.type, id: metadata.id)
            if selectedVideo == nil, let firstEpisode = episodes.first {
                selectVideo(firstEpisode)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func findStreams(using environment: AppEnvironment) async {
        let streamID: String
        if metadata.type == "series" {
            guard let episodeID = selectedVideo?.id ?? metadata.behaviorHints?.defaultVideoId else {
                errorMessage = "Choose an episode first."
                return
            }
            streamID = episodeID
        } else {
            streamID = metadata.id
        }

        streamRequestGeneration += 1
        let requestGeneration = streamRequestGeneration
        isLoadingStreams = true
        errorMessage = nil
        defer {
            if requestGeneration == streamRequestGeneration {
                isLoadingStreams = false
            }
        }
        let candidates = await environment.streamCandidates(type: metadata.type, id: streamID)
        guard requestGeneration == streamRequestGeneration else { return }
        streams = candidates
        if streams.isEmpty {
            errorMessage = environment.addons.isEmpty
                ? "No stream addons are installed. Sync Stremio or add a manifest in Settings."
                : "Your addons returned no streams for this title."
        }
    }

    func play(_ candidate: AttributedStream, using environment: AppEnvironment) async {
        do {
            let source: PlaybackSource
            if candidate.stream.isDirectlyPlayable {
                source = try candidate.stream.playbackSource()
            } else if candidate.stream.infoHash != nil {
                guard environment.hasDebridKey else {
                    errorMessage = "Add your Real-Debrid API key in Settings to play torrent sources."
                    return
                }
                resolvingStreamID = candidate.id
                defer { resolvingStreamID = nil }
                let url = try await environment.debridResolve(stream: candidate.stream)
                source = PlaybackSource(url: url)
            } else {
                source = try candidate.stream.playbackSource()
            }
            playbackSelection = PlaybackSelection(
                title: metadata.name,
                subtitle: candidate.addonName,
                source: source
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectVideo(_ video: StremioVideo) {
        streamRequestGeneration += 1
        selectedVideo = video
        streams = []
        playbackSelection = nil
        errorMessage = nil
        isLoadingStreams = false
    }
}

struct PlaybackSelection: Identifiable {
    let title: String
    let subtitle: String
    let source: PlaybackSource
    var id: String { source.url.absoluteString }
}

struct ContentDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model: ContentDetailViewModel

    init(item: StremioMeta) {
        _model = StateObject(wrappedValue: ContentDetailViewModel(item: item))
    }

    var body: some View {
        ZStack {
            HarborTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    if model.metadata.type == "series", !model.episodes.isEmpty {
                        episodePicker
                    }
                    controls
                    if let message = model.errorMessage { errorCard(message) }
                    streamList
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(model.metadata.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadMetadata(using: environment) }
        .fullScreenCover(item: $model.playbackSelection) { selection in
            HarborPlayerView(selection: selection)
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            HarborAsyncImage(model.metadata.background ?? model.metadata.poster)
                .frame(height: 310)
                .clipped()
            LinearGradient(
                colors: [.clear, HarborTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack(alignment: .bottom, spacing: 16) {
                HarborAsyncImage(model.metadata.poster)
                    .frame(width: 112, height: 166)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(HarborTheme.border) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.metadata.name).font(.title.bold())
                    HStack(spacing: 10) {
                        if let release = model.metadata.releaseInfo { Text(release) }
                        if let rating = model.metadata.imdbRating {
                            Label(rating, systemImage: "star.fill").foregroundStyle(.yellow)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HarborTheme.secondaryText)
                    if let genres = model.metadata.genres, !genres.isEmpty {
                        Text(genres.prefix(3).joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(HarborTheme.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var episodePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Episode").font(.headline)
            Menu {
                ForEach(model.episodes, id: \.stableID) { episode in
                    Button(episodeLabel(episode)) { model.selectVideo(episode) }
                }
            } label: {
                HStack {
                    Text(model.selectedVideo.map(episodeLabel) ?? "Choose episode")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(HarborTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let description = model.metadata.description {
                Text(description)
                    .foregroundStyle(HarborTheme.secondaryText)
                    .lineSpacing(4)
            }
            Button {
                Task { await model.findStreams(using: environment) }
            } label: {
                HStack {
                    if model.isLoadingStreams { ProgressView().tint(.black) }
                    Label("Find Streams", systemImage: "play.fill")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.black)
                .background(HarborTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(model.isLoadingStreams)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var streamList: some View {
        if !model.streams.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sources").font(.title2.bold())
                ForEach(model.streams) { candidate in
                    Button {
                        Task { await model.play(candidate, using: environment) }
                    } label: {
                        StreamRow(
                            candidate: candidate,
                            isResolving: model.resolvingStreamID == candidate.id,
                            debridReady: environment.hasDebridKey
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HarborCard {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private func episodeLabel(_ episode: StremioVideo) -> String {
        let prefix = "S\(episode.season ?? 0) E\(episode.episode ?? episode.number ?? 0)"
        return "\(prefix) · \(episode.displayTitle)"
    }
}

private struct StreamRow: View {
    let candidate: AttributedStream
    let isResolving: Bool
    let debridReady: Bool

    private var badge: String {
        if candidate.stream.isDirectlyPlayable { return "DIRECT" }
        if candidate.stream.infoHash != nil && debridReady { return "DEBRID" }
        return "RESOLVER"
    }

    private var badgeColor: Color {
        if candidate.stream.isDirectlyPlayable { return HarborTheme.accent }
        if candidate.stream.infoHash != nil && debridReady { return .green }
        return .orange
    }

    private var leadingIcon: String {
        if isResolving { return "arrow.triangle.2.circlepath" }
        if candidate.stream.isDirectlyPlayable { return "play.circle.fill" }
        if candidate.stream.infoHash != nil && debridReady { return "bolt.circle.fill" }
        return "link.badge.plus"
    }

    var body: some View {
        HarborCard {
            HStack(spacing: 14) {
                Image(systemName: leadingIcon)
                    .font(.title2)
                    .foregroundStyle(isResolving ? HarborTheme.accent : badgeColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.stream.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(candidate.addonName)
                        .font(.caption)
                        .foregroundStyle(HarborTheme.secondaryText)
                }
                Spacer()
                if isResolving {
                    ProgressView().tint(HarborTheme.accent)
                }
                Text(badge)
                    .font(.caption2.bold())
                    .foregroundStyle(badgeColor)
            }
        }
    }
}
