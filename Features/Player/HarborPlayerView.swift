import AVFoundation
import AVKit
import SwiftUI

struct HarborPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let selection: PlaybackSelection
    @State private var player: AVPlayer

    init(selection: PlaybackSelection) {
        self.selection = selection
        let asset = AVURLAsset(url: selection.source.url)
        _player = State(initialValue: AVPlayer(playerItem: AVPlayerItem(asset: asset)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .horizontal)
            }
            .navigationTitle(selection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(HarborTheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(selection.subtitle)
                        .font(.caption)
                        .foregroundStyle(HarborTheme.secondaryText)
                }
            }
            .onAppear { player.play() }
            .onDisappear { player.pause() }
        }
    }
}
