import SwiftUI

struct ProceduralCoverView: View {
    let seed: String
    let title: String
    var cornerRadius: CGFloat = 14
    var symbolScale: CGFloat = 0.34

    var body: some View {
        GeometryReader { proxy in
            let style = ProceduralCoverStyle(seed: seed)
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [style.primary, style.secondary, style.tertiary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                ForEach(Array(style.blobs.enumerated()), id: \.offset) { _, blob in
                    Circle()
                        .fill(blob.color.opacity(blob.opacity))
                        .frame(
                            width: proxy.size.width * blob.size,
                            height: proxy.size.height * blob.size
                        )
                        .offset(
                            x: (blob.x - 0.5) * proxy.size.width,
                            y: (blob.y - 0.5) * proxy.size.height
                        )
                        .blur(radius: proxy.size.width * 0.04)
                }

                Image(systemName: style.symbol)
                    .font(.system(size: proxy.size.width * symbolScale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .rotationEffect(.degrees(style.symbolRotation))
                    .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)

                VStack {
                    Spacer()
                    HStack {
                        Text(initials(from: title))
                            .font(.system(size: max(11, proxy.size.width * 0.12), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.86))
                        Spacer()
                    }
                }
                .padding(proxy.size.width * 0.08)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.32), lineWidth: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func initials(from title: String) -> String {
        let words = title
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .prefix(2)

        let value = words.reduce(into: "") { partialResult, part in
            if let first = part.first {
                partialResult.append(String(first).uppercased())
            }
        }
        return value.isEmpty ? "♪" : value
    }
}

private struct ProceduralCoverStyle {
    struct Blob {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let color: Color
    }

    let primary: Color
    let secondary: Color
    let tertiary: Color
    let symbol: String
    let symbolRotation: Double
    let blobs: [Blob]

    init(seed: String) {
        var rng = SeededGenerator(seed: fnv1a64(seed))

        let hue = rng.nextUnit()
        let saturation = 0.42 + rng.nextUnit() * 0.30
        let brightness = 0.72 + rng.nextUnit() * 0.20

        primary = Color(
            hue: hue,
            saturation: saturation,
            brightness: brightness,
            opacity: 1
        )
        secondary = Color(
            hue: (hue + 0.12).truncatingRemainder(dividingBy: 1),
            saturation: min(saturation + 0.08, 1),
            brightness: max(brightness - 0.16, 0.25),
            opacity: 1
        )
        tertiary = Color(
            hue: (hue + 0.26).truncatingRemainder(dividingBy: 1),
            saturation: max(saturation - 0.12, 0.18),
            brightness: min(brightness + 0.08, 1),
            opacity: 1
        )

        let symbols = [
            "music.note",
            "music.mic",
            "headphones",
            "waveform",
            "guitars",
            "radio",
            "sparkles",
        ]
        symbol = symbols[Int(rng.next() % UInt64(symbols.count))]
        symbolRotation = (rng.nextUnit() * 18) - 9

        var generatedBlobs: [Blob] = []
        let colors = [Color.white, primary, tertiary]
        for index in 0..<4 {
            generatedBlobs.append(
                Blob(
                    x: 0.15 + CGFloat(rng.nextUnit()) * 0.70,
                    y: 0.14 + CGFloat(rng.nextUnit()) * 0.72,
                    size: 0.28 + CGFloat(rng.nextUnit()) * 0.38,
                    opacity: 0.14 + rng.nextUnit() * 0.28,
                    color: colors[index % colors.count]
                )
            )
        }
        blobs = generatedBlobs
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        let value = next() >> 11
        return Double(value) / Double(1 << 53)
    }
}

private func fnv1a64(_ input: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in input.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}
