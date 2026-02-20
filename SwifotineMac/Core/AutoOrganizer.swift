import Foundation

struct AutoOrganizer {
    static let shared = AutoOrganizer()

    private let libraryRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/Swifotine/Library")

    func organize(downloadedPath: String) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: downloadedPath) else { return nil }

        let url = URL(fileURLWithPath: downloadedPath)
        let ext = url.pathExtension
        let parsed = TrackMetadataParser.parse(localPath: downloadedPath)

        let artist = TrackMetadataParser.filesystemSafeComponent(
            parsed.artist, fallback: "Unknown Artist")
        let album = TrackMetadataParser.filesystemSafeComponent(
            parsed.album, fallback: "Unknown Album")
        let title = TrackMetadataParser.filesystemSafeComponent(
            parsed.title, fallback: url.deletingPathExtension().lastPathComponent)

        // Create Library/Artist/Album structure
        let targetDir =
            libraryRoot
            .appendingPathComponent(artist)
            .appendingPathComponent(album)

        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let normalizedFilename = ext.isEmpty ? title : "\(title).\(ext)"
            let finalDest = targetDir.appendingPathComponent(normalizedFilename)

            // if target exists, replace it or skip? for safety let's assume skip duplicate
            if !fileManager.fileExists(atPath: finalDest.path) {
                try fileManager.moveItem(at: url, to: finalDest)
                return finalDest.path
            } else {
                return finalDest.path  // already exists, maybe return existing path.
            }
        } catch {
            print("AutoOrganizer failed to normalize path: \(error)")
            return nil
        }
    }
}
