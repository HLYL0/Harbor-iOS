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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ContentDetailViewModel

    init(item: StremioMeta) {
        _model = StateObject(wrappedValue: ContentDetailViewModel(item: item))
    }

    var body: some View {
        ZStack {
            HarborTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    backdrop
                    VStack(alignment: .leading, spacing: 0) {
                        titleBlock
                        if !model.episodes.isEmpty {
                            episodePicker
                                .padding(.top, 16)
                        }
                        if let description = model.metadata.description {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(HarborTheme.secondaryText)
                                .lineSpacing(5)
                                .padding(.top, 16)
                        }
                        findStreamsButton
                            .padding(.top, 18)
                        streamList
                            .padding(.top, 24)
                        if let error = model.errorMessage {
                            errorCard(error)
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, -54)
                    .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 6)
        }
        .task { await model.loadMetadata(using: environment) }
        .fullScreenCover(item: $model.playbackSelection) { selection in
            HarborPlayerView(selection: selection)
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            HarborAsyncImage(model.metadata.background ?? model.metadata.poster)
                .frame(height: 272)
                .clipped()
            LinearGradient(
                colors: [.clear, HarborTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 272)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.metadata.name)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(HarborTheme.ink)
            HStack(spacing: 8) {
                if let rating = model.metadata.imdbRating {
                    chip(Label(rating, systemImage: "star.fill"), tint: HarborTheme.accent, bg: HarborTheme.accentSoft)
                }
                if let release = model.metadata.releaseInfo {
                    chip(Text(release))
                }
                if let genres = model.metadata.genres {
                    chip(Text(genres.prefix(2).joined(separator: " · ")))
                }
            }
        }
    }

    private func chip(_ label: some View, tint: Color = HarborTheme.secondaryText, bg: Color = HarborTheme.card) -> some View {
        label
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(HarborTheme.border, lineWidth: 1))
    }

    private var episodePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Episode")
                .font(.headline.weight(.heavy))
                .foregroundStyle(HarborTheme.ink)
            Menu {
                ForEach(model.episodes, id: \.stableID) { episode in
                    Button(episodeLabel(episode)) { model.selectVideo(episode) }
                }
            } label: {
                HStack {
                    Text(model.selectedVideo.map(episodeLabel) ?? "Choose episode")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HarborTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HarborTheme.accent)
                }
                .padding(14)
                .background(HarborTheme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HarborTheme.border, lineWidth: 1))
            }
        }
    }

    private var findStreamsButton: some View {
        Button {
            Task { await model.findStreams(using: environment) }
        } label: {
            HStack(spacing: 10) {
                if model.isLoadingStreams {
                    ProgressView().tint(HarborTheme.onAccent)
                } else {
                    Image(systemName: "play.fill")
                }
                Text("Find Streams")
                    .font(.headline.weight(.heavy))
            }
            .foregroundStyle(HarborTheme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(HarborTheme.accent, in: RoundedRectangle(cornerRadius: 15))
            .shadow(color: HarborTheme.accent.opacity(0.28), radius: 12, y: 6)
        }
        .disabled(model.isLoadingStreams)
    }

    @ViewBuilder
    private var streamList: some View {
        if !model.streams.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sources")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(HarborTheme.ink)
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
        }
    }

    private func errorCard(_ message: String) -> some View {
        HarborCard {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(HarborTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        if candidate.stream.infoHash != nil && debridReady { return HarborTheme.success }
        return .orange
    }

    private var badgeBackground: Color {
        if candidate.stream.isDirectlyPlayable { return HarborTheme.accentSoft }
        if candidate.stream.infoHash != nil && debridReady { return HarborTheme.success.opacity(0.16) }
        return .orange.opacity(0.14)
    }

    private var leadingIcon: String {
        if isResolving { return "arrow.triangle.2.circlepath" }
        if candidate.stream.isDirectlyPlayable { return "play.fill" }
        if candidate.stream.infoHash != nil && debridReady { return "bolt.fill" }
        return "link"
    }

    var body: some View {
        HarborCard {
            HStack(spacing: 13) {
                Image(systemName: leadingIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isResolving ? HarborTheme.accent : badgeColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.stream.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HarborTheme.ink)
                        .lineLimit(2)
                    Text(candidate.addonName)
                        .font(.caption)
                        .foregroundStyle(HarborTheme.subtleText)
                }
                Spacer()
                if isResolving {
                    ProgressView().tint(HarborTheme.accent)
                }
                Text(badge)
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(badgeBackground, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}
