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
    @Namespace private var tabAnimationNamespace

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

    private var selectedItem: SearchResultItem? {
        guard let activeTab else { return nil }
        return activeTab.results.first(where: { activeTab.selection.contains($0.id) })
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

    var body: some View {
        VStack(spacing: 0) {
            tabsBar

            HStack {
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

                if selectedItem != nil {
                    Button("Download Selected") {
                        if let selectedItem {
                            enqueueDownload(selectedItem)
                        }
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
                        enqueueDownload(selectedResult)
                    }
                }
            } primaryAction: { selection in
                if let firstID = selection.first,
                    let selectedResult = activeResults.first(where: { $0.id == firstID })
                {
                    enqueueDownload(selectedResult)
                }
            }
            .id(activeTabID)
            .frame(minHeight: 320)
            .animation(.easeInOut(duration: 0.2), value: activeResults.count)

            Divider()

            GroupBox("File Details") {
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
    }

    private func runSearch() {
        guard let tab = activeTab else { return }
        let trimmedQuery = tab.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

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

        updateTab(activeTabID) { tab in
            tab.title = makeTabTitle(query: entry.query)
            tab.query = entry.query
            tab.results = entry.cachedResults
            tab.selection.removeAll()
            tab.isSearching = false
            tab.lastError = nil
            tab.lastNotice = "Loaded \(entry.resultCount) cached results from \(relativeDateString(entry.searchedAt))."
        }
    }

    private func enqueueDownload(_ item: SearchResultItem) {
        Task {
            let queuedItems = await store.enqueueDownloadWithFallback(for: item, candidates: activeResults)
            for queuedItem in queuedItems {
                downloadsStore.noteQueuedDownload(for: queuedItem)
            }
        }
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
