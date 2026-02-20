import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \Track.title) var tracks: [Track]
    @EnvironmentObject var playbackEngine: PlaybackEngine

    var body: some View {
        Table(tracks) {
            TableColumn("Title", value: \.title)
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            Button("Play") {
                if let firstId = selection.first,
                    let track = tracks.first(where: { $0.id == firstId })
                {
                    playbackEngine.play(track: track)
                }
            }

            Button("Like / Unlike") {
                if let firstId = selection.first,
                    let track = tracks.first(where: { $0.id == firstId })
                {
                    track.isLiked.toggle()
                }
            }
        } primaryAction: { selection in
            if let firstId = selection.first, let track = tracks.first(where: { $0.id == firstId })
            {
                playbackEngine.play(track: track)
            }
        }
        .navigationTitle("Library")
    }
}

struct LikedView: View {
    @Query(
        filter: #Predicate<Track> { track in
            track.isLiked == true
        }, sort: \Track.title) var likedTracks: [Track]

    @EnvironmentObject var playbackEngine: PlaybackEngine

    var body: some View {
        Table(likedTracks) {
            TableColumn("Title", value: \.title)
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            Button("Play") {
                if let firstId = selection.first,
                    let track = likedTracks.first(where: { $0.id == firstId })
                {
                    playbackEngine.play(track: track)
                }
            }

            Button("Unlike") {
                if let firstId = selection.first,
                    let track = likedTracks.first(where: { $0.id == firstId })
                {
                    track.isLiked = false
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
