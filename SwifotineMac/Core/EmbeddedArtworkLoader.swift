import AVFoundation
import AppKit
import Foundation

enum EmbeddedArtworkLoader {
    private static let artworkCache = NSCache<NSString, NSImage>()
    private static let albumArtworkCache = NSCache<NSString, NSImage>()
    private static let folderArtworkCache = NSCache<NSString, NSImage>()
    private static let missingArtworkCache = NSCache<NSString, NSNumber>()

    private static let sidecarExtensions = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tiff"]
    private static let folderArtworkCandidates = [
        "cover", "folder", "front", "album", "albumart", "artwork", "scan", "thumb",
    ]

    static func load(localPath: String, artist: String? = nil, album: String? = nil) async -> NSImage? {
        let fileKey = localPath as NSString
        let albumKey = albumCacheKey(artist: artist, album: album)
        let folderKey = folderCacheKey(for: localPath)

        if let cached = artworkCache.object(forKey: fileKey) {
            return cached
        }
        if let albumKey, let cached = albumArtworkCache.object(forKey: albumKey as NSString) {
            artworkCache.setObject(cached, forKey: fileKey)
            return cached
        }
        if let folderKey, let cached = folderArtworkCache.object(forKey: folderKey as NSString) {
            artworkCache.setObject(cached, forKey: fileKey)
            return cached
        }
        if missingArtworkCache.object(forKey: fileKey) != nil {
            return nil
        }

        let fileURL = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: localPath) else {
            missingArtworkCache.setObject(1, forKey: fileKey)
            return nil
        }

        let asset = AVURLAsset(url: fileURL)
        if let embedded = await extractEmbeddedArtwork(from: asset) {
            cache(image: embedded, fileKey: fileKey, albumKey: albumKey, folderKey: folderKey)
            return embedded
        }

        if let sidecar = loadSidecarArtwork(from: fileURL) {
            cache(image: sidecar, fileKey: fileKey, albumKey: albumKey, folderKey: folderKey)
            return sidecar
        }

        if let folderArt = loadFolderArtwork(from: fileURL) {
            cache(image: folderArt, fileKey: fileKey, albumKey: albumKey, folderKey: folderKey)
            return folderArt
        }

        missingArtworkCache.setObject(1, forKey: fileKey)
        return nil
    }

    static func albumCacheKey(artist: String?, album: String?) -> String? {
        let normalizedArtist = cleanCacheComponent(artist)
        let normalizedAlbum = cleanCacheComponent(album)
        guard !normalizedAlbum.isEmpty else { return nil }
        return "\(normalizedArtist)|\(normalizedAlbum)"
    }

    static func folderCacheKey(for localPath: String) -> String? {
        URL(fileURLWithPath: localPath).deletingLastPathComponent().path
    }

    private static func cleanCacheComponent(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func cache(image: NSImage, fileKey: NSString, albumKey: String?, folderKey: String?) {
        artworkCache.setObject(image, forKey: fileKey)
        missingArtworkCache.removeObject(forKey: fileKey)

        if let albumKey {
            albumArtworkCache.setObject(image, forKey: albumKey as NSString)
        }
        if let folderKey {
            folderArtworkCache.setObject(image, forKey: folderKey as NSString)
        }

        postArtworkDidUpdate(albumKey: albumKey, folderKey: folderKey)
    }

    private static func postArtworkDidUpdate(albumKey: String?, folderKey: String?) {
        var userInfo: [String: String] = [:]
        if let albumKey {
            userInfo[artworkAlbumKeyUserInfoKey] = albumKey
        }
        if let folderKey {
            userInfo[artworkFolderKeyUserInfoKey] = folderKey
        }

        NotificationCenter.default.post(
            name: artworkDidUpdateNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    private static func extractEmbeddedArtwork(from asset: AVURLAsset) async -> NSImage? {
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        if let image = await firstImage(from: commonMetadata) {
            return image
        }

        let metadataFormats = (try? await asset.load(.availableMetadataFormats)) ?? []
        for format in metadataFormats {
            let metadata = (try? await asset.loadMetadata(for: format)) ?? []
            if let image = await firstImage(from: metadata) {
                return image
            }
        }

        return nil
    }

    private static func firstImage(from metadata: [AVMetadataItem]) async -> NSImage? {
        for item in metadata {
            if let data = try? await item.load(.dataValue),
                let image = NSImage(data: data)
            {
                return image
            }
        }
        return nil
    }

    private static func loadSidecarArtwork(from fileURL: URL) -> NSImage? {
        let folder = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent

        for ext in sidecarExtensions {
            let sidecarURL = folder.appendingPathComponent(stem).appendingPathExtension(ext)
            if let image = loadImage(from: sidecarURL) {
                return image
            }
        }

        return nil
    }

    private static func loadFolderArtwork(from fileURL: URL) -> NSImage? {
        let folder = fileURL.deletingLastPathComponent()

        for candidate in folderArtworkCandidates {
            for ext in sidecarExtensions {
                let imageURL = folder.appendingPathComponent(candidate).appendingPathExtension(ext)
                if let image = loadImage(from: imageURL) {
                    return image
                }
            }
        }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let rankedArtworkFiles = entries
            .filter { sidecarExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                rankArtworkFilename(lhs.lastPathComponent) < rankArtworkFilename(rhs.lastPathComponent)
            }

        for entry in rankedArtworkFiles {
            if let image = loadImage(from: entry) {
                return image
            }
        }

        return nil
    }

    private static func loadImage(from url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func rankArtworkFilename(_ filename: String) -> Int {
        let lowered = filename.lowercased()
        if lowered.contains("cover") { return 0 }
        if lowered.contains("folder") { return 1 }
        if lowered.contains("front") { return 2 }
        if lowered.contains("albumart") { return 3 }
        if lowered.contains("artwork") { return 4 }
        return 10
    }
}

let artworkDidUpdateNotification = Notification.Name("EmbeddedArtworkLoader.artworkDidUpdate")
let artworkAlbumKeyUserInfoKey = "albumKey"
let artworkFolderKeyUserInfoKey = "folderKey"
