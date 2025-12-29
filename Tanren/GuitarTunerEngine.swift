//
//  GuitarTunerEngine.swift
//  Tanren
//

import AVFoundation
import Accelerate
import Combine

struct TunerNote {
    let name: String
    let octave: Int
    let frequency: Double
    let stringNumber: Int? // 1-6 for guitar strings, nil for other notes

    var displayName: String {
        "\(name)\(octave)"
    }
}

@MainActor
class GuitarTunerEngine: ObservableObject {
    @Published var isRunning = false
    @Published var detectedFrequency: Double = 0
    @Published var detectedNote: TunerNote?
    @Published var centsDeviation: Double = 0
    @Published var isInTune: Bool = false
    @Published var signalLevel: Float = 0
    @Published var hasPermission: Bool = false

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    private let sampleRate: Double = 44100
    private let bufferSize: AVAudioFrameCount = 4096

    // Moving average for smoothing (1 second window)
    private var frequencyHistory: [(frequency: Double, timestamp: Date, level: Float)] = []
    private let smoothingWindow: TimeInterval = 1.0 // 1 second

    // Standard guitar tuning frequencies (string 6 to 1, low to high)
    static let guitarStrings: [TunerNote] = [
        TunerNote(name: "E", octave: 2, frequency: 82.41, stringNumber: 6),
        TunerNote(name: "A", octave: 2, frequency: 110.00, stringNumber: 5),
        TunerNote(name: "D", octave: 3, frequency: 146.83, stringNumber: 4),
        TunerNote(name: "G", octave: 3, frequency: 196.00, stringNumber: 3),
        TunerNote(name: "B", octave: 3, frequency: 246.94, stringNumber: 2),
        TunerNote(name: "E", octave: 4, frequency: 329.63, stringNumber: 1),
    ]

    // All chromatic notes for reference
    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    init() {
        checkPermission()
    }

    /// Set mock values for SwiftUI previews
    func setPreviewData(note: TunerNote, cents: Double, frequency: Double, signalLevel: Float = 0.5) {
        self.detectedNote = note
        self.centsDeviation = cents
        self.detectedFrequency = frequency
        self.signalLevel = signalLevel
        self.isInTune = abs(cents) < 10
    }

    private func checkPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            hasPermission = true
        case .denied:
            hasPermission = false
        case .undetermined:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    func requestPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        await MainActor.run {
            self.hasPermission = granted
        }
        return granted
    }

    func start() async {
        guard !isRunning else { return }

        if !hasPermission {
            let granted = await requestPermission()
            if !granted { return }
        }

        setupAudio()
        isRunning = true
    }

    func stop() {
        isRunning = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        detectedFrequency = 0
        detectedNote = nil
        centsDeviation = 0
        isInTune = false
        signalLevel = 0
        frequencyHistory.removeAll()
    }

    private func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session for tuner: \(error)")
            return
        }

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install tap to receive audio buffers
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine for tuner: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        // Calculate signal level (RMS)
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

        Task { @MainActor in
            self.signalLevel = rms
        }

        // Only process if signal is strong enough - but keep last value on low volume
        // Using a low threshold (0.002) to detect quieter signals, especially from lower strings
        guard rms > 0.002 else {
            // Don't clear the display, just keep the last known value
            return
        }

        // Detect pitch using YIN algorithm
        let frequency = detectPitchYIN(channelData, frameLength: frameLength, sampleRate: buffer.format.sampleRate)

        guard frequency > 60 && frequency < 500 else {
            return
        }

        // Apply moving average weighted by signal level
        let now = Date()
        let smoothedFrequency = addToHistoryAndGetAverage(frequency: frequency, timestamp: now, level: rms)

        Task { @MainActor in
            self.detectedFrequency = smoothedFrequency
            self.updateNoteFromFrequency(smoothedFrequency)
        }
    }

    private func addToHistoryAndGetAverage(frequency: Double, timestamp: Date, level: Float) -> Double {
        // Add new reading
        frequencyHistory.append((frequency: frequency, timestamp: timestamp, level: level))

        // Remove readings older than the smoothing window
        let cutoff = timestamp.addingTimeInterval(-smoothingWindow)
        frequencyHistory.removeAll { $0.timestamp < cutoff }

        // Calculate weighted average - weight by both recency and signal level
        // This prioritizes the initial attack of the note which has the clearest pitch
        guard !frequencyHistory.isEmpty else { return frequency }

        // Find the max level in the window to normalize
        let maxLevel = frequencyHistory.map { $0.level }.max() ?? 1.0

        var weightedSum = 0.0
        var totalWeight = 0.0

        for reading in frequencyHistory {
            let age = timestamp.timeIntervalSince(reading.timestamp)
            let timeWeight = 1.0 - (age / smoothingWindow)
            // Cube the level ratio to very strongly favor louder samples (the attack)
            let levelWeight = Double(reading.level / maxLevel)
            let weight = timeWeight * levelWeight * levelWeight * levelWeight
            weightedSum += reading.frequency * weight
            totalWeight += weight
        }

        return totalWeight > 0 ? weightedSum / totalWeight : frequency
    }

    private func detectPitchAutocorrelation(_ buffer: UnsafeMutablePointer<Float>, frameLength: Int, sampleRate: Double) -> Double {
        let minPeriod = Int(sampleRate / 500) // Max freq ~500Hz
        let maxPeriod = Int(sampleRate / 60)  // Min freq ~60Hz

        guard maxPeriod < frameLength / 2 else { return 0 }

        var bestPeriod = 0
        var bestCorrelation: Float = 0

        for period in minPeriod..<maxPeriod {
            var sum: Float = 0
            var normA: Float = 0
            var normB: Float = 0

            let compareLength = min(frameLength - period, period * 2)

            for i in 0..<compareLength {
                let a = buffer[i]
                let b = buffer[i + period]
                sum += a * b
                normA += a * a
                normB += b * b
            }

            let correlation = sum / (sqrt(normA * normB) + 1e-10)

            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestPeriod = period
            }
        }

        // Require minimum correlation for valid detection
        guard bestCorrelation > 0.8 && bestPeriod > 0 else { return 0 }

        let frequency = sampleRate / Double(bestPeriod)
        return frequency
    }

    private func detectPitchYIN(_ buffer: UnsafeMutablePointer<Float>, frameLength: Int, sampleRate: Double) -> Double {
        // YIN algorithm for robust pitch detection
        // Reference: "YIN, a fundamental frequency estimator for speech and music"
        // by Alain de Cheveigné and Hideki Kawahara

        let minPeriod = Int(sampleRate / 500) // Max freq ~500Hz
        let maxPeriod = Int(sampleRate / 60)  // Min freq ~60Hz
        let yinThreshold: Float = 0.15        // Threshold for peak detection

        guard maxPeriod < frameLength / 2 else { return 0 }

        // Step 1 & 2: Compute difference function d(τ)
        // d(τ) = Σ(x[j] - x[j+τ])²
        var difference = [Float](repeating: 0, count: maxPeriod + 1)

        for tau in 1...maxPeriod {
            var sum: Float = 0
            let windowSize = min(frameLength - tau, frameLength / 2)
            for j in 0..<windowSize {
                let delta = buffer[j] - buffer[j + tau]
                sum += delta * delta
            }
            difference[tau] = sum
        }

        // Step 3: Cumulative mean normalized difference function d'(τ)
        // d'(τ) = d(τ) / ((1/τ) * Σd(j)) for j=1 to τ
        // This normalization helps find the first dip, avoiding octave errors
        var cumulativeMeanNormalized = [Float](repeating: 0, count: maxPeriod + 1)
        cumulativeMeanNormalized[0] = 1

        var runningSum: Float = 0
        for tau in 1...maxPeriod {
            runningSum += difference[tau]
            if runningSum == 0 {
                cumulativeMeanNormalized[tau] = 1
            } else {
                cumulativeMeanNormalized[tau] = difference[tau] * Float(tau) / runningSum
            }
        }

        // Step 4: Absolute threshold - find first tau where d'(τ) < threshold
        // This is the key to avoiding octave errors - we take the FIRST good match
        var bestTau = 0
        for tau in minPeriod...maxPeriod {
            if cumulativeMeanNormalized[tau] < yinThreshold {
                // Found a candidate - now walk forward to find the local minimum
                var searchTau = tau
                while searchTau + 1 <= maxPeriod &&
                      cumulativeMeanNormalized[searchTau + 1] < cumulativeMeanNormalized[searchTau] {
                    searchTau += 1
                }
                bestTau = searchTau
                break
            }
        }

        // If no value below threshold, find global minimum as fallback
        if bestTau == 0 {
            var minValue: Float = Float.infinity
            for tau in minPeriod...maxPeriod {
                if cumulativeMeanNormalized[tau] < minValue {
                    minValue = cumulativeMeanNormalized[tau]
                    bestTau = tau
                }
            }
            // Require the minimum to be reasonably low
            guard minValue < 0.5 else { return 0 }
        }

        guard bestTau > 0 else { return 0 }

        // Step 5: Parabolic interpolation for sub-sample accuracy
        var betterTau = Double(bestTau)
        if bestTau > 0 && bestTau < maxPeriod {
            let s0 = cumulativeMeanNormalized[bestTau - 1]
            let s1 = cumulativeMeanNormalized[bestTau]
            let s2 = cumulativeMeanNormalized[bestTau + 1]

            // Parabolic interpolation: find vertex of parabola through three points
            let denominator = 2 * s1 - s2 - s0
            if abs(denominator) > 1e-10 {
                betterTau = Double(bestTau) + Double(s0 - s2) / (2 * Double(denominator))
            }
        }

        let frequency = sampleRate / betterTau
        return frequency
    }

    private func updateNoteFromFrequency(_ frequency: Double) {
        // Find closest guitar string
        var closestString: TunerNote?
        var closestCents = Double.infinity

        for string in Self.guitarStrings {
            let cents = 1200 * log2(frequency / string.frequency)
            if abs(cents) < abs(closestCents) {
                closestCents = cents
                closestString = string
            }
        }

        // If not close to a guitar string, find the closest chromatic note
        if abs(closestCents) > 100 {
            let note = findClosestChromaticNote(frequency: frequency)
            detectedNote = note.note
            centsDeviation = note.cents
        } else if let string = closestString {
            detectedNote = string
            centsDeviation = closestCents
        }

        // In tune if within ±10 cents
        isInTune = abs(centsDeviation) < 10
    }

    private func findClosestChromaticNote(frequency: Double) -> (note: TunerNote, cents: Double) {
        // A4 = 440Hz as reference
        let a4Frequency = 440.0
        let semitonesFromA4 = 12 * log2(frequency / a4Frequency)
        let nearestSemitone = round(semitonesFromA4)
        let cents = (semitonesFromA4 - nearestSemitone) * 100

        // Calculate note name and octave
        let noteIndex = Int(nearestSemitone + 9 + 1200) % 12 // +9 because A is index 9
        let octave = Int((nearestSemitone + 9 + 1200) / 12) - 96 // Adjust for octave

        let noteName = Self.noteNames[noteIndex]
        let noteFrequency = a4Frequency * pow(2, nearestSemitone / 12)

        // Check if this matches a guitar string
        let stringNumber = Self.guitarStrings.first { $0.name == noteName && $0.octave == octave }?.stringNumber

        return (TunerNote(name: noteName, octave: octave, frequency: noteFrequency, stringNumber: stringNumber), cents)
    }
}
