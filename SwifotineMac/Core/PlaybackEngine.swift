import AVFoundation
import AppKit
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
    @Published var currentArtwork: NSImage?
    @Published var duration: Double = 0.0
    @Published var upNext: [Track] = []
    @Published var visualizerBins: [Float] = Array(
        repeating: 0, count: AudioVisualizerTimeline.defaultBandCount)

    private var player: AVQueuePlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var metadataRequestID = UUID()
    private var visualizerRequestID = UUID()
    private var visualizerTimeline: AudioVisualizerTimeline = .silent()

    @Published var currentTime: Double = 0.0

    static let shared = PlaybackEngine()

    private init() {
        self.player = AVQueuePlayer()
        setupObservers()
    }

    private func setupObservers() {
        guard let p = player else { return }

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds
                self.updateVisualizer(at: time.seconds)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.playNextFromQueueOrStop()
            }
        }
    }

    func play(track: Track, queueAfter: [Track] = []) {
        upNext = queueAfter.filter {
            FileManager.default.fileExists(atPath: $0.localPath)
        }
        playTrack(track)
    }

    func enqueue(track: Track) {
        guard FileManager.default.fileExists(atPath: track.localPath) else { return }
        upNext.append(track)
    }

    func enqueue(tracks: [Track]) {
        for track in tracks {
            enqueue(track: track)
        }
    }

    func playNext(track: Track) {
        guard FileManager.default.fileExists(atPath: track.localPath) else { return }

        if currentTrack == nil {
            play(track: track)
            return
        }

        upNext.insert(track, at: 0)
    }

    func skipToNextInQueue() {
        playNextFromQueueOrStop()
    }

    func clearQueue() {
        upNext.removeAll()
    }

    private func playTrack(_ track: Track) {
        let url = URL(fileURLWithPath: track.localPath)
        guard
            FileManager.default.fileExists(atPath: track.localPath)
        else {
            print("File not found to play: \(track.localPath)")
            return
        }

        currentTime = 0
        duration = 0
        currentArtwork = nil
        resetVisualizer()

        let item = AVPlayerItem(url: url)
        player?.replaceCurrentItem(with: item)
        player?.play()

        self.currentTrack = track
        self.state = .playing
        let requestID = UUID()
        metadataRequestID = requestID
        visualizerRequestID = requestID
        loadMetadata(for: track, url: url, requestID: requestID)
        loadVisualizerTimeline(for: url, requestID: requestID)
    }

    func pause() {
        player?.pause()
        self.state = .paused
    }

    func resume() {
        player?.play()
        self.state = .playing
    }

    func togglePlayPause() {
        switch state {
        case .playing:
            pause()
        case .paused:
            resume()
        case .stopped:
            if let track = currentTrack {
                playTrack(track)
            }
        case .buffering:
            break
        }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, min(seconds, max(duration, 0)))
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    func seek(by delta: Double) {
        seek(to: currentTime + delta)
    }

    func stop() {
        player?.pause()
        player?.removeAllItems()
        clearQueue()
        self.currentTrack = nil
        self.currentArtwork = nil
        self.state = .stopped
        self.currentTime = 0
        self.duration = 0
        resetVisualizer()
    }

    func showMiniPlayer() {
        MiniPlayerWindowController.shared.show(playbackEngine: self)
    }

    func toggleMiniPlayer() {
        MiniPlayerWindowController.shared.toggle(playbackEngine: self)
    }

    private func playNextFromQueueOrStop() {
        while !upNext.isEmpty {
            let candidate = upNext.removeFirst()
            if FileManager.default.fileExists(atPath: candidate.localPath) {
                playTrack(candidate)
                return
            }
        }

        state = .stopped
        currentTime = duration
        resetVisualizer()
    }

    private func loadMetadata(for track: Track, url: URL, requestID: UUID) {
        Task { [weak self] in
            guard let self else { return }

            let asset = AVURLAsset(url: url)
            let loadedDuration = (try? await asset.load(.duration)) ?? .zero
            let rawDuration = CMTimeGetSeconds(loadedDuration)
            let resolvedArtwork = await EmbeddedArtworkLoader.load(
                localPath: url.path,
                artist: track.artist,
                album: track.album
            )

            guard requestID == metadataRequestID else { return }
            duration = rawDuration.isFinite ? rawDuration : 0
            currentArtwork = resolvedArtwork
        }
    }

    private func loadVisualizerTimeline(for url: URL, requestID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let timeline = await AudioVisualizerAnalyzer.shared.timeline(for: url)
            guard requestID == self.visualizerRequestID else { return }
            self.visualizerTimeline = timeline
        }
    }

    private func updateVisualizer(at seconds: Double) {
        let targetBins: [Float]
        switch state {
        case .playing:
            targetBins = visualizerTimeline.bands(at: seconds)
        case .paused:
            targetBins = visualizerBins.map { $0 * 0.985 }
        case .stopped, .buffering:
            targetBins = Array(repeating: 0, count: visualizerBins.count)
        }

        if visualizerBins.count != targetBins.count {
            visualizerBins = targetBins
            return
        }

        var smoothed = visualizerBins
        for index in 0..<targetBins.count {
            let current = visualizerBins[index]
            let target = targetBins[index]
            let interpolation: Float = target > current ? 0.46 : 0.24
            smoothed[index] = current + ((target - current) * interpolation)
        }
        visualizerBins = smoothed
    }

    private func resetVisualizer() {
        visualizerTimeline = .silent()
        visualizerBins = Array(repeating: 0, count: AudioVisualizerTimeline.defaultBandCount)
    }
}
