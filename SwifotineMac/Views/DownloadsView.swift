import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var store: DownloadsStore

    var body: some View {
        VStack {
            if store.activeTransfers.isEmpty {
                Spacer()
                Text("No Active Downloads")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(store.activeTransfers) { tx in
                    DownloadTransferRow(tx: tx)
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(.easeInOut(duration: 0.2), value: store.activeTransfers)
            }
        }
        .navigationTitle("Downloads")
    }
}

private struct DownloadTransferRow: View {
    let tx: DownloadTransfer
    @State private var isHovering = false

    private var isTransferActive: Bool {
        let status = tx.status.lowercased()
        return tx.speed > 0 && !status.contains("finished") && !status.contains("failed")
    }

    private var progressPercentText: String {
        guard tx.totalSize > 0 else { return "--" }
        let ratio = min(max(Double(tx.bytesTransferred) / Double(tx.totalSize), 0), 1)
        return "\(Int((ratio * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tx.localPath.isEmpty ? tx.virtualPath : tx.localPath)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                TransferStatusIndicator(isActive: isTransferActive)

                Text("\(tx.sourceUsername) · \(tx.status)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if tx.totalSize > 0 {
                    ProgressView(
                        value: Double(tx.bytesTransferred), total: Double(tx.totalSize)
                    )
                    .frame(width: 140)

                    Text(progressPercentText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                Text(
                    "\(ByteCountFormatter.string(fromByteCount: Int64(tx.speed), countStyle: .file))/s"
                )
                .font(.caption)
                .monospacedDigit()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.secondary.opacity(isHovering ? 0.13 : 0.07))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isHovering ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 1)
        }
        .scaleEffect(isHovering ? 1.006 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct TransferStatusIndicator: View {
    let isActive: Bool

    var body: some View {
        if isActive {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.4) / 1.4

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .scaleEffect(0.75 + (phase * 0.35))
                    .opacity(0.5 + (phase * 0.45))
            }
            .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
        }
    }
}
