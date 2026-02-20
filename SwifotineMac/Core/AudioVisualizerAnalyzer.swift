import AVFoundation
import Accelerate
import Foundation

struct AudioVisualizerTimeline {
    static let defaultBandCount = 48
    static let defaultFrameDuration = 1.0 / 30.0

    let frameDuration: Double
    let bandCount: Int
    let frames: [[Float]]

    static func silent(
        bandCount: Int = AudioVisualizerTimeline.defaultBandCount,
        frameDuration: Double = AudioVisualizerTimeline.defaultFrameDuration
    ) -> AudioVisualizerTimeline {
        AudioVisualizerTimeline(
            frameDuration: frameDuration,
            bandCount: bandCount,
            frames: [Array(repeating: 0, count: bandCount)]
        )
    }

    func bands(at seconds: Double) -> [Float] {
        guard !frames.isEmpty else { return Array(repeating: 0, count: bandCount) }
        guard seconds.isFinite, seconds >= 0 else { return frames[0] }
        let index = min(max(Int(seconds / frameDuration), 0), frames.count - 1)
        return frames[index]
    }
}

actor AudioVisualizerAnalyzer {
    static let shared = AudioVisualizerAnalyzer()

    private let bandCount = AudioVisualizerTimeline.defaultBandCount
    private let fftSize = 2048
    private let hopSize = 1024
    private let targetFPS = 30.0
    private let cacheLimit = 20

    private var cache: [String: AudioVisualizerTimeline] = [:]
    private var cacheOrder: [String] = []

    func timeline(for fileURL: URL) async -> AudioVisualizerTimeline {
        let key = fileURL.path
        if let cached = cache[key] {
            promoteCacheKey(key)
            return cached
        }

        let timeline: AudioVisualizerTimeline
        do {
            timeline = try buildTimeline(for: fileURL)
        } catch {
            timeline = .silent()
        }

        cache[key] = timeline
        cacheOrder.removeAll(where: { $0 == key })
        cacheOrder.insert(key, at: 0)
        trimCacheIfNeeded()
        return timeline
    }

    private func buildTimeline(for fileURL: URL) throws -> AudioVisualizerTimeline {
        let file = try AVAudioFile(forReading: fileURL)
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return .silent() }

        let monoSamples = try loadMonoSamples(from: file)
        guard monoSamples.count >= fftSize else {
            return .silent(bandCount: bandCount, frameDuration: 1.0 / targetFPS)
        }

        let fftFrameCount = max(0, ((monoSamples.count - fftSize) / hopSize) + 1)
        guard fftFrameCount > 0 else {
            return .silent(bandCount: bandCount, frameDuration: 1.0 / targetFPS)
        }

        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return .silent(bandCount: bandCount, frameDuration: 1.0 / targetFPS)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfSize = fftSize / 2
        let window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: fftSize,
            isHalfWindow: false
        )
        let binToBand = makeLogBinBandMap(sampleRate: sampleRate, halfBinCount: halfSize)

        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)
        var windowed = [Float](repeating: 0, count: fftSize)

        var rawFrames: [[Float]] = []
        rawFrames.reserveCapacity(fftFrameCount)
        var perBandMax = [Float](repeating: 1e-5, count: bandCount)

        for frameIndex in 0..<fftFrameCount {
            let start = frameIndex * hopSize
            let end = start + fftSize
            guard end <= monoSamples.count else { break }

            for sampleIndex in 0..<fftSize {
                windowed[sampleIndex] = monoSamples[start + sampleIndex]
            }
            vDSP.multiply(windowed, window, result: &windowed)

            real.withUnsafeMutableBufferPointer { realPointer in
                imag.withUnsafeMutableBufferPointer { imagPointer in
                    guard let realBase = realPointer.baseAddress, let imagBase = imagPointer.baseAddress else {
                        return
                    }

                    var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    windowed.withUnsafeBufferPointer { pointer in
                        pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) {
                            complexPointer in
                            vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(halfSize))
                        }
                    }

                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
                }
            }

            var bandSums = [Float](repeating: 0, count: bandCount)
            var bandCounts = [Int](repeating: 0, count: bandCount)

            for bin in 1..<halfSize {
                let band = binToBand[bin]
                guard band >= 0 else { continue }

                let magnitude = sqrtf(magnitudes[bin])
                let perceptual = log1pf(magnitude * 14)
                bandSums[band] += perceptual
                bandCounts[band] += 1
            }

            for band in 0..<bandCount {
                if bandCounts[band] > 0 {
                    bandSums[band] /= Float(bandCounts[band])
                }
                perBandMax[band] = max(perBandMax[band], bandSums[band])
            }

            rawFrames.append(bandSums)
        }

        guard !rawFrames.isEmpty else {
            return .silent(bandCount: bandCount, frameDuration: 1.0 / targetFPS)
        }

        var normalizedFrames = rawFrames
        for index in 0..<normalizedFrames.count {
            for band in 0..<bandCount {
                let normalized = normalizedFrames[index][band] / max(perBandMax[band], 1e-5)
                normalizedFrames[index][band] = min(max(powf(normalized, 0.78), 0), 1)
            }
        }

        applyAdaptiveBandWeighting(to: &normalizedFrames)
        let smoothedFrames = downsampleAndSmooth(
            normalizedFrames,
            sampleRate: sampleRate
        )

        guard !smoothedFrames.isEmpty else {
            return .silent(bandCount: bandCount, frameDuration: 1.0 / targetFPS)
        }

        let outputFrameDuration = 1.0 / targetFPS
        return AudioVisualizerTimeline(
            frameDuration: outputFrameDuration,
            bandCount: bandCount,
            frames: smoothedFrames
        )
    }

    private func loadMonoSamples(from file: AVAudioFile) throws -> [Float] {
        let chunkSize: AVAudioFrameCount = 32_768
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else { return [] }

        var samples: [Float] = []
        let channelDivisor = Float(channelCount)
        let isInterleaved = format.isInterleaved

        while true {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: chunkSize
            ) else {
                break
            }

            do {
                try file.read(into: buffer, frameCount: chunkSize)
            } catch {
                // AVAudioFile can emit nilError at EOF for compressed formats.
                if samples.isEmpty {
                    throw error
                }
                break
            }

            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { break }

            if let floatChannelData = buffer.floatChannelData {
                samples.reserveCapacity(samples.count + frameLength)
                if isInterleaved {
                    let channelData = floatChannelData[0]
                    for frame in 0..<frameLength {
                        let frameOffset = frame * channelCount
                        var sample: Float = 0
                        for channel in 0..<channelCount {
                            sample += channelData[frameOffset + channel]
                        }
                        samples.append(sample / channelDivisor)
                    }
                } else {
                    for frame in 0..<frameLength {
                        var sample: Float = 0
                        for channel in 0..<channelCount {
                            sample += floatChannelData[channel][frame]
                        }
                        samples.append(sample / channelDivisor)
                    }
                }
            } else if let int16ChannelData = buffer.int16ChannelData {
                samples.reserveCapacity(samples.count + frameLength)
                if isInterleaved {
                    let channelData = int16ChannelData[0]
                    for frame in 0..<frameLength {
                        let frameOffset = frame * channelCount
                        var sample: Float = 0
                        for channel in 0..<channelCount {
                            sample += Float(channelData[frameOffset + channel]) / Float(Int16.max)
                        }
                        samples.append(sample / channelDivisor)
                    }
                } else {
                    for frame in 0..<frameLength {
                        var sample: Float = 0
                        for channel in 0..<channelCount {
                            sample += Float(int16ChannelData[channel][frame]) / Float(Int16.max)
                        }
                        samples.append(sample / channelDivisor)
                    }
                }
            } else if let int32ChannelData = buffer.int32ChannelData {
                samples.reserveCapacity(samples.count + frameLength)
                if isInterleaved {
                    let channelData = int32ChannelData[0]
                    for frame in 0..<frameLength {
                        let frameOffset = frame * channelCount
                        var sample: Float = 0
                        for channel in 0..<channelCount {
                            sample += Float(channelData[frameOffset + channel]) / Float(Int32.max)
                        }
                        samples.append(sample / channelDivisor)
                    }
                } else {
                    for frame in 0..<frameLength {
                        var sample: Float = 0
                        for channel in 0..<channelCount {
                            sample += Float(int32ChannelData[channel][frame]) / Float(Int32.max)
                        }
                        samples.append(sample / channelDivisor)
                    }
                }
            } else {
                return []
            }
        }

        return samples
    }

    private func makeLogBinBandMap(sampleRate: Double, halfBinCount: Int) -> [Int] {
        let nyquist = sampleRate / 2
        let minFrequency = 30.0
        let maxFrequency = max(min(16_000.0, nyquist), minFrequency * 1.25)

        let bandEdges: [Double] = (0...bandCount).map { index in
            let t = Double(index) / Double(bandCount)
            return minFrequency * pow(maxFrequency / minFrequency, t)
        }

        var map = [Int](repeating: -1, count: halfBinCount)
        var activeBand = 0

        for bin in 0..<halfBinCount {
            let frequency = Double(bin) * sampleRate / Double(fftSize)
            guard frequency >= minFrequency, frequency <= maxFrequency else { continue }

            while activeBand < bandCount - 1 && frequency > bandEdges[activeBand + 1] {
                activeBand += 1
            }
            map[bin] = activeBand
        }

        return map
    }

    private func applyAdaptiveBandWeighting(to frames: inout [[Float]]) {
        guard !frames.isEmpty else { return }

        var averageByBand = [Float](repeating: 0, count: bandCount)
        for frame in frames {
            for band in 0..<bandCount {
                averageByBand[band] += frame[band]
            }
        }

        for band in 0..<bandCount {
            averageByBand[band] /= Float(frames.count)
        }

        let globalMean = max(averageByBand.reduce(0, +) / Float(bandCount), 1e-5)
        var weights = [Float](repeating: 1, count: bandCount)
        for band in 0..<bandCount {
            let prominence = averageByBand[band] / globalMean
            let deBias = 1 / sqrtf(max(prominence, 0.28))
            let position = Float(band) / Float(max(bandCount - 1, 1))
            let midFocus = 0.9 + (1 - abs((position * 2) - 1)) * 0.24
            weights[band] = min(max(deBias * midFocus, 0.72), 1.28)
        }

        for frameIndex in 0..<frames.count {
            for band in 0..<bandCount {
                frames[frameIndex][band] = min(max(frames[frameIndex][band] * weights[band], 0), 1)
            }
        }
    }

    private func downsampleAndSmooth(
        _ sourceFrames: [[Float]],
        sampleRate: Double
    ) -> [[Float]] {
        guard !sourceFrames.isEmpty else { return [] }

        let sourceFrameDuration = Double(hopSize) / sampleRate
        let targetFrameDuration = 1.0 / targetFPS
        let framesPerChunk = max(1, Int((targetFrameDuration / sourceFrameDuration).rounded()))

        var reduced: [[Float]] = []
        reduced.reserveCapacity(sourceFrames.count / framesPerChunk + 1)

        var start = 0
        while start < sourceFrames.count {
            let end = min(start + framesPerChunk, sourceFrames.count)
            let count = Float(end - start)
            var average = [Float](repeating: 0, count: bandCount)
            var peak = [Float](repeating: 0, count: bandCount)

            for frame in sourceFrames[start..<end] {
                for band in 0..<bandCount {
                    average[band] += frame[band]
                    peak[band] = max(peak[band], frame[band])
                }
            }

            for band in 0..<bandCount {
                average[band] = (average[band] / count) * 0.72 + peak[band] * 0.28
            }
            reduced.append(average)
            start += framesPerChunk
        }

        var smoothed = reduced
        var running = [Float](repeating: 0, count: bandCount)
        var previousEnergy: Float = 0

        for index in 0..<smoothed.count {
            let frame = smoothed[index]
            let energy = frame.reduce(0, +) / Float(bandCount)
            let flux = max(0, energy - previousEnergy)
            previousEnergy = energy

            for band in 0..<bandCount {
                let spectralPosition = Float(band) / Float(max(bandCount - 1, 1))
                let fluxBoost = flux * (0.05 + spectralPosition * 0.06)
                let target = min(max(frame[band] + fluxBoost, 0), 1)
                let current = running[band]
                let interpolation: Float = target > current ? 0.62 : 0.2
                running[band] = current + (target - current) * interpolation
                smoothed[index][band] = running[band]
            }
        }

        return smoothed
    }

    private func promoteCacheKey(_ key: String) {
        cacheOrder.removeAll(where: { $0 == key })
        cacheOrder.insert(key, at: 0)
    }

    private func trimCacheIfNeeded() {
        while cacheOrder.count > cacheLimit {
            let staleKey = cacheOrder.removeLast()
            cache.removeValue(forKey: staleKey)
        }
    }
}
