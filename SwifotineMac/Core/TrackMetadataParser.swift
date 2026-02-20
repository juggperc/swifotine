import Foundation

struct ParsedTrackMetadata {
    let title: String
    let artist: String
    let album: String
}

enum TrackMetadataParser {
    private static let unknownArtist = "Unknown Artist"
    private static let unknownAlbum = "Unknown Album"

    private static let genericFolderNames: Set<String> = [
        "",
        "downloads",
        "incomplete",
        "library",
        "music",
        "swifotine",
        "unknown album",
        "unknown artist",
    ]

    static func parse(localPath: String) -> ParsedTrackMetadata {
        parse(url: URL(fileURLWithPath: localPath))
    }

    static func parse(url: URL) -> ParsedTrackMetadata {
        let parent = cleanedFolderName(url.deletingLastPathComponent().lastPathComponent)
        let grandparent = cleanedFolderName(
            url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)

        let filenameStem = stripTrackIndexPrefix(cleanDisplay(url.deletingPathExtension().lastPathComponent))

        var parsedArtist: String?
        var parsedTitle: String?

        if let pair = splitArtistAndTitle(from: filenameStem) {
            parsedArtist = pair.artist
            parsedTitle = pair.title
        }

        if parsedArtist == nil {
            parsedArtist = folderArtistCandidate(parent: parent, grandparent: grandparent)
        }

        if parsedTitle == nil || parsedTitle?.isEmpty == true {
            parsedTitle = filenameStem.isEmpty ? "Unknown Title" : filenameStem
        }

        let album = folderAlbumCandidate(parent: parent) ?? unknownAlbum
        let artist = parsedArtist?.isEmpty == false ? parsedArtist! : unknownArtist
        let title = parsedTitle?.isEmpty == false ? parsedTitle! : "Unknown Title"

        return ParsedTrackMetadata(
            title: cleanDisplay(title),
            artist: cleanDisplay(artist),
            album: cleanDisplay(album)
        )
    }

    static func filesystemSafeComponent(_ value: String, fallback: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let cleanedScalars = value.unicodeScalars.map { scalar -> Character in
            invalidCharacters.contains(scalar) ? "-" : Character(scalar)
        }
        let cleaned = cleanDisplay(String(cleanedScalars))
        return cleaned.isEmpty ? fallback : cleaned
    }

    private static func splitArtistAndTitle(from raw: String) -> (artist: String, title: String)? {
        let normalized = raw
            .replacingOccurrences(of: " – ", with: " - ")
            .replacingOccurrences(of: " — ", with: " - ")
            .replacingOccurrences(of: "_-_", with: " - ")
            .replacingOccurrences(of: " _ ", with: " - ")
            .replacingOccurrences(of: "|", with: " - ")

        guard let range = normalized.range(of: " - ") else { return nil }

        let left = cleanDisplay(String(normalized[..<range.lowerBound]))
        let right = cleanDisplay(String(normalized[range.upperBound...]))

        guard left.count >= 2, right.count >= 2 else { return nil }
        return (left, right)
    }

    private static func folderArtistCandidate(parent: String, grandparent: String) -> String? {
        if !genericFolderNames.contains(grandparent.lowercased()) {
            return grandparent
        }
        if !genericFolderNames.contains(parent.lowercased()) {
            return parent
        }
        return nil
    }

    private static func folderAlbumCandidate(parent: String) -> String? {
        if genericFolderNames.contains(parent.lowercased()) {
            return nil
        }
        return parent
    }

    private static func cleanedFolderName(_ value: String) -> String {
        cleanDisplay(value)
    }

    private static func stripTrackIndexPrefix(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        let pattern = #"^\s*(?:[A-Za-z]?\d{1,3})[\.\)\] _-]+(?:track\s*)?"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else {
            return value
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        if let match = regex.firstMatch(in: value, options: [], range: range),
            let matchRange = Range(match.range, in: value)
        {
            let stripped = value.replacingCharacters(in: matchRange, with: "")
            let cleaned = cleanDisplay(stripped)
            return cleaned.isEmpty ? value : cleaned
        }

        return value
    }

    private static func cleanDisplay(_ value: String) -> String {
        let replaced = value
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let collapsed = replaced.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed
    }
}
