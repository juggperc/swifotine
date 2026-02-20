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
                HStack(spacing: 10) {
                    ProceduralCoverView(
                        seed: coverStore.seed(
                            for: playlist.id,
                            name: playlist.name,
                            fallbackInfluence: sessionStore.username
                        ),
                        title: playlist.name,
                        cornerRadius: 8,
                        symbolScale: 0.30
                    )
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                            .lineLimit(1)
                        Text("\(sortedEntries(for: playlist).count) tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(playlist.id)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var playlistDetail: some View {
        if let playlist = selectedPlaylist {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    playlistHeader(playlist)
                    playlistTracksSection(playlist)
                    addTracksSection(playlist)
                }
                .padding(.trailing, 4)
            }
        } else {
            ContentUnavailableView(
                "No Playlist Selected",
                systemImage: "music.note.list",
                description: Text("Create a playlist or choose one from the list.")
            )
        }
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
                            HStack(spacing: 10) {
                                ProceduralCoverView(
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
                                    playbackEngine.play(track: track)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.borderless)

                                Button(role: .destructive) {
                                    removeEntry(entry, from: playlist)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.secondary.opacity(0.06))
                        )
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
