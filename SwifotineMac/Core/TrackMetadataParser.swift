import AVFoundation
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
        "single",
        "singles",
        "album",
        "unknown album",
        "unknown artist",
        "various",
        "various artists",
        "va",
        "new folder",
        "untitled",
    ]

    private struct TaggedMetadata {
        var title: String?
        var artist: String?
        var album: String?
    }

    static func parse(localPath: String) -> ParsedTrackMetadata {
        parse(url: URL(fileURLWithPath: localPath))
    }

    static func parse(url: URL) -> ParsedTrackMetadata {
        let tagged = extractTaggedMetadata(from: url)

        let parent = cleanedFolderName(url.deletingLastPathComponent().lastPathComponent)
        let grandparent = cleanedFolderName(
            url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)

        let filenameStem = stripTrackIndexPrefix(cleanDisplay(url.deletingPathExtension().lastPathComponent))
        let splitPair = splitArtistAndTitle(from: filenameStem)

        let artist = firstUsable(
            tagged.artist,
            splitPair?.artist,
            folderArtistCandidate(parent: parent, grandparent: grandparent),
            fallback: unknownArtist,
            rejectGeneric: true
        )

        let album = firstUsable(
            tagged.album,
            folderAlbumCandidate(parent: parent),
            fallback: unknownAlbum,
            rejectGeneric: true
        )

        let title = firstUsable(
            tagged.title,
            splitPair?.title,
            filenameStem,
            fallback: "Unknown Title",
            rejectGeneric: false
        )

        return ParsedTrackMetadata(
            title: sanitizeTitleCandidate(cleanDisplay(title)),
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

    private static func extractTaggedMetadata(from url: URL) -> TaggedMetadata {
        let asset = AVURLAsset(url: url)

        var metadataItems = asset.commonMetadata
        for format in asset.availableMetadataFormats {
            metadataItems.append(contentsOf: asset.metadata(forFormat: format))
        }

        let title = firstMetadataString(
            in: metadataItems,
            identifiers: [.commonIdentifierTitle],
            keyHints: ["title", "tit2", "nam"]
        )
        let artist = firstMetadataString(
            in: metadataItems,
            identifiers: [.commonIdentifierArtist, .commonIdentifierCreator],
            keyHints: ["artist", "albumartist", "tpe1", "tpe2", "aart"]
        )
        let album = firstMetadataString(
            in: metadataItems,
            identifiers: [.commonIdentifierAlbumName],
            keyHints: ["album", "talb"]
        )

        return TaggedMetadata(
            title: title,
            artist: artist,
            album: album
        )
    }

    private static func firstMetadataString(
        in items: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier],
        keyHints: [String]
    ) -> String? {
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
            for item in matches {
                if let text = usableMetadataString(item.stringValue) {
                    return text
                }
            }
        }

        for item in items {
            if let commonKey = item.commonKey?.rawValue.lowercased(),
                keyHints.contains(where: { commonKey.contains($0) }),
                let text = usableMetadataString(item.stringValue)
            {
                return text
            }

            if let key = item.key as? String {
                let normalizedKey = key.lowercased()
                if keyHints.contains(where: { normalizedKey.contains($0) }),
                    let text = usableMetadataString(item.stringValue)
                {
                    return text
                }
            }
        }

        return nil
    }

    private static func usableMetadataString(_ value: String?) -> String? {
        let cleaned = cleanDisplay(value ?? "")
        guard cleaned.count >= 2 else { return nil }
        guard cleaned.lowercased() != "unknown" else { return nil }
        return cleaned
    }

    private static func firstUsable(
        _ candidates: String?...,
        fallback: String,
        rejectGeneric: Bool
    ) -> String {
        for candidate in candidates {
            let cleaned = cleanDisplay(candidate ?? "")
            guard !cleaned.isEmpty else { continue }
            if rejectGeneric && genericFolderNames.contains(cleaned.lowercased()) {
                continue
            }
            return cleaned
        }
        return fallback
    }

    private static func splitArtistAndTitle(from raw: String) -> (artist: String, title: String)? {
        let normalized = raw
            .replacingOccurrences(of: " - ", with: " | ")
            .replacingOccurrences(of: " – ", with: " | ")
            .replacingOccurrences(of: " — ", with: " | ")
            .replacingOccurrences(of: "_-_", with: " | ")
            .replacingOccurrences(of: " _ ", with: " | ")

        guard let range = normalized.range(of: " | ") else { return nil }

        let left = cleanDisplay(String(normalized[..<range.lowerBound]))
        let right = cleanDisplay(String(normalized[range.upperBound...]))

        guard left.count >= 2, right.count >= 2 else { return nil }
        guard !genericFolderNames.contains(left.lowercased()) else { return nil }
        return (left, sanitizeTitleCandidate(right))
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

    private static func sanitizeTitleCandidate(_ value: String) -> String {
        var output = value
        let trailingNoisePattern = #"\s*[\[(](?:official\s+audio|official\s+video|lyrics?|hd|hq|320\s?kbps|explicit|clean|prod\.?\s+by[^\])]{0,30})[\])]\s*$"#
        if let regex = try? NSRegularExpression(pattern: trailingNoisePattern, options: [.caseInsensitive]) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
        }
        return cleanDisplay(output)
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
