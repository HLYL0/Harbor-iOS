import AVFoundation
import Libmpv
import UIKit

struct MPVPlaybackSnapshot: Equatable, Sendable {
    var position: Double?
    var duration: Double = 0
    var paused: Bool = true
    var speed: Double = 1
}

final class MPVPlaybackViewController: UIViewController {
    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?
    var onState: ((MPVPlaybackSnapshot) -> Void)?

    private var mpv: OpaquePointer?
    private let metalLayer = MetalLayer()
    private let eventQueue = DispatchQueue(label: "harbor-mpv-events", qos: .userInitiated)
    private var pollTimer: DispatchSourceTimer?
    private var loadedURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        metalLayer.contentsGravity = .resize
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        metalLayer.wantsExtendedDynamicRangeContent = true
        view.layer.addSublayer(metalLayer)

        setupMpv()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = view.bounds
        metalLayer.drawableSize = CGSize(
            width: view.bounds.width * UIScreen.main.nativeScale,
            height: view.bounds.height * UIScreen.main.nativeScale
        )
        CATransaction.commit()
    }

    deinit {
        pollTimer?.cancel()
        if let mpv {
            mpv_terminate_destroy(mpv)
        }
    }

    // MARK: - Loading

    func load(url: URL, headers: [String: String]) {
        guard loadedURL != url else { return }
        loadedURL = url

        if !headers.isEmpty {
            let fields = headers
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
            setOption("http-header-fields", value: fields)
        }

        command(["loadfile", url.absoluteString, "replace"])
    }

    // MARK: - MPV setup

    private func setupMpv() {
        mpv = mpv_create()
        guard let mpv else {
            onFailed?("Could not create the playback engine.")
            return
        }

        var layerPointer = Int64(Int(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerPointer)
        setOption("vo", value: "gpu-next")
        setOption("gpu-api", value: "vulkan")
        setOption("gpu-context", value: "moltenvk")
        setOption("hwdec", value: "videotoolbox")
        setOption("ao", value: "audiounit")
        setOption("audio-channels", value: "auto")
        setOption("audio-fallback-to-null", value: "yes")
        setOption("vulkan-swap-mode", value: "fifo")
        setOption("video-rotate", value: "no")
        setOption("keep-open", value: "no")
        setOption("subs-match-os-language", value: "yes")

        guard mpv_initialize(mpv) >= 0 else {
            onFailed?("Could not initialize the playback engine.")
            return
        }

        startEventLoop()
        startPolling()
    }

    private func setOption(_ name: String, value: String) {
        guard let mpv else { return }
        name.withCString { namePointer in
            value.withCString { valuePointer in
                mpv_set_option_string(mpv, namePointer, valuePointer)
            }
        }
    }

    private func command(_ args: [String]) {
        guard let mpv else { return }
        var cArgs: [UnsafePointer<CChar>?] = args.map {
            UnsafePointer(strdup($0))
        }
        cArgs.append(nil)
        mpv_command(mpv, &cArgs)
        cArgs.forEach { free(UnsafeMutablePointer(mutating: $0)) }
    }

    private func startEventLoop() {
        eventQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            while true {
                guard let event = mpv_wait_event(mpv, 0.25) else { continue }
                let eventID = event.pointee.event_id
                if eventID == MPV_EVENT_SHUTDOWN {
                    return
                }
                guard eventID == MPV_EVENT_END_FILE else { continue }
                let endFile = event.pointee.data
                    .assumingMemoryBound(to: mpv_event_end_file.self)
                    .pointee
                if endFile.reason == MPV_END_FILE_REASON_ERROR {
                    DispatchQueue.main.async {
                        self.onFailed?("Playback ended with an error.")
                    }
                } else {
                    DispatchQueue.main.async {
                        self.onFinished?()
                    }
                }
            }
        }
    }

    // MARK: - State polling

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: eventQueue)
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            var snapshot = MPVPlaybackSnapshot()
            snapshot.duration = self.doubleProperty("duration")
            snapshot.position = self.optionalDoubleProperty("time-pos")
            snapshot.paused = self.flagProperty("pause")
            snapshot.speed = self.doubleProperty("speed")
            let callback = self.onState
            DispatchQueue.main.async {
                callback?(snapshot)
            }
            _ = mpv
        }
        timer.resume()
        pollTimer = timer
    }

    private func doubleProperty(_ name: String) -> Double {
        guard let mpv else { return 0 }
        var value = 0.0
        let result = name.withCString { pointer in
            mpv_get_property(mpv, pointer, MPV_FORMAT_DOUBLE, &value)
        }
        return result >= 0 ? value : 0
    }

    private func optionalDoubleProperty(_ name: String) -> Double? {
        guard let mpv else { return nil }
        var value = 0.0
        let result = name.withCString { pointer in
            mpv_get_property(mpv, pointer, MPV_FORMAT_DOUBLE, &value)
        }
        return result >= 0 ? value : nil
    }

    private func flagProperty(_ name: String) -> Bool {
        guard let mpv else { return false }
        var value: Int32 = 0
        let result = name.withCString { pointer in
            mpv_get_property(mpv, pointer, MPV_FORMAT_FLAG, &value)
        }
        return result >= 0 && value != 0
    }

    // MARK: - Playback controls

    func togglePlayback() {
        guard let mpv else { return }
        var flag: Int32 = flagProperty("pause") ? 0 : 1
        mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
    }

    func seek(relativeSeconds: Double) {
        command(["seek", "\(relativeSeconds)", "relative"])
    }

    func seekAbsolute(seconds: Double) {
        command(["seek", "\(seconds)", "absolute"])
    }

    func setSpeed(_ speed: Double) {
        guard let mpv else { return }
        var value = speed
        mpv_set_property(mpv, "speed", MPV_FORMAT_DOUBLE, &value)
    }
}
