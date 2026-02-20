import SwiftData
import SwiftUI

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var playbackEngine: PlaybackEngine
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var coverStore: PlaylistCoverStore

    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @Query(sort: \Track.title) private var libraryTracks: [Track]

    @State private var selectedPlaylistID: Playlist.ID?
    @State private var newPlaylistName = ""
    @State private var newCoverInfluence = ""
    @State private var detailCoverInfluence = ""
    @State private var addTrackFilter = ""

    private var sortedPlaylists: [Playlist] {
        playlists.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private var playlistIDs: [Playlist.ID] {
        sortedPlaylists.map(\.id)
    }

    private var selectedPlaylist: Playlist? {
        guard let selectedPlaylistID else { return nil }
        return sortedPlaylists.first(where: { $0.id == selectedPlaylistID })
    }

    var body: some View {
        VStack(spacing: 12) {
            createPlaylistBar

            Divider()

            HSplitView {
                playlistList
                    .frame(minWidth: 250, maxWidth: 320)

                playlistDetail
                    .frame(minWidth: 540)
            }
        }
        .padding(14)
        .navigationTitle("Playlists")
        .onAppear {
            if selectedPlaylistID == nil {
                selectedPlaylistID = sortedPlaylists.first?.id
            }
            if newCoverInfluence.isEmpty, !sessionStore.username.isEmpty {
                newCoverInfluence = sessionStore.username
            }
            coverStore.pruneOrphaned(keeping: Set(playlistIDs))
            syncDetailInfluence()
        }
        .onChange(of: playlistIDs) { _, newIDs in
            if let selectedPlaylistID, !newIDs.contains(selectedPlaylistID) {
                self.selectedPlaylistID = newIDs.first
            } else if selectedPlaylistID == nil {
                selectedPlaylistID = newIDs.first
            }

            coverStore.pruneOrphaned(keeping: Set(newIDs))
            syncDetailInfluence()
        }
        .onChange(of: selectedPlaylistID) { _, _ in
            syncDetailInfluence()
        }
    }

    private var createPlaylistBar: some View {
        HStack(spacing: 10) {
            TextField("New playlist name", text: $newPlaylistName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 210)

            TextField("Cover influence (optional)", text: $newCoverInfluence)
                .textFieldStyle(.roundedBorder)

            Button("Create Playlist") {
                createPlaylist()
            }
            .buttonStyle(.borderedProminent)
            .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var playlistList: some View {
        List(selection: $selectedPlaylistID) {
            ForEach(sortedPlaylists) { playlist in
                PlaylistSidebarRow(
                    playlist: playlist,
                    trackCount: sortedEntries(for: playlist).count,
                    seed: coverStore.seed(
                        for: playlist.id,
                        name: playlist.name,
                        fallbackInfluence: sessionStore.username
                    ),
                    isSelected: playlist.id == selectedPlaylistID
                )
                .tag(playlist.id)
            }
        }
        .listStyle(.sidebar)
        .animation(.easeInOut(duration: 0.2), value: selectedPlaylistID)
    }

    @ViewBuilder
    private var playlistDetail: some View {
        Group {
            if let playlist = selectedPlaylist {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        playlistHeader(playlist)
                        playlistTracksSection(playlist)
                        addTracksSection(playlist)
                    }
                    .padding(.trailing, 4)
                }
                .id(playlist.id)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                ContentUnavailableView(
                    "No Playlist Selected",
                    systemImage: "music.note.list",
                    description: Text("Create a playlist or choose one from the list.")
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selectedPlaylistID)
    }

    private func playlistHeader(_ playlist: Playlist) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ProceduralCoverView(
                seed: coverStore.seed(
                    for: playlist.id, name: playlist.name, fallbackInfluence: sessionStore.username),
                title: playlist.name,
                cornerRadius: 18
            )
            .frame(width: 176, height: 176)

            VStack(alignment: .leading, spacing: 10) {
                Text(playlist.name)
                    .font(.title2.weight(.semibold))

                Text("\(sortedEntries(for: playlist).count) tracks")
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Play Playlist") {
                        playPlaylist(playlist)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Queue Playlist") {
                        enqueuePlaylist(playlist)
                    }
                    .buttonStyle(.bordered)
                }

                TextField("Cover influence", text: $detailCoverInfluence)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("Apply Influence") {
                        coverStore.setInfluence(detailCoverInfluence, for: playlist.id)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Regenerate Cover") {
                        coverStore.regenerate(for: playlist.id)
                    }
                    .buttonStyle(.bordered)

                    Button("Delete Playlist", role: .destructive) {
                        deletePlaylist(playlist)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
    }

    private func playlistTracksSection(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playlist Tracks")
                .font(.headline)

            let entries = sortedEntries(for: playlist)
            if entries.isEmpty {
                Text("Add tracks from your library to start building this playlist.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(entries) { entry in
                        if let track = entry.track {
                            HoverRowCard(cornerRadius: 10, baseOpacity: 0.08) {
                                HStack(spacing: 10) {
                                    TrackArtworkCoverView(
                                        track: track,
                                        seed: "\(track.artist)|\(track.album)",
                                        title: track.album,
                                        cornerRadius: 8,
                                        symbolScale: 0.30
                                    )
                                    .frame(width: 40, height: 40)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .lineLimit(1)
                                        Text("\(track.artist) - \(track.album)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button {
                                        playPlaylist(from: track, in: playlist)
                                    } label: {
                                        Image(systemName: "play.fill")
                                    }
                                    .buttonStyle(.borderless)

                                    Button {
                                        playbackEngine.playNext(track: track)
                                    } label: {
                                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                    }
                                    .buttonStyle(.borderless)

                                    Button {
                                        playbackEngine.enqueue(track: track)
                                    } label: {
                                        Image(systemName: "text.badge.plus")
                                    }
                                    .buttonStyle(.borderless)

                                    Button(role: .destructive) {
                                        removeEntry(entry, from: playlist)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addTracksSection(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Tracks")
                .font(.headline)

            TextField("Filter library tracks", text: $addTrackFilter)
                .textFieldStyle(.roundedBorder)

            let candidates = addableTracks(for: playlist).prefix(40)
            if candidates.isEmpty {
                Text("No matching tracks available.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(Array(candidates), id: \.id) { track in
                        HoverRowCard(cornerRadius: 9, baseOpacity: 0.06, verticalPadding: 6) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .lineLimit(1)
                                    Text("\(track.artist) - \(track.album)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Add") {
                                    addTrack(track, to: playlist)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let playlist = Playlist(name: name)
        modelContext.insert(playlist)

        let initialInfluence = newCoverInfluence.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = initialInfluence.isEmpty ? sessionStore.username : initialInfluence
        coverStore.ensureProfile(for: playlist.id, fallbackInfluence: fallback)

        try? modelContext.save()

        selectedPlaylistID = playlist.id
        newPlaylistName = ""
        detailCoverInfluence = coverStore.influence(for: playlist.id, fallbackInfluence: fallback)
    }

    private func deletePlaylist(_ playlist: Playlist) {
        modelContext.delete(playlist)
        try? modelContext.save()

        if selectedPlaylistID == playlist.id {
            selectedPlaylistID = sortedPlaylists.first(where: { $0.id != playlist.id })?.id
        }
    }

    private func addTrack(_ track: Track, to playlist: Playlist) {
        let existingTrackIDs = Set(playlist.entries.compactMap { $0.track?.id })
        guard !existingTrackIDs.contains(track.id) else { return }

        let nextOrder = (playlist.entries.map(\.order).max() ?? -1) + 1
        playlist.entries.append(PlaylistEntry(order: nextOrder, track: track))
        try? modelContext.save()
    }

    private func removeEntry(_ entry: PlaylistEntry, from playlist: Playlist) {
        playlist.entries.removeAll(where: { $0.id == entry.id })
        modelContext.delete(entry)

        let sorted = playlist.entries.sorted(by: { $0.order < $1.order })
        for (index, value) in sorted.enumerated() {
            value.order = index
        }

        try? modelContext.save()
    }

    private func sortedEntries(for playlist: Playlist) -> [PlaylistEntry] {
        playlist.entries.sorted { $0.order < $1.order }
    }

    private func orderedTracks(for playlist: Playlist) -> [Track] {
        sortedEntries(for: playlist).compactMap(\.track)
    }

    private func playPlaylist(_ playlist: Playlist) {
        let tracks = orderedTracks(for: playlist)
        guard let first = tracks.first else { return }
        playbackEngine.play(track: first, queueAfter: Array(tracks.dropFirst()))
    }

    private func playPlaylist(from track: Track, in playlist: Playlist) {
        let tracks = orderedTracks(for: playlist)
        guard let startIndex = tracks.firstIndex(where: { $0.id == track.id }) else {
            playbackEngine.play(track: track)
            return
        }

        playbackEngine.play(
            track: tracks[startIndex],
            queueAfter: Array(tracks.dropFirst(startIndex + 1))
        )
    }

    private func enqueuePlaylist(_ playlist: Playlist) {
        playbackEngine.enqueue(tracks: orderedTracks(for: playlist))
    }

    private func addableTracks(for playlist: Playlist) -> [Track] {
        let existingIDs = Set(playlist.entries.compactMap { $0.track?.id })
        let filter = addTrackFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return libraryTracks.filter { track in
            guard !existingIDs.contains(track.id) else { return false }
            guard !filter.isEmpty else { return true }

            let haystack = "\(track.title) \(track.artist) \(track.album)".lowercased()
            return haystack.contains(filter)
        }
    }

    private func syncDetailInfluence() {
        guard let playlist = selectedPlaylist else {
            detailCoverInfluence = ""
            return
        }

        detailCoverInfluence = coverStore.influence(
            for: playlist.id,
            fallbackInfluence: sessionStore.username
        )
    }
}

private struct PlaylistSidebarRow: View {
    let playlist: Playlist
    let trackCount: Int
    let seed: String
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ProceduralCoverView(
                seed: seed,
                title: playlist.name,
                cornerRadius: 8,
                symbolScale: 0.30
            )
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .lineLimit(1)
                Text("\(trackCount) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected || isHovering ? 1 : 0)
        }
        .shadow(color: Color.black.opacity(isHovering && !isSelected ? 0.08 : 0), radius: 8, y: 3)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        return isHovering ? Color.secondary.opacity(0.11) : Color.clear
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.35)
        }
        return Color.primary.opacity(0.12)
    }
}

private struct HoverRowCard<Content: View>: View {
    let cornerRadius: CGFloat
    let baseOpacity: Double
    let verticalPadding: CGFloat
    let content: Content
    @State private var isHovering = false

    init(cornerRadius: CGFloat, baseOpacity: Double, verticalPadding: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.baseOpacity = baseOpacity
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(isHovering ? baseOpacity + 0.05 : baseOpacity))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isHovering ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(isHovering ? 0.08 : 0), radius: 8, y: 4)
            .scaleEffect(isHovering ? 1.006 : 1)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
