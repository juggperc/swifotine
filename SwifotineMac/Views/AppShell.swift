import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case search = "Search"
    case downloads = "Downloads"
    case library = "Library"
    case playlists = "Playlists"
    case liked = "Liked"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .downloads: return "arrow.down.circle"
        case .library: return "music.note.list"
        case .playlists: return "list.bullet.rectangle"
        case .liked: return "heart"
        }
    }
}

struct AppShell: View {
    @State private var selection: SidebarSection? = .search

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.iconName)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Swifotine")
        } detail: {
            if let selection = selection {
                MainContentArea(section: selection)
            } else {
                Text("Select a section")
            }
        }
    }
}

struct MainContentArea: View {
    var section: SidebarSection

    var body: some View {
        switch section {
        case .search:
            SearchView()
        case .downloads:
            DownloadsView()
        default:
            Text(section.rawValue)
                .font(.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
        }
    }
}

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        VStack {
            TextField("Search Soulseek...", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()

            Spacer()
            Text("Search Results for '\(query)'")
                .foregroundColor(.secondary)
            Spacer()
        }
        .navigationTitle("Search")
    }
}

struct DownloadsView: View {
    var body: some View {
        List {
            Text("No Active Downloads")
                .foregroundColor(.secondary)
        }
        .navigationTitle("Downloads")
    }
}
