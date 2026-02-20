import Foundation
import SwiftData

public struct DownloadTransfer: Identifiable, Hashable {
    public let id: String
    public let virtualPath: String
    public let sourceUsername: String
    public var status: String
    public var bytesTransferred: Int
    public var totalSize: Int
    public var speed: Int  // bytes per second
    public var eta: Int  // seconds remaining
    public var localPath: String
}

extension DownloadTransfer: Codable {}

@MainActor
class DownloadsStore: ObservableObject {
    @Published var activeTransfers: [DownloadTransfer] = []

    private var modelContext: ModelContext?
    private var pendingCompletedPaths: [String] = []
    private let persistenceURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Swifotine", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("downloads-state.json")
    }()

    private struct PersistedDownloadsState: Codable {
        let savedAt: Date
        let transfers: [DownloadTransfer]
    }

    init() {
        restorePersistedState()
        Task {
            await bindEvents()
        }
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        flushPendingCompletedPaths()
    }

    private func bindEvents() async {
        let stream = await BackendClient.shared.eventStream()
        Task {
            for await event in stream {
                guard let payload = event.payload else { continue }

                switch event.event {
                case "download.updated":
                    if let id = payload["transfer_id"],
                        let status = payload["status"],
                        let xferred = Int(payload["bytes_transferred"] ?? "0"),
                        let total = Int(payload["total"] ?? "0"),
                        let speed = Int(payload["speed"] ?? "0"),
                        let eta = Int(payload["eta"] ?? "0")
                    {

                        let path = payload["local_path"] ?? ""
                        let sourceUsername = payload["source_username"] ?? "unknown"
                        let virtualPath = payload["virtual_path"] ?? ""

                        if let index = activeTransfers.firstIndex(where: { $0.id == id }) {
                            activeTransfers[index].status = status
                            activeTransfers[index].bytesTransferred = xferred
                            activeTransfers[index].totalSize = total
                            activeTransfers[index].speed = speed
                            activeTransfers[index].eta = eta
                            activeTransfers[index].localPath = path
                            persistState()
                        } else {
                            if let queuedIndex = activeTransfers.firstIndex(where: {
                                $0.id == queuedTransferID(
                                    username: sourceUsername, virtualPath: virtualPath)
                            }) {
                                activeTransfers.remove(at: queuedIndex)
                            }

                            let tx = DownloadTransfer(
                                id: id,
                                virtualPath: virtualPath,
                                sourceUsername: sourceUsername,
                                status: status,
                                bytesTransferred: xferred,
                                totalSize: total,
                                speed: speed,
                                eta: eta,
                                localPath: path
                            )
                            activeTransfers.insert(tx, at: 0)
                            persistState()
                        }
                    }

                case "download.finished":
                    if let localPath = payload["local_file_path"], !localPath.isEmpty {
                        handleCompletedDownload(localPath)
                    }

                case "download.failed":
                    if let id = payload["transfer_id"] {
                        if let index = activeTransfers.firstIndex(where: { $0.id == id }) {
                            activeTransfers[index].status =
                                "Failed: \(payload["categorized_reason"] ?? "Unknown")"
                            persistState()
                        } else if let sourceUsername = payload["source_username"],
                            let virtualPath = payload["virtual_path"]
                        {
                            let queuedID = queuedTransferID(
                                username: sourceUsername, virtualPath: virtualPath)
                            if let queuedIndex = activeTransfers.firstIndex(where: { $0.id == queuedID })
                            {
                                activeTransfers[queuedIndex].status =
                                    "Failed: \(payload["categorized_reason"] ?? "Unknown")"
                                persistState()
                            }
                        }
                    }

                default:
                    break
                }
            }
        }
    }

    func noteQueuedDownload(for item: SearchResultItem) {
        let queuedID = queuedTransferID(username: item.peerUsername, virtualPath: item.filePath)

        if activeTransfers.contains(where: {
            $0.id == queuedID || ($0.sourceUsername == item.peerUsername && $0.virtualPath == item.filePath)
        }) {
            return
        }

        let queuedTransfer = DownloadTransfer(
            id: queuedID,
            virtualPath: item.filePath,
            sourceUsername: item.peerUsername,
            status: "Queued",
            bytesTransferred: 0,
            totalSize: item.size,
            speed: 0,
            eta: 0,
            localPath: item.filePath
        )

        activeTransfers.insert(queuedTransfer, at: 0)
        persistState()
    }

    private func queuedTransferID(username: String, virtualPath: String) -> String {
        "queued:\(username):\(virtualPath)"
    }

    private func handleCompletedDownload(_ localPath: String) {
        guard let finalPath = AutoOrganizer.shared.organize(downloadedPath: localPath) else {
            return
        }

        guard let context = modelContext else {
            if !pendingCompletedPaths.contains(finalPath) {
                pendingCompletedPaths.append(finalPath)
            }
            return
        }

        insertTrackIfNeeded(finalPath: finalPath, context: context)
    }

    private func flushPendingCompletedPaths() {
        guard let context = modelContext else { return }
        guard !pendingCompletedPaths.isEmpty else { return }

        for finalPath in pendingCompletedPaths {
            insertTrackIfNeeded(finalPath: finalPath, context: context)
        }
        pendingCompletedPaths.removeAll()
    }

    private func insertTrackIfNeeded(finalPath: String, context: ModelContext) {
        let descriptor = FetchDescriptor<Track>()
        if let existingTracks = try? context.fetch(descriptor),
            existingTracks.contains(where: { $0.localPath == finalPath })
        {
            return
        }

        let url = URL(fileURLWithPath: finalPath)
        let name = url.lastPathComponent
        let ext = url.pathExtension
        let nameWithoutExt = name.replacingOccurrences(of: ".\(ext)", with: "")

        var artist = "Unknown Artist"
        var title = nameWithoutExt

        if let dashRange = nameWithoutExt.range(of: " - ") {
            artist = String(nameWithoutExt[..<dashRange.lowerBound]).trimmingCharacters(
                in: .whitespaces)
            title = String(nameWithoutExt[dashRange.upperBound...]).trimmingCharacters(
                in: .whitespaces)
        }

        let newTrack = Track(
            title: title,
            artist: artist,
            album: "Unknown Album",
            localPath: finalPath
        )
        context.insert(newTrack)
        try? context.save()
        print("Track saved to Library layer: \(title) by \(artist)")
    }

    private func persistState() {
        let snapshot = PersistedDownloadsState(savedAt: Date(), transfers: activeTransfers)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: persistenceURL, options: [.atomic])
        } catch {
            print("Failed to persist downloads state: \(error)")
        }
    }

    private func restorePersistedState() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let snapshot = try JSONDecoder().decode(PersistedDownloadsState.self, from: data)
            activeTransfers = snapshot.transfers
        } catch {
            print("Failed to restore downloads state: \(error)")
        }
    }
}
