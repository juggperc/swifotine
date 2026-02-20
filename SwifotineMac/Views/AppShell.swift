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

    // Playback Engine is shared object
    @StateObject private var playbackEngine = PlaybackEngine.shared

    // Context is here
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if sessionStore.connectionState == .online {
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
                        .environmentObject(playbackEngine)
                } else {
                    Text("Select a section")
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
        Text("Home / Recommendations")
            .navigationTitle("Home")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlaylistsView: View {
    var body: some View {
        Text("Playlists")
            .navigationTitle("Playlists")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlaybackBottomBar: View {
    @EnvironmentObject var playbackEngine: PlaybackEngine

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if let track = playbackEngine.currentTrack {
                    VStack(alignment: .leading) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 200, alignment: .leading)
                } else {
                    Text("Not Playing")
                        .foregroundColor(.secondary)
                        .frame(width: 200, alignment: .leading)
                }

                Spacer()

                HStack(spacing: 20) {
                    Button(action: {
                        playbackEngine.stop()
                    }) {
                        Image(systemName: "stop.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        if playbackEngine.state == .playing {
                            playbackEngine.pause()
                        } else if playbackEngine.state == .paused {
                            playbackEngine.resume()
                        } else if let track = playbackEngine.currentTrack {
                            playbackEngine.play(track: track)
                        }
                    }) {
                        Image(
                            systemName: playbackEngine.state == .playing
                                ? "pause.circle.fill" : "play.circle.fill"
                        )
                        .resizable()
                        .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(formatTime(playbackEngine.currentTime))
                    .monospacedDigit()
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding()
            .background(.regularMaterial)
        }
    }

    private func formatTime(_ time: Double) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
