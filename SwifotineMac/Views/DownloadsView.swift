import SwiftUI

struct DownloadsView: View {
    @StateObject private var store = DownloadsStore()

    var body: some View {
        VStack {
            if store.activeTransfers.isEmpty {
                Spacer()
                Text("No Active Downloads")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(store.activeTransfers) { tx in
                    VStack(alignment: .leading) {
                        Text(tx.localPath)
                            .font(.headline)

                        HStack {
                            Text(tx.status)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()

                            if tx.totalSize > 0 {
                                ProgressView(
                                    value: Double(tx.bytesTransferred), total: Double(tx.totalSize)
                                )
                                .frame(width: 150)
                            }

                            Text(
                                "\(ByteCountFormatter.string(fromByteCount: Int64(tx.speed), countStyle: .file))/s"
                            )
                            .font(.caption)
                            .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Downloads")
    }
}
