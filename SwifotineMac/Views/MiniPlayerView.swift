import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var playbackEngine: PlaybackEngine
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ArtworkThumbnail(image: playbackEngine.currentArtwork, size: 72)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if playbackEngine.state == .playing {
                            MiniNowPlayingPulseDot()
                        }

                        Text(playbackEngine.currentTrack?.title ?? "Not Playing")
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text(playbackEngine.currentTrack?.artist ?? "No artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let queuedTrack = playbackEngine.upNext.first {
                        Text("Up next: \(queuedTrack.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }

            VStack(spacing: 6) {
                HStack {
                    Text(formatTime(playbackEngine.currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: {
                                isScrubbing ? scrubTime : playbackEngine.currentTime
                            },
                            set: { newValue in
                                scrubTime = newValue
                            }),
                        in: 0...max(playbackEngine.duration, 1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                playbackEngine.seek(to: scrubTime)
                            }
                        }
                    )

                    Text(formatTime(playbackEngine.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 18) {
                Button {
                    playbackEngine.seek(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                }
                .help("Back 10 Seconds")

                Button {
                    playbackEngine.togglePlayPause()
                } label: {
                    Image(systemName: playbackEngine.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30, weight: .regular))
                }
                .help("Play or Pause")

                Button {
                    playbackEngine.seek(by: 10)
                } label: {
                    Image(systemName: "goforward.10")
                }
                .help("Forward 10 Seconds")

                Button {
                    playbackEngine.skipToNextInQueue()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(playbackEngine.upNext.isEmpty)
                .help("Next in Queue")

                Button {
                    playbackEngine.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help("Stop")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 210)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .onChange(of: playbackEngine.currentTime) { _, newValue in
            if !isScrubbing {
                scrubTime = newValue
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite, time > 0 else { return "00:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ArtworkThumbnail: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MiniNowPlayingPulseDot: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            let opacity = 0.45 + (phase * 0.5)
            let scale = 0.72 + (phase * 0.28)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .opacity(opacity)
                .scaleEffect(scale)
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}
