import SwiftUI
import UIKit

struct HarborPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let selection: PlaybackSelection

    var body: some View {
        MPVPlayerRepresentable(
            url: selection.source.url,
            headers: selection.source.headers,
            onFinished: { dismiss() },
            onFailed: { message in
                print("Harbor player: \(message)")
                dismiss()
            }
        )
        .ignoresSafeArea()
        .statusBarHidden()
    }
}

private struct MPVPlayerRepresentable: UIViewControllerRepresentable {
    let url: URL
    let headers: [String: String]
    let onFinished: () -> Void
    let onFailed: (String) -> Void

    func makeUIViewController(context: Context) -> MPVPlaybackViewController {
        let controller = MPVPlaybackViewController()
        controller.onFinished = onFinished
        controller.onFailed = onFailed
        return controller
    }

    func updateUIViewController(_ controller: MPVPlaybackViewController, context: Context) {
        controller.load(url: url, headers: headers)
    }
}
