import Foundation

struct AutoOrganizer {
    static let shared = AutoOrganizer()

    private let libraryRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/Swifotine/Library")

    func organize(downloadedPath: String) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: downloadedPath) else { return nil }

        let url = URL(fileURLWithPath: downloadedPath)
        let name = url.lastPathComponent
        let ext = url.pathExtension

        // Very basic heuristic for Phase E: Parse filename "Artist - Title.ext"
        var artist = "Unknown Artist"
        var title = name

        // Remove extension
        let nameWithoutExt = name.replacingOccurrences(of: ".\(ext)", with: "")

        if let dashRange = nameWithoutExt.range(of: " - ") {
            artist = String(nameWithoutExt[..<dashRange.lowerBound]).trimmingCharacters(
                in: .whitespaces)
            title = String(nameWithoutExt[dashRange.upperBound...]).trimmingCharacters(
                in: .whitespaces)
        }

        let album = "Unknown Album"

        // Create Library/Artist/Album structure
        let targetDir =
            libraryRoot
            .appendingPathComponent(artist)
            .appendingPathComponent(album)

        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let finalDest = targetDir.appendingPathComponent("\(title).\(ext)")

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
