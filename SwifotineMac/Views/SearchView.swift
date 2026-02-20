import Foundation
import SwiftUI

private struct SearchTabState: Identifiable, Hashable {
    let id: UUID
    var title: String
    var query: String
    var results: [SearchResultItem]
    var selection: Set<SearchResultItem.ID>
    var isSearching: Bool
    var lastError: String?
    var lastNotice: String?
}

private enum SearchPresentationMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case beta = "Beta"

    var id: String { rawValue }
}

private enum BetaGroupingMode: String, CaseIterable, Identifiable {
    case album = "Album"
    case song = "Song"

    var id: String { rawValue }
}

private struct BetaSourceOption: Identifiable, Hashable {
    let item: SearchResultItem
    let metadata: SearchDetectedMetadata

    var id: String { item.id }
}

private struct BetaFolderCluster: Identifiable, Hashable {
    let id: String
    let username: String
    let folderTitle: String
    let options: [BetaSourceOption]
    let totalSize: Int

    var trackCount: Int {
        options.count
    }
}

private struct BetaSearchGroup: Identifiable, Hashable {
    let id: String
    let mode: BetaGroupingMode
    let title: String
    let subtitle: String
    let coverSeed: String
    let options: [BetaSourceOption]
    let clusters: [BetaFolderCluster]

    var uniqueUsers: Int {
        Set(options.map { $0.item.peerUsername.lowercased() }).count
    }

    var bestOption: BetaSourceOption? {
        options.first
    }
}

private struct SearchDetectedMetadata: Hashable {
    let trackTitle: String
    let albumTitle: String
    let artistName: String
    let folderPath: String
    let parentFolder: String
    let songKey: String
    let albumKey: String

    init(item: SearchResultItem) {
        let normalizedPath = item.filePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalizedPath
            .split(separator: "/")
            .map(String.init)

        let filename = components.last ?? item.filename
        let stem = (filename as NSString).deletingPathExtension
        let parentRaw = components.count >= 2 ? components[components.count - 2] : ""
        let grandparentRaw =
            components.count >= 3
            ? components[components.count - 3]
            : ""

        let detectedTrack = Self.cleanTrackName(stem)
        let detectedAlbum = Self.cleanFolderName(parentRaw)
        let pathArtist = Self.cleanFolderName(grandparentRaw)

        let resolvedArtist = Self.resolveArtist(pathArtist: pathArtist, peerUsername: item.peerUsername)
        let resolvedTrack = detectedTrack.isEmpty ? "Unknown Track" : detectedTrack
        let resolvedAlbum: String
        if detectedAlbum.isEmpty {
            resolvedAlbum = resolvedTrack == "Unknown Track" ? "Unknown Album" : resolvedTrack
        } else {
            resolvedAlbum = detectedAlbum
        }

        trackTitle = resolvedTrack
        albumTitle = resolvedAlbum
        artistName = resolvedArtist
        folderPath = components.dropLast().joined(separator: "/")
        parentFolder = detectedAlbum.isEmpty ? "Unknown Album" : detectedAlbum
        songKey = Self.normalizeKey("\(resolvedArtist)|\(resolvedTrack)")
        albumKey = Self.normalizeKey("\(resolvedArtist)|\(resolvedAlbum)")
    }

    private static func resolveArtist(pathArtist: String, peerUsername: String) -> String {
        if pathArtist.isEmpty || pathArtist.lowercased() == peerUsername.lowercased() {
            return "Unknown Artist"
        }
        return pathArtist
    }

    private static func cleanTrackName(_ value: String) -> String {
        var result = sanitize(value)
        result = replacing(pattern: #"^\s*((disc|cd)\s*\d+|track\s*\d+|\d{1,3})[\s\-._]+"#, in: result)
        result = replacing(pattern: #"^\s*\d{4}[\s\-._]+"#, in: result)
        result = replacing(pattern: #"\s+"#, in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanFolderName(_ value: String) -> String {
        var result = sanitize(value)
        result = replacing(pattern: #"^\s*\d{4}[\s\-._]+"#, in: result)
        result = replacing(pattern: #"\s+"#, in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitize(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        result = replacing(pattern: #"\[[^\]]*\]"#, in: result)
        result = replacing(pattern: #"\([^\)]*\)"#, in: result)
        result = replacing(pattern: #"\b(FLAC|MP3|V0|V2|WEB|CD|DELUXE|REMASTERED|LOSSLESS|HQ|REMIX)\b"#, in: result)
        result = replacing(pattern: #"\b\d{2,3}\s*KBPS\b"#, in: result)
        result = replacing(pattern: #"\s+"#, in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(pattern: String, in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: " ")
    }

    private static func normalizeKey(_ value: String) -> String {
        let lowered = value.lowercased()
        return replacing(pattern: #"\s+"#, in: lowered)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: SearchStore
    @EnvironmentObject private var downloadsStore: DownloadsStore

    private static let initialTabID = UUID()

    @State private var tabs: [SearchTabState] = [
        SearchTabState(
            id: SearchView.initialTabID,
            title: "Search 1",
            query: "",
            results: [],
            selection: [],
            isSearching: false,
            lastError: nil,
            lastNotice: nil
        )
    ]
    @State private var activeTabID: UUID = SearchView.initialTabID
    @State private var runningSearchTabID: UUID? = nil
    @State private var betaFocusedItemID: SearchResultItem.ID?
    @State private var expandedBetaGroupIDs: Set<String> = []
    @Namespace private var tabAnimationNamespace

    @AppStorage("swifotine.search.presentation.mode") private var presentationModeRaw =
        SearchPresentationMode.standard.rawValue
    @AppStorage("swifotine.search.beta.grouping.mode") private var betaGroupingModeRaw =
        BetaGroupingMode.album.rawValue

    private var presentationMode: SearchPresentationMode {
        SearchPresentationMode(rawValue: presentationModeRaw) ?? .standard
    }

    private var betaGroupingMode: BetaGroupingMode {
        BetaGroupingMode(rawValue: betaGroupingModeRaw) ?? .album
    }

    private var presentationModeBinding: Binding<SearchPresentationMode> {
        Binding(
            get: { SearchPresentationMode(rawValue: presentationModeRaw) ?? .standard },
            set: { presentationModeRaw = $0.rawValue }
        )
    }

    private var betaGroupingModeBinding: Binding<BetaGroupingMode> {
        Binding(
            get: { BetaGroupingMode(rawValue: betaGroupingModeRaw) ?? .album },
            set: { betaGroupingModeRaw = $0.rawValue }
        )
    }

    private var activeTabIndex: Int? {
        tabs.firstIndex(where: { $0.id == activeTabID })
    }

    private var activeTab: SearchTabState? {
        guard let index = activeTabIndex else { return nil }
        return tabs[index]
    }

    private var activeResults: [SearchResultItem] {
        activeTab?.results ?? []
    }

    private var tableSelectedItem: SearchResultItem? {
        guard let activeTab else { return nil }
        return activeTab.results.first(where: { activeTab.selection.contains($0.id) })
    }

    private var betaFocusedItem: SearchResultItem? {
        guard let betaFocusedItemID else { return nil }
        return activeResults.first(where: { $0.id == betaFocusedItemID })
    }

    private var selectedItem: SearchResultItem? {
        presentationMode == .standard ? tableSelectedItem : betaFocusedItem
    }

    private var activeQueryBinding: Binding<String> {
        Binding(
            get: { activeTab?.query ?? "" },
            set: { newValue in
                updateTab(activeTabID) { tab in
                    tab.query = newValue
                }
            }
        )
    }

    private var activeSelectionBinding: Binding<Set<SearchResultItem.ID>> {
        Binding(
            get: { activeTab?.selection ?? [] },
            set: { newSelection in
                updateTab(activeTabID) { tab in
                    tab.selection = newSelection
                }
            }
        )
    }

    private var betaGroups: [BetaSearchGroup] {
        buildBetaGroups(from: activeResults, grouping: betaGroupingMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabsBar

            HStack(spacing: 10) {
                TextField("Search Soulseek...", text: activeQueryBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        runSearch()
                    }

                Button("Search") {
                    runSearch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled((activeTab?.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if activeTab?.isSearching == true {
                    Button("Stop") {
                        store.stopSearch(notice: "Search stopped.")
                    }
                    .buttonStyle(.bordered)
                }

                Picker("Mode", selection: presentationModeBinding) {
                    ForEach(SearchPresentationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 175)

                if presentationMode == .beta {
                    Label("Experimental Beta", systemImage: "flask.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    Picker("Group", selection: betaGroupingModeBinding) {
                        ForEach(BetaGroupingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                if presentationMode == .standard, tableSelectedItem != nil {
                    Button("Download Selected") {
                        if let tableSelectedItem {
                            enqueueDownloadWithFallback(tableSelectedItem)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else if presentationMode == .beta, let betaFocusedItem {
                    Button("Download Focused") {
                        enqueueExactDownload(betaFocusedItem)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Menu {
                    if store.searchHistory.isEmpty {
                        Text("No search history")
                    } else {
                        ForEach(store.searchHistory) { entry in
                            Button(historyMenuLabel(entry)) {
                                applyHistoryEntry(entry)
                            }
                        }
                        Divider()
                        Button("Clear History", role: .destructive) {
                            store.clearSearchHistory()
                        }
                    }
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                if activeTab?.isSearching == true {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Text("\(activeResults.count) results")
                    .foregroundStyle(.secondary)
            }
            .padding()

            if let error = activeTab?.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let notice = activeTab?.lastNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let downloadError = store.lastDownloadError {
                Text(downloadError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Group {
                if presentationMode == .standard {
                    standardResultsView
                } else {
                    betaResultsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            GroupBox(presentationMode == .standard ? "File Details" : "Selected Download Details") {
                SearchFileDetailsPanel(selectedItem: selectedItem)
            }
            .padding()
        }
        .navigationTitle("Search")
        .onChange(of: store.results) { _, newResults in
            guard let targetTabID = runningSearchTabID else { return }
            updateTab(targetTabID) { tab in
                tab.results = newResults
                tab.selection = tab.selection.intersection(Set(newResults.map(\.id)))
            }
            synchronizeBetaState()
        }
        .onChange(of: store.lastSearchError) { _, newError in
            guard let targetTabID = runningSearchTabID else { return }
            updateTab(targetTabID) { tab in
                tab.lastError = newError
            }
        }
        .onChange(of: store.lastSearchNotice) { _, newNotice in
            guard let targetTabID = runningSearchTabID else { return }
            updateTab(targetTabID) { tab in
                tab.lastNotice = newNotice
            }
        }
        .onChange(of: store.isSearching) { _, isSearching in
            guard let targetTabID = runningSearchTabID else { return }
            updateTab(targetTabID) { tab in
                tab.isSearching = isSearching
            }
            if !isSearching {
                runningSearchTabID = nil
            }
        }
        .onChange(of: activeTabID) { _, _ in
            expandedBetaGroupIDs.removeAll()
            betaFocusedItemID = nil
        }
        .onChange(of: betaGroupingModeRaw) { _, _ in
            expandedBetaGroupIDs.removeAll()
            synchronizeBetaState()
        }
    }

    private var standardResultsView: some View {
        Table(activeResults, selection: activeSelectionBinding) {
            TableColumn("Filename", value: \.filename)
            TableColumn("User", value: \.peerUsername)
            TableColumn("Length") { item in
                Text(formatDuration(item.length))
                    .monospacedDigit()
            }
            TableColumn("Size") { item in
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
            }
            TableColumn("Bitrate") { item in
                Text(item.bitrate > 0 ? "\(item.bitrate) kbps" : "Unknown")
            }
            TableColumn("Path") { item in
                Text(item.filePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.filePath)
            }
        }
        .contextMenu(forSelectionType: SearchResultItem.ID.self) { selection in
            Button("Download") {
                if let firstID = selection.first,
                    let selectedResult = activeResults.first(where: { $0.id == firstID })
                {
                    enqueueDownloadWithFallback(selectedResult)
                }
            }
        } primaryAction: { selection in
            if let firstID = selection.first,
                let selectedResult = activeResults.first(where: { $0.id == firstID })
            {
                enqueueDownloadWithFallback(selectedResult)
            }
        }
        .id(activeTabID)
        .frame(minHeight: 320)
        .animation(.easeInOut(duration: 0.2), value: activeResults.count)
    }

    private var betaResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Click any cover to expand download options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(betaGroups) { group in
                        BetaSearchGroupCard(
                            group: group,
                            isExpanded: expandedBetaGroupIDs.contains(group.id),
                            onToggleExpanded: {
                                toggleGroupExpansion(group)
                            },
                            onDownloadBest: {
                                if let bestOption = group.bestOption {
                                    betaFocusedItemID = bestOption.item.id
                                    enqueueExactDownload(bestOption.item)
                                }
                            },
                            onDownloadOption: { option in
                                betaFocusedItemID = option.item.id
                                enqueueExactDownload(option.item)
                            },
                            onDownloadCluster: { cluster in
                                betaFocusedItemID = cluster.options.first?.item.id
                                enqueueCluster(cluster)
                            },
                            onFocusOption: { option in
                                betaFocusedItemID = option.item.id
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: betaGroups.count)
    }

    private var tabsBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        HStack(spacing: 6) {
                            Button {
                                activeTabID = tab.id
                            } label: {
                                HStack(spacing: 6) {
                                    Text(tab.title)
                                        .lineLimit(1)
                                        .fontWeight(tab.id == activeTabID ? .semibold : .regular)
                                    if tab.isSearching {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    if tab.id == activeTabID {
                                        Capsule()
                                            .fill(Color.accentColor.opacity(0.2))
                                            .matchedGeometryEffect(id: "active-search-tab", in: tabAnimationNamespace)
                                    } else {
                                        Capsule()
                                            .fill(Color.secondary.opacity(0.12))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.2), value: activeTabID)

                            if tabs.count > 1 {
                                Button {
                                    closeTab(tab.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            Button {
                addTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(.trailing)
        }
    }

    private func addTab() {
        let tabNumber = tabs.count + 1
        let newTab = SearchTabState(
            id: UUID(),
            title: "Search \(tabNumber)",
            query: "",
            results: [],
            selection: [],
            isSearching: false,
            lastError: nil,
            lastNotice: nil
        )
        tabs.append(newTab)
        activeTabID = newTab.id
    }

    private func closeTab(_ tabID: UUID) {
        guard tabs.count > 1 else { return }

        if runningSearchTabID == tabID {
            store.stopSearch(notice: nil)
            runningSearchTabID = nil
        }

        let fallbackID = tabs.first(where: { $0.id != tabID })?.id
        tabs.removeAll(where: { $0.id == tabID })

        if activeTabID == tabID, let fallbackID {
            activeTabID = fallbackID
        }

        synchronizeBetaState()
    }

    private func runSearch() {
        guard let tab = activeTab else { return }
        let trimmedQuery = tab.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        expandedBetaGroupIDs.removeAll()
        betaFocusedItemID = nil

        updateTab(tab.id) { updatedTab in
            updatedTab.title = makeTabTitle(query: trimmedQuery)
            updatedTab.query = trimmedQuery
            updatedTab.results.removeAll()
            updatedTab.selection.removeAll()
            updatedTab.isSearching = true
            updatedTab.lastError = nil
            updatedTab.lastNotice = nil
        }

        runningSearchTabID = tab.id

        Task {
            await store.startSearch(query: trimmedQuery)
        }
    }

    private func applyHistoryEntry(_ entry: SearchHistoryEntry) {
        if runningSearchTabID == activeTabID {
            store.stopSearch(notice: nil)
            runningSearchTabID = nil
        }

        expandedBetaGroupIDs.removeAll()
        betaFocusedItemID = nil

        updateTab(activeTabID) { tab in
            tab.title = makeTabTitle(query: entry.query)
            tab.query = entry.query
            tab.results = entry.cachedResults
            tab.selection.removeAll()
            tab.isSearching = false
            tab.lastError = nil
            tab.lastNotice =
                "Loaded \(entry.resultCount) cached results from \(relativeDateString(entry.searchedAt))."
        }
        synchronizeBetaState()
    }

    private func enqueueDownloadWithFallback(_ item: SearchResultItem) {
        Task {
            let queuedItems = await store.enqueueDownloadWithFallback(for: item, candidates: activeResults)
            for queuedItem in queuedItems {
                downloadsStore.noteQueuedDownload(for: queuedItem)
            }
        }
    }

    private func enqueueExactDownload(_ item: SearchResultItem) {
        Task {
            let didQueue = await store.enqueueDownload(for: item)
            if didQueue {
                downloadsStore.noteQueuedDownload(for: item)
            }
        }
    }

    private func enqueueCluster(_ cluster: BetaFolderCluster) {
        Task {
            let uniqueOptions = Dictionary(grouping: cluster.options, by: \.id)
                .compactMap { $0.value.first }

            for option in uniqueOptions {
                let didQueue = await store.enqueueDownload(for: option.item)
                if didQueue {
                    downloadsStore.noteQueuedDownload(for: option.item)
                }
            }
        }
    }

    private func toggleGroupExpansion(_ group: BetaSearchGroup) {
        if expandedBetaGroupIDs.contains(group.id) {
            expandedBetaGroupIDs.remove(group.id)
        } else {
            expandedBetaGroupIDs.insert(group.id)
            if betaFocusedItemID == nil {
                betaFocusedItemID = group.bestOption?.item.id
            }
        }
    }

    private func synchronizeBetaState() {
        let validIDs = Set(betaGroups.map(\.id))
        expandedBetaGroupIDs = expandedBetaGroupIDs.intersection(validIDs)

        if let betaFocusedItemID, !activeResults.contains(where: { $0.id == betaFocusedItemID }) {
            self.betaFocusedItemID = nil
        }
    }

    private func buildBetaGroups(from results: [SearchResultItem], grouping: BetaGroupingMode) -> [BetaSearchGroup] {
        guard !results.isEmpty else { return [] }

        let options = results.map { item in
            BetaSourceOption(item: item, metadata: SearchDetectedMetadata(item: item))
        }

        var grouped: [String: [BetaSourceOption]] = [:]
        for option in options {
            let key = grouping == .album ? option.metadata.albumKey : option.metadata.songKey
            grouped[key, default: []].append(option)
        }

        return grouped.compactMap { key, groupedOptions in
            let sortedOptions = groupedOptions.sorted(by: betaOptionComparator(lhs:rhs:))
            guard let lead = sortedOptions.first else { return nil }

            let titleValues: [String] = sortedOptions.map {
                grouping == .album ? $0.metadata.albumTitle : $0.metadata.trackTitle
            }
            let title = mostFrequent(from: titleValues, fallback: grouping == .album ? lead.metadata.albumTitle : lead.metadata.trackTitle)
            let artist = mostFrequent(from: sortedOptions.map(\.metadata.artistName), fallback: lead.metadata.artistName)
            let albumReference = mostFrequent(
                from: sortedOptions.map(\.metadata.albumTitle),
                fallback: lead.metadata.albumTitle
            )
            let subtitle: String
            if grouping == .album {
                subtitle = "\(artist) · \(sortedOptions.count) files"
            } else {
                subtitle = "\(artist) · \(albumReference)"
            }

            let clusters = buildClusters(from: sortedOptions)
            return BetaSearchGroup(
                id: key,
                mode: grouping,
                title: title,
                subtitle: subtitle,
                coverSeed: "\(artist)|\(title)|\(albumReference)",
                options: sortedOptions,
                clusters: clusters
            )
        }
        .sorted { lhs, rhs in
            let lhsScore = lhs.bestOption?.item.relevanceScore ?? 0
            let rhsScore = rhs.bestOption?.item.relevanceScore ?? 0
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            if lhs.options.count != rhs.options.count {
                return lhs.options.count > rhs.options.count
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func buildClusters(from options: [BetaSourceOption]) -> [BetaFolderCluster] {
        var buckets: [String: [BetaSourceOption]] = [:]

        for option in options {
            let folderKey = option.metadata.folderPath.lowercased()
            let key = "\(option.item.peerUsername.lowercased())|\(folderKey)"
            buckets[key, default: []].append(option)
        }

        return buckets.compactMap { key, groupedOptions in
            guard let first = groupedOptions.first else { return nil }
            let sortedOptions = groupedOptions.sorted(by: betaOptionComparator(lhs:rhs:))
            let folderTitle = mostFrequent(
                from: sortedOptions.map(\.metadata.parentFolder),
                fallback: first.metadata.parentFolder
            )
            let totalSize = sortedOptions.reduce(0) { $0 + $1.item.size }

            return BetaFolderCluster(
                id: key,
                username: first.item.peerUsername,
                folderTitle: folderTitle,
                options: sortedOptions,
                totalSize: totalSize
            )
        }
        .sorted { lhs, rhs in
            if lhs.trackCount != rhs.trackCount {
                return lhs.trackCount > rhs.trackCount
            }
            if lhs.totalSize != rhs.totalSize {
                return lhs.totalSize > rhs.totalSize
            }
            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }
    }

    private func betaOptionComparator(lhs: BetaSourceOption, rhs: BetaSourceOption) -> Bool {
        if lhs.item.relevanceScore != rhs.item.relevanceScore {
            return lhs.item.relevanceScore > rhs.item.relevanceScore
        }
        if lhs.item.freeUploadSlots != rhs.item.freeUploadSlots {
            return lhs.item.freeUploadSlots > rhs.item.freeUploadSlots
        }
        if lhs.item.queueSize != rhs.item.queueSize {
            return lhs.item.queueSize < rhs.item.queueSize
        }
        if lhs.item.uploadSpeed != rhs.item.uploadSpeed {
            return lhs.item.uploadSpeed > rhs.item.uploadSpeed
        }
        if lhs.item.bitrate != rhs.item.bitrate {
            return lhs.item.bitrate > rhs.item.bitrate
        }
        return lhs.item.peerUsername.localizedCaseInsensitiveCompare(rhs.item.peerUsername)
            == .orderedAscending
    }

    private func mostFrequent(from values: [String], fallback: String) -> String {
        var counts: [String: (display: String, count: Int)] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if var existing = counts[key] {
                existing.count += 1
                counts[key] = existing
            } else {
                counts[key] = (display: trimmed, count: 1)
            }
        }

        let top = counts.values.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.display.localizedCaseInsensitiveCompare(rhs.display) == .orderedAscending
        }
        return top.first?.display ?? fallback
    }

    private func updateTab(_ tabID: UUID, apply update: (inout SearchTabState) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = tabs[index]
        update(&tab)
        tabs[index] = tab
    }

    private func makeTabTitle(query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Search"
        }
        let maxTitleLength = 22
        if trimmed.count <= maxTitleLength {
            return trimmed
        }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: maxTitleLength)
        return "\(trimmed[..<cutoff])…"
    }

    private func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Unknown" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func historyMenuLabel(_ entry: SearchHistoryEntry) -> String {
        "\(entry.query) (\(entry.resultCount)) - \(relativeDateString(entry.searchedAt))"
    }

    private func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct BetaSearchGroupCard: View {
    let group: BetaSearchGroup
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onDownloadBest: () -> Void
    let onDownloadOption: (BetaSourceOption) -> Void
    let onDownloadCluster: (BetaFolderCluster) -> Void
    let onFocusOption: (BetaSourceOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onToggleExpanded()
                if let best = group.bestOption {
                    onFocusOption(best)
                }
            } label: {
                ProceduralCoverView(seed: group.coverSeed, title: group.title, cornerRadius: 12, symbolScale: 0.30)
                    .frame(height: 170)
            }
            .buttonStyle(.plain)

            Text(group.title)
                .font(.headline)
                .lineLimit(1)

            Text(group.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                BetaInfoChip(label: "Files", value: "\(group.options.count)")
                BetaInfoChip(label: "Users", value: "\(group.uniqueUsers)")
                if group.mode == .album {
                    BetaInfoChip(label: "Folders", value: "\(group.clusters.count)")
                }
                Spacer()
                Button(isExpanded ? "Hide" : "Options") {
                    onToggleExpanded()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isExpanded {
                Divider()

                HStack(spacing: 8) {
                    Button("Download Best Match") {
                        onDownloadBest()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if group.mode == .album, let topCluster = group.clusters.first {
                        Button("Download Album Folder") {
                            onDownloadCluster(topCluster)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if group.mode == .album {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Album Folder Sources")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(group.clusters.prefix(4))) { cluster in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(cluster.username)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(cluster.folderTitle) · \(cluster.trackCount) tracks")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(cluster.totalSize), countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Button("Download") {
                                    onDownloadCluster(cluster)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.mode == .album ? "Track Sources" : "Song Sources")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(group.options.prefix(8))) { option in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.metadata.trackTitle)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(option.item.peerUsername)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(option.item.bitrate > 0 ? "\(option.item.bitrate)k" : "--")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(option.item.size), countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 62, alignment: .trailing)
                            Button("Download") {
                                onDownloadOption(option)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onFocusOption(option)
                        }
                    }
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct BetaInfoChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }
}

private struct SearchFileDetailsPanel: View {
    let selectedItem: SearchResultItem?

    var body: some View {
        ZStack {
            if let selectedItem {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                            Image(systemName: "music.note")
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedItem.filename)
                                .font(.headline)
                                .lineLimit(1)
                            Text("From \(selectedItem.peerUsername)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        detailChip(
                            label: "Size",
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(selectedItem.size), countStyle: .file)
                        )
                        detailChip(label: "Length", value: formatDuration(selectedItem.length))
                        detailChip(
                            label: "Bitrate",
                            value: selectedItem.bitrate > 0 ? "\(selectedItem.bitrate) kbps" : "Unknown"
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Path")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedItem.filePath)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("Select a result to inspect file details.")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: selectedItem?.id)
    }

    private func detailChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Unknown" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
