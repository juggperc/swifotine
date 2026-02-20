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
    @Published var lastSearchError: String? = nil
    @Published var lastDownloadError: String? = nil
    @Published var searchHistory: [String] = []

    private var searchIdleTask: Task<Void, Never>?
    private let searchIdleTimeoutNanos: UInt64 = 2_000_000_000
    private let maxHistoryItems = 25
    private let historyDefaultsKey = "swifotine.search.history"

    init() {
        loadSearchHistory()
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
                        if !self.results.contains(where: {
                            $0.filePath == path && $0.size == size && $0.peerUsername == peer
                        })
                        {
                            self.results.append(item)
                        }

                        markSearchActivity()
                    }
                }
            }
        }
    }

    func startSearch(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        recordSearchHistory(trimmedQuery)

        self.activeQuery = trimmedQuery
        self.results.removeAll()
        self.isSearching = true
        self.lastSearchError = nil
        scheduleSearchIdleTimeout()

        do {
            let response = try await BackendClient.shared.sendRequest(
                method: "search.start", params: ["query": trimmedQuery])
            try validateRPCResponse(response, fallbackMessage: "Search request failed.")
        } catch {
            self.isSearching = false
            self.lastSearchError = error.localizedDescription
            print("Search failed: \(error)")
        }
    }

    func stopSearch() {
        searchIdleTask?.cancel()
        searchIdleTask = nil
        self.isSearching = false
        // Request stop via backend
    }

    func enqueueDownload(for item: SearchResultItem) async -> Bool {
        await enqueueDownloadInternal(for: item)
    }

    func enqueueDownloadWithFallback(for item: SearchResultItem, candidates: [SearchResultItem]) async
        -> [SearchResultItem]
    {
        lastDownloadError = nil

        // Creative failover: enqueue same file from additional peers so a stalled source
        // can be bypassed without manual retries.
        let fallbackCandidates = candidates.filter {
            $0.id != item.id
                && $0.filePath == item.filePath
                && $0.size == item.size
                && $0.peerUsername != item.peerUsername
        }
        .sorted { lhs, rhs in
            if lhs.bitrate != rhs.bitrate {
                return lhs.bitrate > rhs.bitrate
            }
            return lhs.peerUsername < rhs.peerUsername
        }

        var queuePlan: [SearchResultItem] = [item]
        queuePlan.append(contentsOf: fallbackCandidates.prefix(2))

        var enqueuedItems: [SearchResultItem] = []
        for candidate in queuePlan {
            let didEnqueue = await enqueueDownloadInternal(for: candidate)
            if didEnqueue {
                enqueuedItems.append(candidate)
            }
        }

        if enqueuedItems.isEmpty {
            lastDownloadError = lastDownloadError ?? "Failed to enqueue selected file."
        }

        return enqueuedItems
    }

    private func enqueueDownloadInternal(for item: SearchResultItem) async -> Bool {
        lastDownloadError = nil

        do {
            let response = try await BackendClient.shared.sendRequest(
                method: "download.enqueue",
                params: [
                    "username": item.peerUsername,
                    "virtualPath": item.filePath,
                ])
            try validateRPCResponse(response, fallbackMessage: "Failed to enqueue download.")
            print("Enqueued \(item.filename)")
            return true
        } catch {
            lastDownloadError = error.localizedDescription
            print("Enqueue failed: \(error)")
            return false
        }
    }

    func clearSearchHistory() {
        searchHistory.removeAll()
        persistSearchHistory()
    }

    private func markSearchActivity() {
        isSearching = true
        scheduleSearchIdleTimeout()
    }

    private func scheduleSearchIdleTimeout() {
        searchIdleTask?.cancel()
        searchIdleTask = Task { [weak self] in
            guard let self else { return }
            let timeout = self.searchIdleTimeoutNanos
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled else { return }
            self.isSearching = false
        }
    }

    private func validateRPCResponse(_ response: RPCResponse, fallbackMessage: String) throws {
        if response.ok == true {
            return
        }

        let message = response.error?.message ?? fallbackMessage
        throw NSError(
            domain: "SearchStore",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func loadSearchHistory() {
        let rawItems = UserDefaults.standard.stringArray(forKey: historyDefaultsKey) ?? []
        searchHistory = rawItems.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func recordSearchHistory(_ query: String) {
        var newHistory = searchHistory

        if let existingIndex = newHistory.firstIndex(of: query) {
            newHistory.remove(at: existingIndex)
        }

        newHistory.insert(query, at: 0)
        if newHistory.count > maxHistoryItems {
            newHistory = Array(newHistory.prefix(maxHistoryItems))
        }

        searchHistory = newHistory
        persistSearchHistory()
    }

    private func persistSearchHistory() {
        UserDefaults.standard.set(searchHistory, forKey: historyDefaultsKey)
    }
}
