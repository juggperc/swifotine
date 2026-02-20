import SwiftUI

struct AcknowledgementsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Acknowledgements")
                .font(.title2.weight(.semibold))

            Text("Swifotine is powered by open-source projects and platform frameworks.")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    acknowledgementCard(
                        title: "Nicotine+",
                        detail: "Core Soulseek networking and transfer engine.",
                        license: "GPL-3.0-or-later",
                        linkLabel: "Project",
                        linkURL: "https://github.com/nicotine-plus/nicotine-plus"
                    )

                    acknowledgementCard(
                        title: "Apple Frameworks",
                        detail: "SwiftUI, SwiftData, AppKit, and AVFoundation provide native macOS UI and media support.",
                        license: "Apple SDK Terms",
                        linkLabel: "Developer Docs",
                        linkURL: "https://developer.apple.com/documentation/"
                    )

                    acknowledgementCard(
                        title: "Python",
                        detail: "Helper process runtime for Nicotine+ integration.",
                        license: "PSF License",
                        linkLabel: "Python.org",
                        linkURL: "https://www.python.org/"
                    )

                    Text("For bundled licenses and details, see `licensing.md` in the project root.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func acknowledgementCard(
        title: String,
        detail: String,
        license: String,
        linkLabel: String,
        linkURL: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
            Text("License: \(license)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let url = URL(string: linkURL) {
                Link(linkLabel, destination: url)
                    .font(.footnote.weight(.medium))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
