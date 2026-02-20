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

enum DownloadTransferState: String, CaseIterable, Identifiable {
    case active = "Active"
    case queued = "Queued"
    case finished = "Finished"
    case failed = "Failed"

    var id: String { rawValue }
}

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

    func transferState(for transfer: DownloadTransfer) -> DownloadTransferState {
        let normalizedStatus = transfer.status.lowercased()

        if normalizedStatus.contains("failed") {
            return .failed
        }

        if normalizedStatus.contains("finished")
            || (transfer.totalSize > 0
                && transfer.bytesTransferred >= transfer.totalSize
                && transfer.speed == 0
                && !normalizedStatus.contains("queued"))
        {
            return .finished
        }

        if normalizedStatus.contains("queued") || transfer.id.hasPrefix("queued:") {
            return .queued
        }

        if transfer.speed > 0
            || (transfer.totalSize > 0 && transfer.bytesTransferred > 0 && transfer.bytesTransferred < transfer.totalSize)
            || normalizedStatus.contains("downloading")
            || normalizedStatus.contains("transferring")
            || normalizedStatus.contains("requesting")
        {
            return .active
        }

        return .queued
    }

    func retryTransfer(_ transfer: DownloadTransfer) async -> Bool {
        do {
            let response = try await BackendClient.shared.sendRequest(
                method: "download.enqueue",
                params: [
                    "username": transfer.sourceUsername,
                    "virtualPath": transfer.virtualPath,
                ])
            try validateRPCResponse(response, fallbackMessage: "Failed to retry download.")

            if let index = activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                let wasFailed = transferState(for: activeTransfers[index]) == .failed
                activeTransfers[index].status = "Queued"
                activeTransfers[index].speed = 0
                activeTransfers[index].eta = 0
                if wasFailed {
                    activeTransfers[index].bytesTransferred = 0
                }
            } else {
                let queuedID = queuedTransferID(
                    username: transfer.sourceUsername,
                    virtualPath: transfer.virtualPath
                )
                let queuedTransfer = DownloadTransfer(
                    id: queuedID,
                    virtualPath: transfer.virtualPath,
                    sourceUsername: transfer.sourceUsername,
                    status: "Queued",
                    bytesTransferred: 0,
                    totalSize: transfer.totalSize,
                    speed: 0,
                    eta: 0,
                    localPath: transfer.localPath
                )
                activeTransfers.insert(queuedTransfer, at: 0)
            }

            persistState()
            return true
        } catch {
            print("Retry enqueue failed: \(error)")
            return false
        }
    }

    func retryFailedTransfers() async -> Int {
        let failedTransfers = activeTransfers.filter { transferState(for: $0) == .failed }
        var successfulRetries = 0

        for transfer in failedTransfers {
            let didRetry = await retryTransfer(transfer)
            if didRetry {
                successfulRetries += 1
            }
        }

        return successfulRetries
    }

    func dismissTransfer(id: String) {
        activeTransfers.removeAll(where: { $0.id == id })
        persistState()
    }

    func clearFinishedTransfers() {
        clearTransfers(where: { transferState(for: $0) == .finished })
    }

    func clearFailedTransfers() {
        clearTransfers(where: { transferState(for: $0) == .failed })
    }

    func clearInactiveTransfers() {
        clearTransfers(where: {
            let state = transferState(for: $0)
            return state == .finished || state == .failed
        })
    }

    private func queuedTransferID(username: String, virtualPath: String) -> String {
        "queued:\(username):\(virtualPath)"
    }

    private func clearTransfers(where shouldRemove: (DownloadTransfer) -> Bool) {
        let beforeCount = activeTransfers.count
        activeTransfers.removeAll(where: shouldRemove)
        if activeTransfers.count != beforeCount {
            persistState()
        }
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

        let parsed = TrackMetadataParser.parse(localPath: finalPath)

        let newTrack = Track(
            title: parsed.title,
            artist: parsed.artist,
            album: parsed.album,
            localPath: finalPath
        )
        context.insert(newTrack)
        try? context.save()
        print("Track saved to Library layer: \(parsed.title) by \(parsed.artist)")
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

    private func validateRPCResponse(_ response: RPCResponse, fallbackMessage: String) throws {
        if response.ok == true {
            return
        }

        let message = response.error?.message ?? fallbackMessage
        throw NSError(
            domain: "DownloadsStore",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
