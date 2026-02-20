import SwiftUI

struct SearchView: View {
    @StateObject private var store = SearchStore()
    @State private var query = ""

    var body: some View {
        VStack {
            HStack {
                TextField("Search Soulseek...", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await store.startSearch(query: query)
                        }
                    }

                if store.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()

            Table(store.results) {
                TableColumn("Filename", value: \.filename)
                TableColumn("User", value: \.peerUsername)
                TableColumn("Size") { item in
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(item.size), countStyle: .file))
                }
                TableColumn("Bitrate") { item in
                    Text("\(item.bitrate) kbps")
                }
            }
            .contextMenu(forSelectionType: SearchResultItem.ID.self) { selection in
                Button("Download") {
                    if let firstId = selection.first,
                        let item = store.results.first(where: { $0.id == firstId })
                    {
                        Task {
                            await store.enqueueDownload(for: item)
                        }
                    }
                }
            } primaryAction: { selection in
                if let firstId = selection.first,
                    let item = store.results.first(where: { $0.id == firstId })
                {
                    Task {
                        await store.enqueueDownload(for: item)
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}
