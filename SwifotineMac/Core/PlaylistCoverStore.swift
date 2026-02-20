import Foundation

struct PlaylistCoverProfile: Codable, Hashable {
    var influence: String
    var variant: UInt64
}

@MainActor
final class PlaylistCoverStore: ObservableObject {
    @Published private var profiles: [String: PlaylistCoverProfile] = [:]

    private let persistenceURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Swifotine", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("playlist-covers.json")
    }()

    private struct PersistedProfileState: Codable {
        let savedAt: Date
        let profiles: [String: PlaylistCoverProfile]
    }

    init() {
        restore()
    }

    func seed(for playlistID: UUID, name: String, fallbackInfluence: String = "") -> String {
        let key = key(for: playlistID)
        let profile = profiles[key] ?? PlaylistCoverProfile(
            influence: fallbackInfluence.trimmingCharacters(in: .whitespacesAndNewlines),
            variant: 0
        )

        return "\(playlistID.uuidString)|\(name)|\(profile.influence)|\(profile.variant)"
    }

    func influence(for playlistID: UUID, fallbackInfluence: String = "") -> String {
        profiles[key(for: playlistID)]?.influence ?? fallbackInfluence
    }

    func ensureProfile(for playlistID: UUID, fallbackInfluence: String = "") {
        let key = key(for: playlistID)
        guard profiles[key] == nil else { return }

        profiles[key] = PlaylistCoverProfile(
            influence: fallbackInfluence.trimmingCharacters(in: .whitespacesAndNewlines),
            variant: 0
        )
        persist()
    }

    func setInfluence(_ influence: String, for playlistID: UUID) {
        let key = key(for: playlistID)
        var profile = profiles[key] ?? PlaylistCoverProfile(influence: "", variant: 0)
        profile.influence = influence.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[key] = profile
        persist()
    }

    func regenerate(for playlistID: UUID) {
        let key = key(for: playlistID)
        var profile = profiles[key] ?? PlaylistCoverProfile(influence: "", variant: 0)
        profile.variant &+= 1
        profiles[key] = profile
        persist()
    }

    func pruneOrphaned(keeping playlistIDs: Set<UUID>) {
        let keepKeys = Set(playlistIDs.map(\.uuidString))
        let filtered = profiles.filter { keepKeys.contains($0.key) }
        guard filtered.count != profiles.count else { return }
        profiles = filtered
        persist()
    }

    private func key(for playlistID: UUID) -> String {
        playlistID.uuidString
    }

    private func persist() {
        let snapshot = PersistedProfileState(savedAt: Date(), profiles: profiles)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: persistenceURL, options: [.atomic])
        } catch {
            print("Failed to persist playlist cover profiles: \(error)")
        }
    }

    private func restore() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let snapshot = try JSONDecoder().decode(PersistedProfileState.self, from: data)
            profiles = snapshot.profiles
        } catch {
            print("Failed to restore playlist cover profiles: \(error)")
        }
    }
}
