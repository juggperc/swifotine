import SwiftData
import SwiftUI

private enum LibraryLayoutMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case grid = "Grid"

    var id: String { rawValue }
}

struct LibraryView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @Query(sort: \Playlist.name) private var playlists: [Playlist]

    @EnvironmentObject private var playbackEngine: PlaybackEngine
    @Environment(\.modelContext) private var modelContext

    @AppStorage("swifotine.library.layout") private var layoutModeRaw = LibraryLayoutMode.table.rawValue
    @State private var tableSelection: Set<Track.ID> = []

    private var layoutMode: LibraryLayoutMode {
        LibraryLayoutMode(rawValue: layoutModeRaw) ?? .table
    }

    private var layoutModeBinding: Binding<LibraryLayoutMode> {
        Binding(
            get: { LibraryLayoutMode(rawValue: layoutModeRaw) ?? .table },
            set: { layoutModeRaw = $0.rawValue }
        )
    }

    private var sortedPlaylists: [Playlist] {
        playlists.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("View", selection: layoutModeBinding) {
                    ForEach(LibraryLayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                Spacer()

                Text("\(tracks.count) tracks")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if layoutMode == .table {
                tableLayout
            } else {
                gridLayout
            }
        }
        .navigationTitle("Library")
    }

    private var tableLayout: some View {
        Table(tracks, selection: $tableSelection) {
            TableColumn("Title", value: \.title)
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            if let firstID = selection.first,
                let track = tracks.first(where: { $0.id == firstID })
            {
                trackContextMenu(for: track)
            }
        } primaryAction: { selection in
            if let firstID = selection.first,
                let track = tracks.first(where: { $0.id == firstID })
            {
                playbackEngine.play(track: track)
            }
        }
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                ForEach(tracks) { track in
                    TrackGridCard(
                        track: track,
                        onPlay: { playbackEngine.play(track: track) },
                        onToggleLike: { toggleLike(track) }
                    )
                    .contextMenu {
                        trackContextMenu(for: track)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func trackContextMenu(for track: Track) -> some View {
        Button("Play") {
            playbackEngine.play(track: track)
        }

        Button("Play Next") {
            playbackEngine.playNext(track: track)
        }

        Button("Add to Queue") {
            playbackEngine.enqueue(track: track)
        }

        Button(track.isLiked ? "Unlike" : "Like") {
            toggleLike(track)
        }

        Menu("Add to Playlist") {
            if sortedPlaylists.isEmpty {
                Text("No playlists yet")
            } else {
                ForEach(sortedPlaylists) { playlist in
                    Button(playlist.name) {
                        addTrack(track, to: playlist)
                    }
                }
            }
        }
    }

    private func addTrack(_ track: Track, to playlist: Playlist) {
        let existingTrackIDs = Set(playlist.entries.compactMap { $0.track?.id })
        guard !existingTrackIDs.contains(track.id) else { return }

        let nextOrder = (playlist.entries.map(\.order).max() ?? -1) + 1
        playlist.entries.append(PlaylistEntry(order: nextOrder, track: track))
        try? modelContext.save()
    }

    private func toggleLike(_ track: Track) {
        track.isLiked.toggle()
        try? modelContext.save()
    }
}

private struct TrackGridCard: View {
    let track: Track
    let onPlay: () -> Void
    let onToggleLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackArtworkCoverView(
                track: track,
                seed: "\(track.artist)|\(track.album)",
                title: track.album
            )

            Text(track.title)
                .font(.headline)
                .lineLimit(1)

            Text(track.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Text(track.album)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    onToggleLike()
                } label: {
                    Image(systemName: track.isLiked ? "heart.fill" : "heart")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(count: 2, perform: onPlay)
    }
}

struct LikedView: View {
    @Query(
        filter: #Predicate<Track> { track in
            track.isLiked == true
        }, sort: \Track.title) private var likedTracks: [Track]

    @EnvironmentObject private var playbackEngine: PlaybackEngine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Table(likedTracks) {
            TableColumn("Title", value: \.title)
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            if let firstId = selection.first,
                let track = likedTracks.first(where: { $0.id == firstId })
            {
                Button("Play") {
                    playbackEngine.play(track: track)
                }

                Button("Unlike") {
                    track.isLiked = false
                    try? modelContext.save()
                }
            }
        } primaryAction: { selection in
            if let firstId = selection.first,
                let track = likedTracks.first(where: { $0.id == firstId })
            {
                playbackEngine.play(track: track)
            }
        }
        .navigationTitle("Liked Tracks")
    }
}
