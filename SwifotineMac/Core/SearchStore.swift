import Foundation

public struct SearchResultItem: Identifiable, Hashable, Codable {
    public let id: String
    public let peerUsername: String
    public let filePath: String
    public let size: Int
    public let bitrate: Int
    public let length: Int
    public let freeUploadSlots: Int
    public let queueSize: Int
    public let uploadSpeed: Int
    public let searchToken: String
    public let relevanceScore: Double

    public init(
        peerUsername: String,
        filePath: String,
        size: Int,
        bitrate: Int,
        length: Int,
        freeUploadSlots: Int,
        queueSize: Int,
        uploadSpeed: Int,
        searchToken: String,
        relevanceScore: Double
    ) {
        self.id = SearchResultItem.makeID(
            peerUsername: peerUsername, filePath: filePath, size: size, searchToken: searchToken)
        self.peerUsername = peerUsername
        self.filePath = filePath
        self.size = size
        self.bitrate = bitrate
        self.length = length
        self.freeUploadSlots = freeUploadSlots
        self.queueSize = queueSize
        self.uploadSpeed = uploadSpeed
        self.searchToken = searchToken
        self.relevanceScore = relevanceScore
    }

    var filename: String {
        (filePath as NSString).lastPathComponent
    }

    private static func makeID(
        peerUsername: String,
        filePath: String,
        size: Int,
        searchToken: String
    ) -> String {
        "\(searchToken)|\(peerUsername)|\(filePath)|\(size)"
    }
}

public struct SearchHistoryEntry: Identifiable, Hashable, Codable {
    public let id: UUID
    public let query: String
    public let searchedAt: Date
    public let resultCount: Int
    public let cachedResults: [SearchResultItem]
}

@MainActor
class SearchStore: ObservableObject {
    @Published var activeQuery: String = ""
    @Published var results: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    @Published var lastSearchError: String? = nil
    @Published var lastSearchNotice: String? = nil
    @Published var lastDownloadError: String? = nil
    @Published var searchHistory: [SearchHistoryEntry] = []

    private var searchIdleTask: Task<Void, Never>?
    private var searchDurationTask: Task<Void, Never>?
    private var activeSearchToken: String?
    private var seenResultIDs: Set<String> = []

    private let searchIdleTimeoutNanos: UInt64 = 1_500_000_000
    private let searchDurationLimitNanos: UInt64 = 18_000_000_000
    private let maxResultsPerSearch = 1_800
    private let maxCachedResultsPerHistoryEntry = 400
    private let maxHistoryItems = 25
    private let historyDefaultsKey = "swifotine.search.history"
    private let historyFileURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Swifotine", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("search-history.json")
    }()

    private struct PersistedSearchHistory: Codable {
        let savedAt: Date
        let entries: [SearchHistoryEntry]
    }

    private let preferredAudioExtensions: Set<String> = [
        "aac",
        "aif",
        "aiff",
        "alac",
        "flac",
        "m4a",
        "mp3",
        "ogg",
        "opus",
        "wav",
        "wma",
    ]

    init() {
        loadSearchHistory()
        Task {
            await bindEvents()
        }
    }

    private func bindEvents() async {
        let stream = await BackendClient.shared.eventStream()
        Task { @MainActor in
            for await event in stream {
                switch event.event {
                case "search.result":
                    handleSearchResult(event.payload ?? [:])
                default:
                    break
                }
            }
        }
    }

    func startSearch(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        let tokenToStop = activeSearchToken
        await stopSearchInternal(sendStopRequest: true, notice: nil, expectedToken: tokenToStop)

        activeQuery = trimmedQuery
        results.removeAll()
        seenResultIDs.removeAll()
        isSearching = true
        lastSearchError = nil
        lastSearchNotice = nil

        do {
            let response = try await BackendClient.shared.sendRequest(
                method: "search.start", params: ["query": trimmedQuery])
            try validateRPCResponse(response, fallbackMessage: "Search request failed.")

            let token = response.result?["token"]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            guard !token.isEmpty else {
                throw NSError(
                    domain: "SearchStore",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Search token was not returned by backend."]
                )
            }

            activeSearchToken = token
            scheduleSearchIdleTimeout(for: token)
            scheduleSearchDurationTimeout(for: token)
        } catch {
            isSearching = false
            activeSearchToken = nil
            lastSearchError = error.localizedDescription
            print("Search failed: \(error)")
        }
    }

    func stopSearch(notice: String? = nil) {
        let tokenToStop = activeSearchToken
        Task {
            await stopSearchInternal(sendStopRequest: true, notice: notice, expectedToken: tokenToStop)
        }
    }

    func enqueueDownload(for item: SearchResultItem) async -> Bool {
        await enqueueDownloadInternal(for: item)
    }

    func enqueueDownloadWithFallback(for item: SearchResultItem, candidates: [SearchResultItem]) async
        -> [SearchResultItem]
    {
        lastDownloadError = nil

        let fallbackCandidates = candidates.filter {
            $0.id != item.id
                && $0.filePath == item.filePath
                && $0.size == item.size
                && $0.peerUsername != item.peerUsername
        }
        .sorted { lhs, rhs in
            if lhs.freeUploadSlots != rhs.freeUploadSlots {
                return lhs.freeUploadSlots > rhs.freeUploadSlots
            }
            if lhs.queueSize != rhs.queueSize {
                return lhs.queueSize < rhs.queueSize
            }
            if lhs.uploadSpeed != rhs.uploadSpeed {
                return lhs.uploadSpeed > rhs.uploadSpeed
            }
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

    func clearSearchHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: historyDefaultsKey)
        persistSearchHistory()
    }

    private func handleSearchResult(_ payload: [String: String]) {
        guard let token = payload["token"], token == activeSearchToken else { return }
        guard let peer = payload["peer_username"], !peer.isEmpty else { return }
        guard let path = payload["file_path"], !path.isEmpty else { return }
        guard let sizeStr = payload["size"], let size = Int(sizeStr), size > 0 else { return }

        let bitrate = intPayload("bitrate", payload: payload)
        let length = intPayload("length", payload: payload)
        let freeUploadSlots = intPayload("free_upload_slots", payload: payload)
        let queueSize = intPayload("queue_size", payload: payload)
        let uploadSpeed = intPayload("upload_speed", payload: payload)

        let score = calculateRelevanceScore(
            query: activeQuery,
            path: path,
            size: size,
            bitrate: bitrate,
            freeUploadSlots: freeUploadSlots,
            queueSize: queueSize,
            uploadSpeed: uploadSpeed
        )

        let item = SearchResultItem(
            peerUsername: peer,
            filePath: path,
            size: size,
            bitrate: bitrate,
            length: length,
            freeUploadSlots: freeUploadSlots,
            queueSize: queueSize,
            uploadSpeed: uploadSpeed,
            searchToken: token,
            relevanceScore: score
        )

        guard seenResultIDs.insert(item.id).inserted else { return }

        results.append(item)
        results.sort(by: searchSortComparator)
        if results.count > maxResultsPerSearch {
            results = Array(results.prefix(maxResultsPerSearch))
        }

        markSearchActivity(for: token)

        if results.count >= maxResultsPerSearch {
            Task {
                await self.stopSearchInternal(
                    sendStopRequest: true,
                    notice: "Search capped at \(maxResultsPerSearch) ranked results.",
                    expectedToken: token
                )
            }
        }
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

    private func markSearchActivity(for token: String) {
        guard token == activeSearchToken else { return }
        isSearching = true
        scheduleSearchIdleTimeout(for: token)
    }

    private func scheduleSearchIdleTimeout(for token: String) {
        searchIdleTask?.cancel()
        searchIdleTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.searchIdleTimeoutNanos)
            guard !Task.isCancelled else { return }
            await self.handleSearchIdleTimeout(expectedToken: token)
        }
    }

    private func scheduleSearchDurationTimeout(for token: String) {
        searchDurationTask?.cancel()
        searchDurationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.searchDurationLimitNanos)
            guard !Task.isCancelled else { return }
            await self.handleSearchDurationTimeout(expectedToken: token)
        }
    }

    private func handleSearchIdleTimeout(expectedToken: String) async {
        guard activeSearchToken == expectedToken else { return }
        await stopSearchInternal(
            sendStopRequest: true,
            notice: "Search finished after no new results.",
            expectedToken: expectedToken
        )
    }

    private func handleSearchDurationTimeout(expectedToken: String) async {
        guard activeSearchToken == expectedToken else { return }
        await stopSearchInternal(
            sendStopRequest: true,
            notice: "Search reached the 18 second limit.",
            expectedToken: expectedToken
        )
    }

    private func stopSearchInternal(sendStopRequest: Bool, notice: String?, expectedToken: String?) async {
        if let expectedToken {
            guard activeSearchToken == expectedToken else { return }
        }

        let token = activeSearchToken
        activeSearchToken = nil

        searchIdleTask?.cancel()
        searchIdleTask = nil
        searchDurationTask?.cancel()
        searchDurationTask = nil
        isSearching = false

        if let notice, !notice.isEmpty {
            lastSearchNotice = notice
        }

        if let token {
            if !activeQuery.isEmpty {
                upsertHistoryEntry(query: activeQuery, results: results)
            }
            if sendStopRequest {
                do {
                    _ = try await BackendClient.shared.sendRequest(
                        method: "search.stop",
                        params: ["token": token]
                    )
                } catch {
                    print("Failed to stop search token \(token): \(error)")
                }
            }
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
        if FileManager.default.fileExists(atPath: historyFileURL.path) {
            do {
                let data = try Data(contentsOf: historyFileURL)
                let persisted = try JSONDecoder().decode(PersistedSearchHistory.self, from: data)
                searchHistory = persisted.entries.filter {
                    !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return
            } catch {
                print("Failed to load search history file: \(error)")
            }
        }

        let legacyQueries = UserDefaults.standard.stringArray(forKey: historyDefaultsKey) ?? []
        if !legacyQueries.isEmpty {
            var migratedEntries: [SearchHistoryEntry] = []
            for query in legacyQueries {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                migratedEntries.append(
                    SearchHistoryEntry(
                        id: UUID(),
                        query: trimmed,
                        searchedAt: Date(),
                        resultCount: 0,
                        cachedResults: []
                    )
                )
            }
            searchHistory = migratedEntries
            UserDefaults.standard.removeObject(forKey: historyDefaultsKey)
            persistSearchHistory()
        }
    }

    private func upsertHistoryEntry(query: String, results: [SearchResultItem]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updatedHistory = searchHistory
        if let existingIndex = updatedHistory.firstIndex(where: {
            $0.query.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            updatedHistory.remove(at: existingIndex)
        }

        let cachedResults = Array(results.prefix(maxCachedResultsPerHistoryEntry))
        let entry = SearchHistoryEntry(
            id: UUID(),
            query: trimmed,
            searchedAt: Date(),
            resultCount: results.count,
            cachedResults: cachedResults
        )

        updatedHistory.insert(entry, at: 0)
        if updatedHistory.count > maxHistoryItems {
            updatedHistory = Array(updatedHistory.prefix(maxHistoryItems))
        }

        searchHistory = updatedHistory
        persistSearchHistory()
    }

    private func persistSearchHistory() {
        do {
            let persisted = PersistedSearchHistory(savedAt: Date(), entries: searchHistory)
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: historyFileURL, options: [.atomic])
        } catch {
            print("Failed to persist search history: \(error)")
        }
    }

    private func searchSortComparator(_ lhs: SearchResultItem, _ rhs: SearchResultItem) -> Bool {
        if lhs.relevanceScore != rhs.relevanceScore {
            return lhs.relevanceScore > rhs.relevanceScore
        }
        if lhs.freeUploadSlots != rhs.freeUploadSlots {
            return lhs.freeUploadSlots > rhs.freeUploadSlots
        }
        if lhs.queueSize != rhs.queueSize {
            return lhs.queueSize < rhs.queueSize
        }
        if lhs.uploadSpeed != rhs.uploadSpeed {
            return lhs.uploadSpeed > rhs.uploadSpeed
        }
        if lhs.bitrate != rhs.bitrate {
            return lhs.bitrate > rhs.bitrate
        }
        return lhs.peerUsername < rhs.peerUsername
    }

    private func calculateRelevanceScore(
        query: String,
        path: String,
        size: Int,
        bitrate: Int,
        freeUploadSlots: Int,
        queueSize: Int,
        uploadSpeed: Int
    ) -> Double {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path.lowercased()
        let filename = (path as NSString).lastPathComponent.lowercased()
        let queryTerms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .map(String.init)

        var score = 0.0

        if !normalizedQuery.isEmpty {
            if filename == normalizedQuery {
                score += 300
            }
            if filename.contains(normalizedQuery) {
                score += 180
            }
            if filename.hasPrefix(normalizedQuery) {
                score += 120
            }
            if normalizedPath.contains(normalizedQuery) {
                score += 80
            }

            for term in queryTerms {
                if filename.contains(term) {
                    score += 50
                } else if normalizedPath.contains(term) {
                    score += 24
                } else {
                    score -= 6
                }
            }
        }

        let ext = (path as NSString).pathExtension.lowercased()
        if preferredAudioExtensions.contains(ext) {
            score += 20
        }

        if bitrate > 0 {
            score += min(Double(bitrate), 320.0) / 4.0
        }
        if freeUploadSlots > 0 {
            score += Double(min(freeUploadSlots, 5)) * 22.0
        }
        if queueSize > 0 {
            score -= Double(min(queueSize, 50)) * 2.0
        }
        if uploadSpeed > 0 {
            score += min(Double(uploadSpeed) / 64.0, 80.0)
        }
        if size > 0 {
            score += 8.0
        }

        return score
    }

    private func intPayload(_ key: String, payload: [String: String]) -> Int {
        Int(payload[key] ?? "0") ?? 0
    }
}
