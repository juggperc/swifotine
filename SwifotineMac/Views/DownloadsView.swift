import AppKit
import SwiftUI

private enum DownloadsFilterMode: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case queued = "Queued"
    case finished = "Finished"
    case failed = "Failed"

    var id: String { rawValue }
}

struct DownloadsView: View {
    @EnvironmentObject private var store: DownloadsStore
    @State private var filterMode: DownloadsFilterMode = .all
    @State private var searchText = ""
    @State private var statusMessage: String?

    private var filteredTransfers: [DownloadTransfer] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return sortedTransfers.filter { transfer in
            if filterMode != .all {
                let state = store.transferState(for: transfer)
                switch filterMode {
                case .active:
                    guard state == .active else { return false }
                case .queued:
                    guard state == .queued else { return false }
                case .finished:
                    guard state == .finished else { return false }
                case .failed:
                    guard state == .failed else { return false }
                case .all:
                    break
                }
            }

            guard !query.isEmpty else { return true }

            let haystack = [
                transfer.sourceUsername,
                transfer.status,
                transfer.virtualPath,
                transfer.localPath,
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(query)
        }
    }

    private var sortedTransfers: [DownloadTransfer] {
        store.activeTransfers.sorted { lhs, rhs in
            let lhsRank = stateRank(store.transferState(for: lhs))
            let rhsRank = stateRank(store.transferState(for: rhs))
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.virtualPath.localizedCaseInsensitiveCompare(rhs.virtualPath) == .orderedAscending
        }
    }

    private var activeCount: Int {
        store.activeTransfers.filter { store.transferState(for: $0) == .active }.count
    }

    private var queuedCount: Int {
        store.activeTransfers.filter { store.transferState(for: $0) == .queued }.count
    }

    private var failedCount: Int {
        store.activeTransfers.filter { store.transferState(for: $0) == .failed }.count
    }

    private var totalSpeed: Int {
        store.activeTransfers.reduce(0) { partial, transfer in
            partial + transfer.speed
        }
    }

    private var aggregateProgressText: String {
        let progressAwareTransfers = store.activeTransfers.filter { transfer in
            transfer.totalSize > 0 && store.transferState(for: transfer) != .failed
        }

        let total = progressAwareTransfers.reduce(0) { partial, transfer in
            partial + transfer.totalSize
        }
        guard total > 0 else { return "--" }

        let transferred = progressAwareTransfers.reduce(0) { partial, transfer in
            partial + min(transfer.bytesTransferred, transfer.totalSize)
        }
        let ratio = Double(transferred) / Double(total)
        return "\(Int((ratio * 100).rounded()))%"
    }

    var body: some View {
        VStack(spacing: 10) {
            controlsBar

            DownloadSummaryCard(
                activeCount: activeCount,
                queuedCount: queuedCount,
                failedCount: failedCount,
                totalSpeed: totalSpeed,
                aggregateProgress: aggregateProgressText
            )

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if filteredTransfers.isEmpty {
                ContentUnavailableView(
                    "No Matching Downloads",
                    systemImage: "tray",
                    description: Text("Adjust filters or wait for active transfers.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(filteredTransfers) { transfer in
                    DownloadTransferRow(
                        tx: transfer,
                        state: store.transferState(for: transfer),
                        onRetry: {
                            retryTransfer(transfer)
                        },
                        onDismiss: {
                            store.dismissTransfer(id: transfer.id)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(.easeInOut(duration: 0.2), value: filteredTransfers)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .navigationTitle("Downloads")
    }

    private var controlsBar: some View {
        HStack(spacing: 10) {
            Picker("Filter", selection: $filterMode) {
                ForEach(DownloadsFilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 330)

            TextField("Filter downloads", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)

            Menu {
                Button("Retry Failed Downloads") {
                    retryFailedTransfers()
                }
                .disabled(failedCount == 0)

                Divider()

                Button("Clear Finished") {
                    store.clearFinishedTransfers()
                    statusMessage = "Cleared finished downloads."
                }

                Button("Clear Failed") {
                    store.clearFailedTransfers()
                    statusMessage = "Cleared failed downloads."
                }

                Button("Clear Finished + Failed", role: .destructive) {
                    store.clearInactiveTransfers()
                    statusMessage = "Cleared inactive downloads."
                }
            } label: {
                Label("Manage", systemImage: "slider.horizontal.3")
            }

            Spacer()

            Text("\(filteredTransfers.count) shown")
                .foregroundStyle(.secondary)
        }
    }

    private func retryTransfer(_ transfer: DownloadTransfer) {
        Task {
            let didRetry = await store.retryTransfer(transfer)
            statusMessage = didRetry
                ? "Retry request sent for \(transfer.sourceUsername)."
                : "Retry request failed."
        }
    }

    private func retryFailedTransfers() {
        Task {
            let retried = await store.retryFailedTransfers()
            if retried == 0 {
                statusMessage = "No failed downloads could be retried."
            } else {
                statusMessage = "Retried \(retried) failed downloads."
            }
        }
    }

    private func stateRank(_ state: DownloadTransferState) -> Int {
        switch state {
        case .active:
            return 0
        case .queued:
            return 1
        case .failed:
            return 2
        case .finished:
            return 3
        }
    }
}

private struct DownloadSummaryCard: View {
    let activeCount: Int
    let queuedCount: Int
    let failedCount: Int
    let totalSpeed: Int
    let aggregateProgress: String

    var body: some View {
        HStack(spacing: 10) {
            summaryPill(label: "Active", value: "\(activeCount)")
            summaryPill(label: "Queued", value: "\(queuedCount)")
            summaryPill(label: "Failed", value: "\(failedCount)")
            summaryPill(
                label: "Speed",
                value: "\(ByteCountFormatter.string(fromByteCount: Int64(totalSpeed), countStyle: .file))/s"
            )
            summaryPill(label: "Overall", value: aggregateProgress)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func summaryPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

private struct DownloadTransferRow: View {
    let tx: DownloadTransfer
    let state: DownloadTransferState
    let onRetry: () -> Void
    let onDismiss: () -> Void
    @State private var isHovering = false

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
                TransferStatusIndicator(isActive: state == .active)

                Text("\(tx.sourceUsername) · \(tx.status)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if tx.totalSize > 0 {
                    ProgressView(
                        value: Double(tx.bytesTransferred), total: Double(tx.totalSize)
                    )
                    .frame(width: 130)

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
                .frame(width: 90, alignment: .trailing)

                HStack(spacing: 6) {
                    if state == .failed {
                        Button("Retry") {
                            onRetry()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if state == .finished {
                        Button("Reveal") {
                            revealInFinder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
                .frame(width: state == .active || state == .queued ? 30 : 120, alignment: .trailing)
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
        .contextMenu {
            if state == .failed {
                Button("Retry") {
                    onRetry()
                }
            }

            if state == .finished {
                Button("Reveal in Finder") {
                    revealInFinder()
                }
            }

            Button("Dismiss") {
                onDismiss()
            }
        }
    }

    private func revealInFinder() {
        let resolvedPath = tx.localPath.isEmpty ? tx.virtualPath : tx.localPath
        guard FileManager.default.fileExists(atPath: resolvedPath) else { return }
        NSWorkspace.shared.selectFile(resolvedPath, inFileViewerRootedAtPath: "")
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
