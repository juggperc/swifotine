import Foundation
import SwiftData

public struct DownloadTransfer: Identifiable, Hashable {
    public let id: String
    public let virtualPath: String
    public var status: String
    public var bytesTransferred: Int
    public var totalSize: Int
    public var speed: Int  // bytes per second
    public var eta: Int  // seconds remaining
    public var localPath: String
}

@MainActor
class DownloadsStore: ObservableObject {
    @Published var activeTransfers: [DownloadTransfer] = []

    private var modelContext: ModelContext?

    init() {
        Task {
            await bindEvents()
        }
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
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

                        if let index = activeTransfers.firstIndex(where: { $0.id == id }) {
                            activeTransfers[index].status = status
                            activeTransfers[index].bytesTransferred = xferred
                            activeTransfers[index].totalSize = total
                            activeTransfers[index].speed = speed
                            activeTransfers[index].eta = eta
                            activeTransfers[index].localPath = path
                        } else {
                            let tx = DownloadTransfer(
                                id: id, virtualPath: "", status: status, bytesTransferred: xferred,
                                totalSize: total, speed: speed, eta: eta, localPath: path)
                            activeTransfers.append(tx)
                        }
                    }

                case "download.finished":
                    if let localPath = payload["local_file_path"], !localPath.isEmpty {
                        // Mark UI as finished or remove from active queue later

                        // Let AutoOrganizer run
                        if let finalPath = AutoOrganizer.shared.organize(downloadedPath: localPath)
                        {

                            // Let's create a SwiftData Track
                            if let context = self.modelContext {
                                let url = URL(fileURLWithPath: finalPath)
                                let name = url.lastPathComponent
                                let ext = url.pathExtension

                                let nameWithoutExt = name.replacingOccurrences(
                                    of: ".\(ext)", with: "")
                                var artist = "Unknown Artist"
                                var title = nameWithoutExt

                                if let dashRange = nameWithoutExt.range(of: " - ") {
                                    artist = String(nameWithoutExt[..<dashRange.lowerBound])
                                        .trimmingCharacters(in: .whitespaces)
                                    title = String(nameWithoutExt[dashRange.upperBound...])
                                        .trimmingCharacters(in: .whitespaces)
                                }

                                let newTrack = Track(
                                    title: title, artist: artist, album: "Unknown Album",
                                    localPath: finalPath)
                                context.insert(newTrack)

                                try? context.save()
                                print("Track saved to Library layer: \(title) by \(artist)")
                            }
                        }
                    }

                case "download.failed":
                    if let id = payload["transfer_id"] {
                        if let index = activeTransfers.firstIndex(where: { $0.id == id }) {
                            activeTransfers[index].status =
                                "Failed: \(payload["categorized_reason"] ?? "Unknown")"
                        }
                    }

                default:
                    break
                }
            }
        }
    }
}
