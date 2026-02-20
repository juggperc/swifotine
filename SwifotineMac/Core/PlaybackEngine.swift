import AVFoundation
import Foundation

enum PlaybackState {
    case stopped
    case playing
    case paused
    case buffering
}

@MainActor
class PlaybackEngine: ObservableObject {
    @Published var state: PlaybackState = .stopped
    @Published var currentTrack: Track?

    private var player: AVQueuePlayer?
    private var timeObserver: Any?

    @Published var currentTime: Double = 0.0

    static let shared = PlaybackEngine()

    private init() {
        self.player = AVQueuePlayer()
        setupObservers()
    }

    private func setupObservers() {
        guard let p = player else { return }

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
    }

    func play(track: Track) {
        guard let url = URL(string: "file://" + track.localPath),
            FileManager.default.fileExists(atPath: track.localPath)
        else {
            print("File not found to play: \(track.localPath)")
            return
        }

        let item = AVPlayerItem(url: url)
        player?.replaceCurrentItem(with: item)
        player?.play()

        self.currentTrack = track
        self.state = .playing
    }

    func pause() {
        player?.pause()
        self.state = .paused
    }

    func resume() {
        player?.play()
        self.state = .playing
    }

    func stop() {
        player?.pause()
        player?.removeAllItems()
        self.currentTrack = nil
        self.state = .stopped
        self.currentTime = 0
    }
}
