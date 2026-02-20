import AppKit
import SwiftUI

struct TrackArtworkCoverView: View {
    let track: Track
    var seed: String
    var title: String
    var cornerRadius: CGFloat = 14
    var symbolScale: CGFloat = 0.34

    @State private var artwork: NSImage?

    var body: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ProceduralCoverView(
                    seed: seed,
                    title: title,
                    cornerRadius: cornerRadius,
                    symbolScale: symbolScale
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
        }
        .task(id: track.localPath) {
            artwork = await EmbeddedArtworkLoader.load(
                localPath: track.localPath,
                artist: track.artist,
                album: track.album
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: artworkDidUpdateNotification)) { notification in
            let albumKey = notification.userInfo?[artworkAlbumKeyUserInfoKey] as? String
            let folderKey = notification.userInfo?[artworkFolderKeyUserInfoKey] as? String

            let trackAlbumKey = EmbeddedArtworkLoader.albumCacheKey(
                artist: track.artist,
                album: track.album
            )
            let trackFolderKey = EmbeddedArtworkLoader.folderCacheKey(for: track.localPath)

            guard albumKey == trackAlbumKey || folderKey == trackFolderKey else { return }

            Task {
                artwork = await EmbeddedArtworkLoader.load(
                    localPath: track.localPath,
                    artist: track.artist,
                    album: track.album
                )
            }
        }
    }
}
