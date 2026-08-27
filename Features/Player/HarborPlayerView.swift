import Combine
import SwiftUI
import UIKit

@MainActor
final class MPVPlaybackState: ObservableObject {
    @Published var snapshot = MPVPlaybackSnapshot()
    weak var controller: MPVPlaybackViewController?
}

struct HarborPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let selection: PlaybackSelection

    @StateObject private var state = MPVPlaybackState()
    @State private var controlsVisible = true
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var speedIndex = 2
    @State private var hideTask: Task<Void, Never>?

    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MPVPlayerRepresentable(
                url: selection.source.url,
                headers: selection.source.headers,
                state: state,
                onFinished: { dismiss() },
                onFailed: { _ in dismiss() }
            )
            .ignoresSafeArea()

            if state.snapshot.position == nil && !state.snapshot.paused {
                ProgressView()
                    .tint(HarborTheme.accent)
                    .scaleEffect(1.4)
            }

            controlsOverlay
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: controlsVisible)
        }
        .statusBarHidden()
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .onDisappear { hideTask?.cancel() }
    }

    private var controlsOverlay: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .allowsHitTesting(controlsVisible)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(selection.subtitle)
                    .font(.caption2)
                    .foregroundStyle(HarborTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 30)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.75), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(timeLabel(isScrubbing ? scrubPosition : state.snapshot.position))
                    .frame(width: 42)
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubPosition : state.snapshot.position ?? 0 },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(state.snapshot.duration, 1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            state.controller?.seekAbsolute(seconds: scrubPosition)
                            scheduleHide()
                        }
                    }
                )
                .tint(HarborTheme.accent)
                Text(timeLabel(state.snapshot.duration))
                    .frame(width: 42)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)

            HStack {
                HStack(spacing: 26) {
                    Button { seek(-15) } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Button { togglePlayback() } label: {
                        Image(systemName: state.snapshot.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(.white.opacity(0.14), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                    Button { seek(15) } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                Button {
                    cycleSpeed()
                } label: {
                    Text(speedLabel)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 18)
        .padding(.top, 30)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var speedLabel: String {
        let value = speeds[speedIndex]
        return value == 1.0 ? "1×" : String(format: value == floor(value) ? "%.0f×" : "%.2g×", value)
    }

    private func timeLabel(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func toggleControls() {
        if controlsVisible {
            hideControls()
        } else {
            withAnimation { controlsVisible = true }
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled, !state.snapshot.paused else { return }
            withAnimation { controlsVisible = false }
        }
    }

    private func hideControls() {
        hideTask?.cancel()
        withAnimation { controlsVisible = false }
    }

    private func seek(_ seconds: Double) {
        state.controller?.seek(relativeSeconds: seconds)
        scheduleHide()
    }

    private func togglePlayback() {
        state.controller?.togglePlayback()
        scheduleHide()
    }

    private func cycleSpeed() {
        speedIndex = (speedIndex + 1) % speeds.count
        state.controller?.setSpeed(speeds[speedIndex])
        scheduleHide()
    }
}

private struct MPVPlayerRepresentable: UIViewControllerRepresentable {
    let url: URL
    let headers: [String: String]
    @ObservedObject var state: MPVPlaybackState
    let onFinished: () -> Void
    let onFailed: (String) -> Void

    final class Coordinator {
        let controller = MPVPlaybackViewController()
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.controller.onFinished = onFinished
        coordinator.controller.onFailed = onFailed
        coordinator.controller.onState = { [weak state] snapshot in
            Task { @MainActor in
                state?.snapshot = snapshot
            }
        }
        return coordinator
    }

    func makeUIViewController(context: Context) -> MPVPlaybackViewController {
        state.controller = context.coordinator.controller
        return context.coordinator.controller
    }

    func updateUIViewController(_ controller: MPVPlaybackViewController, context: Context) {
        controller.load(url: url, headers: headers)
    }
}
