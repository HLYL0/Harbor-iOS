import AVFoundation
import Libmpv
import UIKit

final class MPVPlaybackViewController: UIViewController {
    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?

    private var mpv: OpaquePointer?
    private let metalLayer = MetalLayer()
    private let eventQueue = DispatchQueue(label: "harbor-mpv-events", qos: .userInitiated)
    private var loadedURL: URL?
    private var isPaused = false
    private var pauseButton: UIButton?

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
        installControls()
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
                if endFile.reason == MPV_END_FILE_REASON_ERROR.rawValue {
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

    // MARK: - Playback controls

    func togglePlayback() {
        guard let mpv else { return }
        isPaused.toggle()
        var flag = isPaused ? 1 : 0
        mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        pauseButton?.setImage(
            UIImage(systemName: isPaused ? "play.fill" : "pause.fill"),
            for: .normal
        )
    }

    func seek(relativeSeconds: Double) {
        command(["seek", "\(relativeSeconds)", "relative"])
    }

    // MARK: - UIKit overlay controls

    private func installControls() {
        let backButton = controlButton("gobackward.15", action: #selector(seekBack))
        let pause = controlButton("pause.fill", action: #selector(togglePlaybackTapped))
        let forwardButton = controlButton("goforward.15", action: #selector(seekForward))
        let doneButton = controlButton("xmark.circle.fill", action: #selector(doneTapped))
        pauseButton = pause

        let stack = UIStackView(arrangedSubviews: [backButton, pause, forwardButton, doneButton])
        stack.axis = .horizontal
        stack.spacing = 36
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])
    }

    private func controlButton(_ symbol: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func togglePlaybackTapped() { togglePlayback() }
    @objc private func seekBack() { seek(relativeSeconds: -15) }
    @objc private func seekForward() { seek(relativeSeconds: 15) }
    @objc private func doneTapped() { onFinished?() }
}
