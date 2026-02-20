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
                    if let selection = selection {
                        MainContentArea(section: selection)
                            .environmentObject(searchStore)
                            .environmentObject(downloadsStore)
                            .environmentObject(playlistCoverStore)
                            .environmentObject(playbackEngine)
                    } else {
                        Text("Select a section")
                    }
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
    var body: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.08),
                Color(NSColor.windowBackgroundColor),
                Color.accentColor.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
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
                    ArtworkThumbnail(image: playbackEngine.currentArtwork, size: 44)

                    if let track = playbackEngine.currentTrack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.headline)
                                .lineLimit(1)
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

                    Spacer()

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
