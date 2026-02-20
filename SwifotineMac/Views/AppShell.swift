import AppKit
import SwiftData
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case search = "Search"
    case downloads = "Downloads"
    case library = "Library"
    case playlists = "Playlists"
    case liked = "Liked"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .downloads: return "arrow.down.circle"
        case .library: return "music.note.list"
        case .playlists: return "list.bullet.rectangle"
        case .liked: return "heart"
        }
    }
}

struct AppShell: View {
    @EnvironmentObject var sessionStore: SessionStore
    @State private var selection: SidebarSection? = .search

    // Inject globally
    @StateObject private var downloadsStore = DownloadsStore()
    @StateObject private var searchStore = SearchStore()
    @StateObject private var playlistCoverStore = PlaylistCoverStore()

    // Playback Engine is shared object
    @StateObject private var playbackEngine = PlaybackEngine.shared

    // Context is here
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if sessionStore.connectionState == .online {
            ZStack {
                AppBackdrop()

                NavigationSplitView {
                    List(selection: $selection) {
                        ForEach(SidebarSection.allCases) { section in
                            Label(section.rawValue, systemImage: section.iconName)
                                .tag(section)
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("Swifotine")
                } detail: {
                    ZStack {
                        if let selection = selection {
                            MainContentArea(section: selection)
                                .environmentObject(searchStore)
                                .environmentObject(downloadsStore)
                                .environmentObject(playlistCoverStore)
                                .environmentObject(playbackEngine)
                                .id(selection.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        } else {
                            Text("Select a section")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(.easeInOut(duration: 0.22), value: selection)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PlaybackBottomBar()
                    .environmentObject(playbackEngine)
            }
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                downloadsStore.setup(modelContext: modelContext)
            }
        } else {
            LoginView()
        }
    }
}

struct MainContentArea: View {
    var section: SidebarSection

    var body: some View {
        switch section {
        case .search:
            SearchView()
        case .downloads:
            DownloadsView()
        case .library:
            LibraryView()
        case .liked:
            LikedView()
        case .playlists:
            PlaylistsView()
        case .home:
            HomeView()
        }
    }
}

struct HomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Swifotine")
                .font(.title2.weight(.semibold))

            Text("Search, download, and play your library with a native macOS workflow.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("View Acknowledgements") {
                AcknowledgementsWindowController.shared.show()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Home")
    }
}

struct AppBackdrop: View {
    @State private var animateBackdrop = false
    @State private var breatheBackdrop = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.09),
                        Color(NSColor.windowBackgroundColor),
                        Color.accentColor.opacity(0.05),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.accentColor.opacity(0.11))
                    .frame(width: proxy.size.width * 0.55, height: proxy.size.width * 0.55)
                    .blur(radius: 42)
                    .offset(
                        x: animateBackdrop ? proxy.size.width * 0.2 : -proxy.size.width * 0.16,
                        y: animateBackdrop ? -proxy.size.height * 0.18 : -proxy.size.height * 0.04
                    )
                    .scaleEffect(breatheBackdrop ? 1.06 : 0.94)

                Circle()
                    .fill(Color.blue.opacity(0.09))
                    .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
                    .blur(radius: 36)
                    .offset(
                        x: animateBackdrop ? -proxy.size.width * 0.16 : proxy.size.width * 0.14,
                        y: animateBackdrop ? proxy.size.height * 0.14 : proxy.size.height * 0.02
                    )
                    .scaleEffect(breatheBackdrop ? 0.95 : 1.05)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                animateBackdrop.toggle()
            }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                breatheBackdrop.toggle()
            }
        }
    }
}

struct PlaybackBottomBar: View {
    @EnvironmentObject var playbackEngine: PlaybackEngine
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text(formatTime(playbackEngine.currentTime))
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubTime : playbackEngine.currentTime },
                            set: { newValue in scrubTime = newValue }
                        ),
                        in: 0...max(playbackEngine.duration, 1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                playbackEngine.seek(to: scrubTime)
                            }
                        }
                    )

                    Text(formatTime(playbackEngine.duration))
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ArtworkThumbnail(image: playbackEngine.currentArtwork, size: 44)

                        if let track = playbackEngine.currentTrack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if playbackEngine.state == .playing {
                                        NowPlayingPulseDot()
                                    }

                                    Text(track.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                }
                                Text(track.artist)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                if let queuedTrack = playbackEngine.upNext.first {
                                    Text("Up next: \(queuedTrack.title)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: 280, alignment: .leading)
                        } else {
                            Text("Not Playing")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: 280, alignment: .leading)
                        }
                    }

                    Spacer(minLength: 12)

                    InlineWaveformVisualizerView(
                        bands: playbackEngine.visualizerBins,
                        isPlaying: playbackEngine.state == .playing
                    )
                    .frame(minWidth: 220, idealWidth: 380, maxWidth: 520)
                    .layoutPriority(1)
                    .accessibilityLabel("Music Visualizer")

                    Spacer(minLength: 12)

                    HStack(spacing: 12) {
                        Button {
                            playbackEngine.seek(by: -10)
                        } label: {
                            Image(systemName: "gobackward.10")
                        }
                        .help("Back 10 Seconds")

                        Button {
                            playbackEngine.togglePlayPause()
                        } label: {
                            Image(systemName: playbackEngine.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28))
                        }
                        .help("Play or Pause")

                        Button {
                            playbackEngine.seek(by: 10)
                        } label: {
                            Image(systemName: "goforward.10")
                        }
                        .help("Forward 10 Seconds")

                        Button {
                            playbackEngine.skipToNextInQueue()
                        } label: {
                            Image(systemName: "forward.end.fill")
                        }
                        .disabled(playbackEngine.upNext.isEmpty)
                        .help("Next in Queue")

                        Button {
                            playbackEngine.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .help("Stop Playback")

                        Divider()
                            .frame(height: 20)

                        Button {
                            playbackEngine.toggleMiniPlayer()
                        } label: {
                            Image(systemName: "pip")
                        }
                        .help("Open Mini Player")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .onChange(of: playbackEngine.currentTime) { _, newValue in
            if !isScrubbing {
                scrubTime = newValue
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite, time > 0 else { return "00:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct NowPlayingPulseDot: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            let opacity = 0.45 + (phase * 0.5)
            let scale = 0.72 + (phase * 0.28)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .opacity(opacity)
                .scaleEffect(scale)
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

private struct InlineWaveformVisualizerView: View {
    let bands: [Float]
    let isPlaying: Bool

    private var normalizedBands: [Float] {
        if bands.isEmpty {
            return Array(repeating: 0, count: AudioVisualizerTimeline.defaultBandCount)
        }
        return bands
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                guard size.width > 40, size.height > 12 else { return }

                let frameBands = normalizedBands
                let bandCount = frameBands.count
                let midY = size.height / 2
                let width = size.width
                let maxAmplitude = size.height * 0.42
                let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate * 2.4)

                let aggregateEnergy = frameBands.reduce(0, +) / Float(max(frameBands.count, 1))
                let activeMultiplier: CGFloat = isPlaying ? 1 : 0.35
                let energyBoost = CGFloat(min(max(aggregateEnergy, 0), 1)) * 0.18

                var upperPoints: [CGPoint] = []
                var lowerPoints: [CGPoint] = []
                upperPoints.reserveCapacity(bandCount)
                lowerPoints.reserveCapacity(bandCount)

                for index in 0..<bandCount {
                    let xPosition = CGFloat(index) / CGFloat(max(bandCount - 1, 1))
                    let x = xPosition * width
                    let bandValue = CGFloat(min(max(frameBands[index], 0), 1))
                    let perceptual = pow(bandValue, 0.75)
                    let taper = sin(xPosition * .pi)
                    let shimmer = isPlaying ? (sin(phase + CGFloat(index) * 0.42) * 0.7) : 0
                    let amplitude =
                        max(1.2, ((perceptual + energyBoost) * maxAmplitude * taper * activeMultiplier) + shimmer)

                    upperPoints.append(CGPoint(x: x, y: midY - amplitude))
                    lowerPoints.append(CGPoint(x: x, y: midY + amplitude))
                }

                var fillPath = Path()
                if let first = upperPoints.first {
                    fillPath.move(to: first)
                    for point in upperPoints.dropFirst() {
                        fillPath.addLine(to: point)
                    }
                    for point in lowerPoints.reversed() {
                        fillPath.addLine(to: point)
                    }
                    fillPath.closeSubpath()
                }

                let topStroke = smoothPath(points: upperPoints)
                let bottomStroke = smoothPath(points: lowerPoints)

                let fillGradient = Gradient(colors: [
                    Color.accentColor.opacity(0.18),
                    Color.cyan.opacity(0.06),
                    Color.accentColor.opacity(0.18),
                ])
                context.fill(
                    fillPath,
                    with: .linearGradient(
                        fillGradient,
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: width, y: size.height)
                    )
                )

                context.stroke(
                    topStroke,
                    with: .linearGradient(
                        Gradient(colors: [Color.cyan.opacity(0.85), Color.accentColor.opacity(0.95)]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: width, y: midY)
                    ),
                    lineWidth: 2.0
                )
                context.stroke(
                    bottomStroke,
                    with: .linearGradient(
                        Gradient(colors: [Color.accentColor.opacity(0.95), Color.cyan.opacity(0.85)]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: width, y: midY)
                    ),
                    lineWidth: 1.65
                )

                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: midY))
                baseline.addLine(to: CGPoint(x: width, y: midY))
                context.stroke(
                    baseline,
                    with: .color(Color.white.opacity(0.08)),
                    style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
                )
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        guard let first = points.first else { return Path() }
        guard points.count > 1 else {
            var singlePath = Path()
            singlePath.move(to: first)
            return singlePath
        }

        var path = Path()
        path.move(to: first)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )

            if index == 1 {
                path.addLine(to: midpoint)
            } else {
                path.addQuadCurve(to: midpoint, control: previous)
            }

            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: midpoint)
            }
        }

        return path
    }
}
