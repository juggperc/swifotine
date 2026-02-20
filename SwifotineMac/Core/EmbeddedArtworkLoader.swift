import AVFoundation
import AppKit
import Foundation

enum EmbeddedArtworkLoader {
    private static let artworkCache = NSCache<NSString, NSImage>()
    private static let missingArtworkCache = NSCache<NSString, NSNumber>()

    static func load(localPath: String) async -> NSImage? {
        let key = localPath as NSString

        if let cached = artworkCache.object(forKey: key) {
            return cached
        }
        if missingArtworkCache.object(forKey: key) != nil {
            return nil
        }

        guard FileManager.default.fileExists(atPath: localPath) else {
            missingArtworkCache.setObject(1, forKey: key)
            return nil
        }

        let asset = AVURLAsset(url: URL(fileURLWithPath: localPath))
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        let artworkItems = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .commonIdentifierArtwork
        )

        for item in artworkItems {
            if let data = try? await item.load(.dataValue),
                let image = NSImage(data: data)
            {
                artworkCache.setObject(image, forKey: key)
                return image
            }
        }

        missingArtworkCache.setObject(1, forKey: key)
        return nil
    }
}
