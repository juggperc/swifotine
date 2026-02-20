import AppKit
import SwiftData
import SwiftUI

private enum LibraryLayoutMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case grid = "Grid"
    case albums = "Albums"

    var id: String { rawValue }
}

private enum LibrarySortMode: String, CaseIterable, Identifiable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case recent = "Recently Added"
    case duration = "Duration"

    var id: String { rawValue }
}

private struct AlbumBucket: Identifiable {
    let id: String
    let title: String
    let artist: String
    let tracks: [Track]
    let totalDuration: Int

    var leadTrack: Track? {
        tracks.first
    }
}

struct LibraryView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @Query(sort: \Playlist.name) private var playlists: [Playlist]

    @EnvironmentObject private var playbackEngine: PlaybackEngine
    @Environment(\.modelContext) private var modelContext

    @AppStorage("swifotine.library.layout") private var layoutModeRaw = LibraryLayoutMode.table.rawValue
    @AppStorage("swifotine.library.sort") private var sortModeRaw = LibrarySortMode.title.rawValue
    @State private var tableSelection: Set<Track.ID> = []
    @State private var filterText = ""
    @State private var showOnlyLiked = false
    @State private var selectedAlbumID: String?

    private var layoutMode: LibraryLayoutMode {
        LibraryLayoutMode(rawValue: layoutModeRaw) ?? .table
    }

    private var sortMode: LibrarySortMode {
        LibrarySortMode(rawValue: sortModeRaw) ?? .title
    }

    private var layoutModeBinding: Binding<LibraryLayoutMode> {
        Binding(
            get: { LibraryLayoutMode(rawValue: layoutModeRaw) ?? .table },
            set: { layoutModeRaw = $0.rawValue }
        )
    }

    private var sortModeBinding: Binding<LibrarySortMode> {
        Binding(
            get: { LibrarySortMode(rawValue: sortModeRaw) ?? .title },
            set: { sortModeRaw = $0.rawValue }
        )
    }

    private var sortedPlaylists: [Playlist] {
        playlists.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var filteredTracks: [Track] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return tracks.filter { track in
            if showOnlyLiked && !track.isLiked {
                return false
            }

            guard !query.isEmpty else { return true }

            let haystack = "\(track.title) \(track.artist) \(track.album) \(track.localPath)".lowercased()
            return haystack.contains(query)
        }
    }

    private var visibleTracks: [Track] {
        filteredTracks.sorted(by: sortComparator(lhs:rhs:))
    }

    private var visibleTrackCount: Int {
        visibleTracks.count
    }

    private var visibleDuration: Int {
        visibleTracks.reduce(0) { partial, track in
            partial + max(track.duration, 0)
        }
    }

    private var missingTracks: [Track] {
        tracks.filter { !FileManager.default.fileExists(atPath: $0.localPath) }
    }

    private var albumBuckets: [AlbumBucket] {
        var grouped: [String: [Track]] = [:]
        for track in visibleTracks {
            let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Artist" : track.artist
            let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Album" : track.album
            let key = "\(artist.lowercased())|\(album.lowercased())"
            grouped[key, default: []].append(track)
        }

        return grouped.compactMap { key, groupedTracks in
            guard !groupedTracks.isEmpty else { return nil }
            let sortedTracks = groupedTracks.sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            let first = sortedTracks[0]
            return AlbumBucket(
                id: key,
                title: first.album,
                artist: first.artist,
                tracks: sortedTracks,
                totalDuration: sortedTracks.reduce(0) { $0 + max($1.duration, 0) }
            )
        }
        .sorted { lhs, rhs in
            let titleCompare = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleCompare != .orderedSame {
                return titleCompare == .orderedAscending
            }
            return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending
        }
    }

    private var albumBucketIDs: [String] {
        albumBuckets.map(\.id)
    }

    private var selectedAlbumBucket: AlbumBucket? {
        guard let selectedAlbumID else { return albumBuckets.first }
        return albumBuckets.first(where: { $0.id == selectedAlbumID }) ?? albumBuckets.first
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsPanel
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)

            Group {
                switch layoutMode {
                case .table:
                    tableLayout
                        .transition(.opacity.combined(with: .move(edge: .top)))
                case .grid:
                    gridLayout
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .albums:
                    albumsLayout
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: layoutMode)
        }
        .navigationTitle("Library")
        .onAppear {
            syncSelectedAlbum()
        }
        .onChange(of: albumBucketIDs) { _, _ in
            syncSelectedAlbum()
        }
    }

    private var controlsPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Picker("View", selection: layoutModeBinding) {
                    ForEach(LibraryLayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)

                Picker("Sort", selection: sortModeBinding) {
                    ForEach(LibrarySortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)

                Toggle("Liked Only", isOn: $showOnlyLiked)
                    .toggleStyle(.checkbox)

                Spacer()

                Text("\(visibleTrackCount) tracks · \(formatTotalDuration(visibleDuration))")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Filter library tracks, artists, albums, paths", text: $filterText)
                    .textFieldStyle(.roundedBorder)

                Menu {
                    Button("Play Filtered (\(visibleTracks.count))") {
                        playTracks(visibleTracks)
                    }
                    .disabled(visibleTracks.isEmpty)

                    Button("Queue Filtered (\(visibleTracks.count))") {
                        playbackEngine.enqueue(tracks: visibleTracks)
                    }
                    .disabled(visibleTracks.isEmpty)

                    if !tableSelection.isEmpty {
                        Divider()
                        Button("Play Selected (\(tableSelection.count))") {
                            playTracks(tracksForSelection(tableSelection))
                        }
                        Button("Queue Selected (\(tableSelection.count))") {
                            playbackEngine.enqueue(tracks: tracksForSelection(tableSelection))
                        }
                        .disabled(tracksForSelection(tableSelection).isEmpty)
                    }

                    Divider()

                    Menu("Add Filtered to Playlist") {
                        if sortedPlaylists.isEmpty {
                            Text("No playlists yet")
                        } else {
                            ForEach(sortedPlaylists) { playlist in
                                Button(playlist.name) {
                                    addTracks(visibleTracks, to: playlist)
                                }
                            }
                        }
                    }
                    .disabled(visibleTracks.isEmpty)
                } label: {
                    Label("Batch", systemImage: "square.stack.3d.down.right")
                }

                Menu {
                    Button("Remove Missing Files (\(missingTracks.count))", role: .destructive) {
                        removeTracks(missingTracks)
                    }
                    .disabled(missingTracks.isEmpty)

                    Button("Prune Empty Playlist Entries") {
                        pruneOrphanedPlaylistEntries()
                    }

                    if !tableSelection.isEmpty {
                        Divider()
                        Button("Clear Table Selection") {
                            tableSelection.removeAll()
                        }
                    }
                } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private var tableLayout: some View {
        Table(visibleTracks, selection: $tableSelection) {
            TableColumn("Title", value: \.title)
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
            TableColumn("Duration") { track in
                Text(formatTrackDuration(track.duration))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            let selectedTracks = tracksForSelection(selection)
            if selectedTracks.count > 1 {
                multiTrackContextMenu(for: selectedTracks)
            } else if let track = selectedTracks.first {
                trackContextMenu(for: track)
            }
        } primaryAction: { selection in
            let selectedTracks = tracksForSelection(selection)
            playTracks(selectedTracks)
        }
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                ForEach(visibleTracks) { track in
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

    private var albumsLayout: some View {
        VStack(spacing: 12) {
            if albumBuckets.isEmpty {
                ContentUnavailableView(
                    "No Albums to Show",
                    systemImage: "square.stack",
                    description: Text("Adjust your filters or add tracks to your library.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(albumBuckets) { bucket in
                            AlbumShelfCard(
                                bucket: bucket,
                                isSelected: bucket.id == selectedAlbumBucket?.id,
                                onSelect: { selectedAlbumID = bucket.id },
                                onPlay: { playTracks(bucket.tracks) },
                                onQueue: { playbackEngine.enqueue(tracks: bucket.tracks) }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }
                .frame(height: 235)

                Divider()
                    .padding(.horizontal)

                if let selectedAlbumBucket {
                    AlbumDetailList(
                        bucket: selectedAlbumBucket,
                        onPlayTrack: { playbackEngine.play(track: $0) },
                        onQueueTrack: { playbackEngine.enqueue(track: $0) },
                        onLikeTrack: { toggleLike($0) }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
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

        if FileManager.default.fileExists(atPath: track.localPath) {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(track.localPath, inFileViewerRootedAtPath: "")
            }
        }

        Button("Remove from Library", role: .destructive) {
            removeTracks([track])
        }

        Menu("Add to Playlist") {
            if sortedPlaylists.isEmpty {
                Text("No playlists yet")
            } else {
                ForEach(sortedPlaylists) { playlist in
                    Button(playlist.name) {
                        addTracks([track], to: playlist)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func multiTrackContextMenu(for tracks: [Track]) -> some View {
        Button("Play Selection") {
            playTracks(tracks)
        }

        Button("Queue Selection") {
            playbackEngine.enqueue(tracks: tracks)
        }

        Button("Like Selection") {
            setLikeState(for: tracks, liked: true)
        }

        Button("Unlike Selection") {
            setLikeState(for: tracks, liked: false)
        }

        Button("Remove Selection", role: .destructive) {
            removeTracks(tracks)
        }

        Menu("Add Selection to Playlist") {
            if sortedPlaylists.isEmpty {
                Text("No playlists yet")
            } else {
                ForEach(sortedPlaylists) { playlist in
                    Button(playlist.name) {
                        addTracks(tracks, to: playlist)
                    }
                }
            }
        }
    }

    private func tracksForSelection(_ selection: Set<Track.ID>) -> [Track] {
        visibleTracks.filter { selection.contains($0.id) }
    }

    private func addTracks(_ tracks: [Track], to playlist: Playlist) {
        guard !tracks.isEmpty else { return }

        var existingTrackIDs = Set(playlist.entries.compactMap { $0.track?.id })
        var nextOrder = (playlist.entries.map(\.order).max() ?? -1) + 1

        for track in tracks where !existingTrackIDs.contains(track.id) {
            playlist.entries.append(PlaylistEntry(order: nextOrder, track: track))
            existingTrackIDs.insert(track.id)
            nextOrder += 1
        }

        try? modelContext.save()
    }

    private func toggleLike(_ track: Track) {
        track.isLiked.toggle()
        try? modelContext.save()
    }

    private func setLikeState(for tracks: [Track], liked: Bool) {
        for track in tracks {
            track.isLiked = liked
        }
        try? modelContext.save()
    }

    private func playTracks(_ tracks: [Track]) {
        let existingTracks = tracks.filter { FileManager.default.fileExists(atPath: $0.localPath) }
        guard let firstTrack = existingTracks.first else { return }
        playbackEngine.play(track: firstTrack, queueAfter: Array(existingTracks.dropFirst()))
    }

    private func removeTracks(_ tracksToRemove: [Track]) {
        let trackIDs = Set(tracksToRemove.map(\.id))
        guard !trackIDs.isEmpty else { return }

        for playlist in playlists {
            let removedEntries = playlist.entries.filter { entry in
                guard let track = entry.track else { return false }
                return trackIDs.contains(track.id)
            }

            guard !removedEntries.isEmpty else { continue }

            playlist.entries.removeAll { entry in
                removedEntries.contains(where: { $0.id == entry.id })
            }
            for entry in removedEntries {
                modelContext.delete(entry)
            }
            reindexEntries(in: playlist)
        }

        for track in tracksToRemove {
            modelContext.delete(track)
        }

        try? modelContext.save()
        tableSelection.subtract(trackIDs)
        syncSelectedAlbum()
    }

    private func pruneOrphanedPlaylistEntries() {
        for playlist in playlists {
            let orphanedEntries = playlist.entries.filter { $0.track == nil }
            guard !orphanedEntries.isEmpty else { continue }

            playlist.entries.removeAll { entry in
                orphanedEntries.contains(where: { $0.id == entry.id })
            }
            for entry in orphanedEntries {
                modelContext.delete(entry)
            }
            reindexEntries(in: playlist)
        }

        try? modelContext.save()
    }

    private func reindexEntries(in playlist: Playlist) {
        let sorted = playlist.entries.sorted(by: { $0.order < $1.order })
        for (index, entry) in sorted.enumerated() {
            entry.order = index
        }
    }

    private func syncSelectedAlbum() {
        if let selectedAlbumID, albumBucketIDs.contains(selectedAlbumID) {
            return
        }
        selectedAlbumID = albumBucketIDs.first
    }

    private func sortComparator(lhs: Track, rhs: Track) -> Bool {
        switch sortMode {
        case .title:
            let titleCompare = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleCompare != .orderedSame {
                return titleCompare == .orderedAscending
            }
            return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending

        case .artist:
            let artistCompare = lhs.artist.localizedCaseInsensitiveCompare(rhs.artist)
            if artistCompare != .orderedSame {
                return artistCompare == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending

        case .album:
            let albumCompare = lhs.album.localizedCaseInsensitiveCompare(rhs.album)
            if albumCompare != .orderedSame {
                return albumCompare == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending

        case .recent:
            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt > rhs.addedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending

        case .duration:
            if lhs.duration != rhs.duration {
                return lhs.duration > rhs.duration
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func formatTrackDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "--:--" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatTotalDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "--" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct TrackGridCard: View {
    let track: Track
    let onPlay: () -> Void
    let onToggleLike: () -> Void
    @State private var isHovering = false

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
                .fill(isHovering ? .regularMaterial : .thinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovering ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(isHovering ? 0.14 : 0.06), radius: isHovering ? 14 : 6, y: isHovering ? 7 : 3)
        .scaleEffect(isHovering ? 1.012 : 1)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2, perform: onPlay)
    }
}

private struct AlbumShelfCard: View {
    let bucket: AlbumBucket
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onQueue: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let leadTrack = bucket.leadTrack {
                TrackArtworkCoverView(
                    track: leadTrack,
                    seed: "\(bucket.artist)|\(bucket.title)",
                    title: bucket.title
                )
                .frame(width: 158, height: 158)
            }

            Text(bucket.title)
                .font(.headline)
                .lineLimit(1)

            Text(bucket.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("\(bucket.tracks.count) tracks")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button("Play", action: onPlay)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Queue", action: onQueue)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.35)
                        : (isHovering ? Color.accentColor.opacity(0.18) : Color.clear),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0), radius: 8, y: 4)
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct AlbumDetailList: View {
    let bucket: AlbumBucket
    let onPlayTrack: (Track) -> Void
    let onQueueTrack: (Track) -> Void
    let onLikeTrack: (Track) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.title)
                        .font(.title3.weight(.semibold))
                    Text(bucket.artist)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(bucket.tracks.count) tracks")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(bucket.tracks) { track in
                        HStack(spacing: 10) {
                            Text(track.title)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(track.duration > 0 ? String(format: "%d:%02d", track.duration / 60, track.duration % 60) : "--:--")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)

                            HStack(spacing: 6) {
                                Button {
                                    onPlayTrack(track)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    onQueueTrack(track)
                                } label: {
                                    Image(systemName: "text.badge.plus")
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    onLikeTrack(track)
                                } label: {
                                    Image(systemName: track.isLiked ? "heart.fill" : "heart")
                                }
                                .buttonStyle(.borderless)
                            }
                            .frame(width: 82, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.secondary.opacity(0.07))
                        )
                    }
                }
                .padding(.bottom, 10)
            }
            .frame(minHeight: 220)
        }
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
