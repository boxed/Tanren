//
//  PitchDetection.swift
//  Tanren
//
//  Pitch detection primitives for the tuner. Pure DSP with no audio session,
//  AVFoundation or UI dependencies so everything here is unit testable against
//  synthetic signals.
//
//  Pipeline: raw mic samples -> SignalConditioner (band limit + decimate)
//            -> PitchDetector (NSDF period detection + phase refinement)
//            -> PitchSmoother (median + adaptive exponential smoothing)
//

import Accelerate
import Foundation

// MARK: - Musical helpers

enum Music {
    /// Concert pitch reference for A4.
    static let referenceFrequency = 440.0

    private static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// Continuous MIDI note number for a frequency. 69 = A4 = 440 Hz.
    static func midi(forFrequency frequency: Double) -> Double {
        69 + 12 * log2(frequency / referenceFrequency)
    }

    static func frequency(forMidi midi: Double) -> Double {
        referenceFrequency * pow(2, (midi - 69) / 12)
    }

    static func noteName(forMidi midi: Int) -> String {
        noteNames[((midi % 12) + 12) % 12]
    }

    /// Scientific pitch notation octave (C4 = middle C = MIDI 60).
    static func octave(forMidi midi: Int) -> Int {
        Int(floor(Double(midi) / 12)) - 1
    }

    /// Signed distance in cents from `reference` to `frequency`.
    static func cents(from frequency: Double, to reference: Double) -> Double {
        1200 * log2(frequency / reference)
    }
}

/// One string of a guitar in standard tuning.
struct GuitarString: Identifiable, Hashable, Sendable {
    /// 6 = thickest/lowest (E2), 1 = thinnest/highest (E4).
    let number: Int
    let midi: Int

    var id: Int { number }
    var frequency: Double { Music.frequency(forMidi: Double(midi)) }
    var noteName: String { Music.noteName(forMidi: midi) }
    var octave: Int { Music.octave(forMidi: midi) }
    var displayName: String { "\(noteName)\(octave)" }

    /// Low to high, i.e. the order strings are usually drawn left to right.
    static let standardTuning: [GuitarString] = [
        GuitarString(number: 6, midi: 40), // E2
        GuitarString(number: 5, midi: 45), // A2
        GuitarString(number: 4, midi: 50), // D3
        GuitarString(number: 3, midi: 55), // G3
        GuitarString(number: 2, midi: 59), // B3
        GuitarString(number: 1, midi: 64), // E4
    ]

    static func string(forMidi midi: Int) -> GuitarString? {
        standardTuning.first { $0.midi == midi }
    }
}

// MARK: - Biquad filtering

/// Direct form I biquad section. Used to build the band limiting cascade that
/// runs ahead of decimation.
struct Biquad {
    private let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    static func lowPass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        let w0 = 2 * .pi * min(cutoff, sampleRate * 0.49) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        return Biquad(b0: (1 - cosw) / 2, b1: 1 - cosw, b2: (1 - cosw) / 2,
                      a0: 1 + alpha, a1: -2 * cosw, a2: 1 - alpha)
    }

    static func highPass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        let w0 = 2 * .pi * min(cutoff, sampleRate * 0.49) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        return Biquad(b0: (1 + cosw) / 2, b1: -(1 + cosw), b2: (1 + cosw) / 2,
                      a0: 1 + alpha, a1: -2 * cosw, a2: 1 - alpha)
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }

    mutating func reset() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }
}

/// Removes rumble and everything well above the guitar's fundamental range,
/// then decimates so the period search runs at a sane rate.
///
/// Band limiting matters twice over: it prevents aliasing when decimating, and
/// it strips the upper harmonics that make raw guitar autocorrelation pick the
/// wrong octave.
final class SignalConditioner {
    let inputSampleRate: Double
    let decimation: Int
    let outputSampleRate: Double

    private var highPass: Biquad
    /// Fourth order Butterworth, split into two sections.
    private var lowPass: [Biquad]
    private var counter = 0

    init(inputSampleRate: Double,
         targetSampleRate: Double = 12_000,
         highPassCutoff: Double = 50,
         lowPassCutoff: Double = 1_100) {
        self.inputSampleRate = inputSampleRate
        self.decimation = max(1, Int((inputSampleRate / targetSampleRate).rounded(.down)))
        self.outputSampleRate = inputSampleRate / Double(decimation)

        highPass = .highPass(cutoff: highPassCutoff, sampleRate: inputSampleRate, q: 0.7071)
        lowPass = [
            .lowPass(cutoff: lowPassCutoff, sampleRate: inputSampleRate, q: 0.5412),
            .lowPass(cutoff: lowPassCutoff, sampleRate: inputSampleRate, q: 1.3066),
        ]
    }

    /// Filters one input sample. Returns a value on the sample that survives
    /// decimation, `nil` otherwise.
    func push(_ sample: Float) -> Float? {
        var value = highPass.process(Double(sample))
        for index in lowPass.indices {
            value = lowPass[index].process(value)
        }

        counter += 1
        guard counter >= decimation else { return nil }
        counter = 0
        return Float(value)
    }

    func reset() {
        highPass.reset()
        for index in lowPass.indices { lowPass[index].reset() }
        counter = 0
    }
}

// MARK: - Pitch detection

struct PitchEstimate: Equatable {
    /// Estimated fundamental in Hz.
    let frequency: Double
    /// Periodicity of the winning candidate, 0...1. Low values mean noise.
    let clarity: Double
}

/// Fundamental frequency estimation using the normalised square difference
/// function (the McLeod pitch method) with a phase based refinement pass.
///
/// The NSDF finds the period robustly even when the fundamental is weak, which
/// is the normal case for a low E played into a phone microphone. Its
/// resolution is limited by the sample period though, so the coarse estimate is
/// then refined by measuring how much the phase of the fundamental advances
/// between the two halves of the window. That gives sub-cent resolution without
/// needing a huge FFT.
final class PitchDetector {
    struct Configuration {
        /// Lowest fundamental to look for. Below the low E (82.4 Hz) with room
        /// for a badly slack string.
        var minFrequency = 58.0
        /// Highest fundamental to look for. Well above the high E (329.6 Hz).
        var maxFrequency = 520.0
        /// A candidate peak wins if it reaches this fraction of the tallest
        /// peak. Picking the earliest such peak is what keeps the detector from
        /// latching onto a harmonic.
        var peakThreshold = 0.90
        /// Minimum periodicity for a usable reading.
        var minClarity = 0.62
        /// Upper bound for the harmonic used by the refinement pass. Must stay
        /// inside the conditioner's pass band.
        var maxRefinementFrequency = 900.0

        init() {}
    }

    let sampleRate: Double
    let windowSize: Int
    let configuration: Configuration

    private let minLag: Int
    private let maxLag: Int
    /// Number of samples compared at every lag. Fixed across lags so the NSDF
    /// is not biased towards short periods.
    private let correlationLength: Int

    private var nsdf: [Double]
    private var cumulativeEnergy: [Double]
    private var hannHalf: [Double]

    init(sampleRate: Double, windowSize: Int, configuration: Configuration = Configuration()) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.configuration = configuration

        minLag = max(2, Int((sampleRate / configuration.maxFrequency).rounded(.down)))
        maxLag = min(windowSize / 2 - 1, Int((sampleRate / configuration.minFrequency).rounded(.up)) + 1)
        correlationLength = windowSize - maxLag

        nsdf = [Double](repeating: 0, count: maxLag + 2)
        cumulativeEnergy = [Double](repeating: 0, count: windowSize + 1)

        let half = windowSize / 2
        hannHalf = (0..<half).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(half)) }
    }

    func estimate(_ samples: [Float]) -> PitchEstimate? {
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return nil }
            return estimate(base, count: buffer.count)
        }
    }

    func estimate(_ samples: UnsafePointer<Float>, count: Int) -> PitchEstimate? {
        guard count >= windowSize, maxLag > minLag, correlationLength > minLag else { return nil }

        computeNSDF(samples)

        guard let peak = pickPeak() else { return nil }
        guard peak.clarity >= configuration.minClarity else { return nil }

        let coarse = sampleRate / peak.lag
        guard coarse >= configuration.minFrequency, coarse <= configuration.maxFrequency else { return nil }

        let refined = refineByPhase(coarse: coarse, samples: samples)
        return PitchEstimate(frequency: refined, clarity: peak.clarity)
    }

    // MARK: NSDF

    /// n(τ) = 2·r(τ) / (Σx[j]² + Σx[j+τ]²), evaluated over a fixed length
    /// window. Ranges from -1 to 1 with 1 meaning perfectly periodic at τ.
    private func computeNSDF(_ samples: UnsafePointer<Float>) {
        cumulativeEnergy[0] = 0
        for index in 0..<windowSize {
            let value = Double(samples[index])
            cumulativeEnergy[index + 1] = cumulativeEnergy[index] + value * value
        }

        let headEnergy = cumulativeEnergy[correlationLength] - cumulativeEnergy[0]

        for lag in minLag...maxLag {
            var correlation: Float = 0
            vDSP_dotpr(samples, 1, samples + lag, 1, &correlation, vDSP_Length(correlationLength))

            let tailEnergy = cumulativeEnergy[lag + correlationLength] - cumulativeEnergy[lag]
            let denominator = headEnergy + tailEnergy
            nsdf[lag] = denominator > 1e-12 ? 2 * Double(correlation) / denominator : 0
        }
    }

    /// Picks the earliest local maximum that comes within `peakThreshold` of the
    /// tallest one, then interpolates its true position.
    private func pickPeak() -> (lag: Double, clarity: Double)? {
        var peaks: [(lag: Int, value: Double)] = []
        var tallest = -Double.infinity

        var lag = minLag + 1
        while lag < maxLag {
            let value = nsdf[lag]
            if value > 0, value > nsdf[lag - 1], value >= nsdf[lag + 1] {
                peaks.append((lag, value))
                tallest = max(tallest, value)
                // Skip past the falling side of this peak.
                while lag < maxLag, nsdf[lag + 1] <= nsdf[lag] { lag += 1 }
            }
            lag += 1
        }

        guard !peaks.isEmpty, tallest > 0 else { return nil }

        let cutoff = tallest * configuration.peakThreshold
        guard let winner = peaks.first(where: { $0.value >= cutoff }) else { return nil }

        return interpolatePeak(at: winner.lag)
    }

    /// Fits a parabola through the peak and its neighbours for sub-sample
    /// resolution on both position and height.
    private func interpolatePeak(at lag: Int) -> (lag: Double, clarity: Double) {
        guard lag > 0, lag < maxLag else { return (Double(lag), nsdf[lag]) }

        let previous = nsdf[lag - 1]
        let current = nsdf[lag]
        let next = nsdf[lag + 1]

        let denominator = 2 * current - previous - next
        guard abs(denominator) > 1e-12 else { return (Double(lag), current) }

        let offset = (next - previous) / (2 * denominator)
        guard abs(offset) <= 1 else { return (Double(lag), current) }

        let height = current + (next - previous) * offset / 4
        return (Double(lag) + offset, min(1, max(-1, height)))
    }

    // MARK: Phase refinement

    /// Refines the coarse estimate by measuring how far the phase of a partial
    /// drifts between the first and second half of the window.
    ///
    /// The strongest of the first few harmonics is used rather than always the
    /// fundamental, because a low E played into a phone microphone often has
    /// almost no energy at 82 Hz while its octave is loud and clean.
    ///
    /// With half-window length L, a correction measured at harmonic h is
    /// unambiguous while the coarse estimate is within ±fs/(2Lh) — still an
    /// order of magnitude wider than the NSDF's error. Anything larger is
    /// rejected rather than trusted.
    private func refineByPhase(coarse: Double, samples: UnsafePointer<Float>) -> Double {
        let half = windowSize / 2
        guard half > 8 else { return coarse }

        let rms = sqrt(cumulativeEnergy[windowSize] / Double(windowSize))
        let minimumMagnitude = 0.03 * rms * Double(half)
        guard minimumMagnitude > 0 else { return coarse }

        var bestCorrection = 0.0
        var bestMagnitude = 0.0

        for harmonic in 1...3 {
            let target = coarse * Double(harmonic)
            if target > configuration.maxRefinementFrequency { break }

            let measurement = measurePhaseAdvance(frequency: target, samples: samples, half: half)
            guard measurement.magnitude > minimumMagnitude, measurement.magnitude > bestMagnitude else { continue }

            let correction = measurement.phaseAdvance * sampleRate
                / (2 * .pi * Double(half) * Double(harmonic))
            // Half the unambiguous range, and never more than ~50 cents.
            let limit = min(sampleRate / (4 * Double(half) * Double(harmonic)), coarse * 0.03)
            guard abs(correction) < limit else { continue }

            bestCorrection = correction
            bestMagnitude = measurement.magnitude
        }

        return coarse + bestCorrection
    }

    /// Windowed single-bin DFT over each half of the window, demodulated against
    /// the absolute sample index so the phase difference reflects only the error
    /// in `frequency`.
    private func measurePhaseAdvance(frequency: Double,
                                     samples: UnsafePointer<Float>,
                                     half: Int) -> (magnitude: Double, phaseAdvance: Double) {
        let omega = 2 * .pi * frequency / sampleRate
        var firstReal = 0.0, firstImaginary = 0.0
        var secondReal = 0.0, secondImaginary = 0.0

        for index in 0..<(half * 2) {
            let windowed = Double(samples[index]) * hannHalf[index % half]
            let phase = -omega * Double(index)
            let real = windowed * cos(phase)
            let imaginary = windowed * sin(phase)
            if index < half {
                firstReal += real
                firstImaginary += imaginary
            } else {
                secondReal += real
                secondImaginary += imaginary
            }
        }

        let firstMagnitude = (firstReal * firstReal + firstImaginary * firstImaginary).squareRoot()
        let secondMagnitude = (secondReal * secondReal + secondImaginary * secondImaginary).squareRoot()
        guard firstMagnitude > 1e-9, secondMagnitude > 1e-9 else { return (0, 0) }

        let difference = atan2(secondImaginary, secondReal) - atan2(firstImaginary, firstReal)
        let wrapped = atan2(sin(difference), cos(difference))
        return (min(firstMagnitude, secondMagnitude), wrapped)
    }
}

// MARK: - Smoothing

/// Turns a stream of per-frame estimates into a display value that is steady
/// when a note is held but still snaps quickly when a different string is
/// played.
///
/// Smoothing happens in semitones rather than Hz: averaging in the log domain
/// keeps the cents readout linear, and a median rejects the occasional octave
/// outlier instead of dragging the reading halfway to it.
struct PitchSmoother {
    /// Number of raw values the median is taken over.
    var historyLength = 5
    /// A move larger than this (in semitones) is treated as a new note.
    var snapThreshold = 0.4
    /// Exponential weight applied once the reading has settled.
    var responsiveness = 0.3

    private var history: [Double] = []
    private(set) var value: Double?

    init() {}

    /// Feeds one raw estimate in continuous MIDI numbers, returning the value
    /// to display.
    mutating func update(midi: Double) -> Double {
        history.append(midi)
        if history.count > historyLength { history.removeFirst() }

        let target = history.sorted()[history.count / 2]

        guard let current = value else {
            value = target
            return target
        }

        let distance = abs(target - current)
        let alpha = distance > snapThreshold ? 1.0 : responsiveness
        let updated = current + (target - current) * alpha
        value = updated
        return updated
    }

    mutating func reset() {
        history.removeAll(keepingCapacity: true)
        value = nil
    }
}

// MARK: - Frame analysis

/// One analysis result produced by `TunerAnalyzer`.
struct TunerFrame: Sendable {
    /// RMS of the band limited signal, 0...1.
    let level: Float
    /// Pitch, or `nil` when the frame was too quiet or too noisy to trust.
    let estimate: PitchEstimate?
}

/// Accumulates microphone samples into overlapping analysis windows and runs
/// the detector on each. Lives entirely on the audio thread; it allocates only
/// at init so the render callback stays real time safe.
final class TunerAnalyzer {
    let inputSampleRate: Double
    let workingSampleRate: Double
    /// Input samples consumed per working sample.
    let decimation: Int
    let windowSize: Int
    let hopSize: Int

    /// Below this RMS there is nothing worth analysing.
    private let noiseFloor: Float = 0.0012

    private let conditioner: SignalConditioner
    private let detector: PitchDetector

    private var ring: [Float]
    private var window: [Float]
    private var writeIndex = 0
    private var samplesBuffered = 0
    private var samplesSinceAnalysis = 0

    /// - Parameters:
    ///   - windowDuration: Analysis window length. 0.25 s gives roughly twenty
    ///     periods of the low E, which the NSDF needs to be decisive.
    ///   - hopDuration: Time between analyses, i.e. the update interval.
    init(inputSampleRate: Double,
         windowDuration: Double = 0.25,
         hopDuration: Double = 0.06,
         configuration: PitchDetector.Configuration = PitchDetector.Configuration()) {
        self.inputSampleRate = inputSampleRate
        conditioner = SignalConditioner(inputSampleRate: inputSampleRate)
        workingSampleRate = conditioner.outputSampleRate
        decimation = conditioner.decimation

        // Even window size keeps the two phase refinement halves equal.
        windowSize = max(512, Int((windowDuration * workingSampleRate).rounded()) & ~1)
        hopSize = max(64, Int((hopDuration * workingSampleRate).rounded()))

        detector = PitchDetector(sampleRate: workingSampleRate,
                                 windowSize: windowSize,
                                 configuration: configuration)

        ring = [Float](repeating: 0, count: windowSize)
        window = [Float](repeating: 0, count: windowSize)
    }

    /// Feeds interleaved-free mono samples. Returns a frame each time a full hop
    /// has been accumulated, otherwise `nil`.
    func process(_ samples: UnsafePointer<Float>, count: Int) -> TunerFrame? {
        var result: TunerFrame?

        for index in 0..<count {
            guard let sample = conditioner.push(samples[index]) else { continue }

            ring[writeIndex] = sample
            writeIndex = (writeIndex + 1) % windowSize
            samplesBuffered = min(samplesBuffered + 1, windowSize)
            samplesSinceAnalysis += 1

            if samplesSinceAnalysis >= hopSize, samplesBuffered >= windowSize {
                samplesSinceAnalysis = 0
                result = analyze()
            }
        }

        return result
    }

    func reset() {
        conditioner.reset()
        for index in ring.indices { ring[index] = 0 }
        writeIndex = 0
        samplesBuffered = 0
        samplesSinceAnalysis = 0
    }

    private func analyze() -> TunerFrame {
        // Linearise the ring buffer, oldest sample first.
        let tail = windowSize - writeIndex
        window.withUnsafeMutableBufferPointer { destination in
            ring.withUnsafeBufferPointer { source in
                guard let to = destination.baseAddress, let from = source.baseAddress else { return }
                to.update(from: from + writeIndex, count: tail)
                (to + tail).update(from: from, count: writeIndex)
            }
        }

        var level: Float = 0
        window.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            vDSP_rmsqv(base, 1, &level, vDSP_Length(windowSize))
        }

        guard level > noiseFloor else { return TunerFrame(level: level, estimate: nil) }
        return TunerFrame(level: level, estimate: detector.estimate(window))
    }
}
