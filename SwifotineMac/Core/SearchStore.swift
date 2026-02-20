import Foundation

public struct SearchResultItem: Identifiable, Hashable {
    public let id = UUID()
    public let peerUsername: String
    public let filePath: String
    public let size: Int
    public let bitrate: Int
    public let length: Int  // in seconds

    // Original metadata properties from Nicotine path parsing or tags if available later
    var filename: String {
        (filePath as NSString).lastPathComponent
    }
}

@MainActor
class SearchStore: ObservableObject {
    @Published var activeQuery: String = ""
    @Published var results: [SearchResultItem] = []
    @Published var isSearching: Bool = false

    init() {
        Task {
            await bindEvents()
        }
    }

    private func bindEvents() async {
        let stream = await BackendClient.shared.eventStream()
        Task {
            for await event in stream {
                if event.event == "search.result", let payload = event.payload {
                    if let peer = payload["peer_username"],
                        let path = payload["file_path"],
                        let sizeStr = payload["size"],
                        let size = Int(sizeStr)
                    {

                        let bitrate = Int(payload["bitrate"] ?? "0") ?? 0
                        let length = Int(payload["length"] ?? "0") ?? 0

                        let item = SearchResultItem(
                            peerUsername: peer,
                            filePath: path,
                            size: size,
                            bitrate: bitrate,
                            length: length
                        )

                        // Simple deduplication heuristic
                        if !self.results.contains(where: { $0.filePath == path && $0.size == size })
                        {
                            self.results.append(item)
                        }
                    }
                }
            }
        }
    }

    func startSearch(query: String) async {
        self.activeQuery = query
        self.results.removeAll()
        self.isSearching = true

        do {
            _ = try await BackendClient.shared.sendRequest(
                method: "search.start", params: ["query": query])
        } catch {
            print("Search failed: \(error)")
        }
    }

    func stopSearch() {
        self.isSearching = false
        // Request stop via backend
    }

    func enqueueDownload(for item: SearchResultItem) async {
        do {
            _ = try await BackendClient.shared.sendRequest(
                method: "download.enqueue",
                params: [
                    "username": item.peerUsername,
                    "virtualPath": item.filePath,
                ])
            print("Enqueued \(item.filename)")
        } catch {
            print("Enqueue failed: \(error)")
        }
    }
}
