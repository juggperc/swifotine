import Foundation
import SwiftData

@Model
final class Track {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var localPath: String
    var duration: Int
    var isLiked: Bool
    var addedAt: Date

    init(title: String, artist: String, album: String, localPath: String, duration: Int = 0) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.album = album
        self.localPath = localPath
        self.duration = duration
        self.isLiked = false
        self.addedAt = Date()
    }
}

@Model
final class Playlist {
    var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade) var entries: [PlaylistEntry]
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.entries = []
        self.createdAt = Date()
    }
}

@Model
final class PlaylistEntry {
    var id: UUID
    var order: Int
    var track: Track?

    init(order: Int, track: Track) {
        self.id = UUID()
        self.order = order
        self.track = track
    }
}
