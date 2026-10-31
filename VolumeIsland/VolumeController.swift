#if !WIDGET_EXTENSION
import ActivityKit
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class VolumeController: ObservableObject {
    static let shared = VolumeController()
    static let stepSize: Float = 0.0625

    @Published var volume: Float = 0
    @Published var isMuted = false
    @Published var lastError = ""

    private var previousVolume: Float = 0.5
    private var prepared = false
    private var observation: NSKeyValueObservation?
    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))

    private init() {}

    // MARK: Setup

    func prepare() {
        if !prepared {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, options: [.mixWithOthers])
                try session.setActive(true)
                volume = session.outputVolume
                isMuted = volume < 0.001
                observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                    guard let value = change.newValue else { return }
                    Task { @MainActor in self?.hardwareVolumeChanged(value) }
                }
                prepared = true
            } catch {
                lastError = "Audio session failed: \(error.localizedDescription)"
            }
        }
        attachVolumeView()
    }

    private func attachVolumeView() {
        guard volumeView.superview == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first
        guard let window else {
            lastError = "No app window available (app was in the background)"
            return
        }
        volumeView.alpha = 0.0001
        window.addSubview(volumeView)
    }

    private func hardwareVolumeChanged(_ value: Float) {
        volume = value
        isMuted = value < 0.001
        Task { await refreshActivity() }
    }

    // MARK: Volume actions

    func step(_ delta: Float) async {
        prepare()
        let current = AVAudioSession.sharedInstance().outputVolume
        await apply(min(max(current + delta, 0), 1))
    }

    func toggleMute() async {
        prepare()
        let current = AVAudioSession.sharedInstance().outputVolume
        if current < 0.001 {
            await apply(previousVolume)
        } else {
            previousVolume = current
            await apply(0)
        }
    }

    private func apply(_ target: Float) async {
        attachVolumeView()
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else {
            lastError = "Volume slider not found"
            return
        }
        slider.value = target
        slider.sendActions(for: .valueChanged)

        try? await Task.sleep(nanoseconds: 250_000_000)

        let actual = AVAudioSession.sharedInstance().outputVolume
        volume = actual
        isMuted = actual < 0.001
        if abs(actual - target) > 0.02 {
            lastError = "Asked for \(Int(target * 100))%, iOS gave \(Int(actual * 100))%"
        } else {
            lastError = ""
        }
        await refreshActivity()
    }

    // MARK: Live Activity

    func startActivity() async {
        prepare()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities are turned off in iPhone Settings"
            return
        }
        let state = VolumeAttributes.ContentState(volume: volume, isMuted: isMuted)
        do {
            _ = try Activity.request(
                attributes: VolumeAttributes(),
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            lastError = ""
        } catch {
            lastError = "Could not start: \(error.localizedDescription)"
        }
    }

    func stopActivity() async {
        for activity in Activity<VolumeAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func refreshActivity() async {
        let state = VolumeAttributes.ContentState(volume: volume, isMuted: isMuted)
        for activity in Activity<VolumeAttributes>.activities {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
}
#endif
