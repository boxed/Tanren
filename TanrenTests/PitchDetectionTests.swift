//
//  PitchDetectionTests.swift
//  TanrenTests
//
//  Exercises the tuner's signal analysis against synthetic signals that
//  resemble what a guitar actually puts into a phone microphone: strong
//  harmonics, a weak fundamental on the low strings, decay and noise.
//

import Foundation
import Testing
@testable import Tanren

// MARK: - Signal generation

private enum Signal {
    static let sampleRate = 48_000.0

    /// A plucked-string-ish tone: harmonics with decreasing amplitude, each with
    /// its own phase, decaying over time.
    static func pluck(frequency: Double,
                      duration: Double,
                      sampleRate: Double = sampleRate,
                      harmonicAmplitudes: [Double] = [1.0, 0.6, 0.35, 0.2, 0.12, 0.07],
                      decay: Double = 1.5,
                      amplitude: Double = 0.2,
                      noise: Double = 0,
                      seed: UInt64 = 42) -> [Float] {
        var generator = SplitMix64(seed: seed)
        let count = Int(duration * sampleRate)
        var output = [Float](repeating: 0, count: count)

        let phases = harmonicAmplitudes.indices.map { Double($0) * 0.7 }

        for index in 0..<count {
            let time = Double(index) / sampleRate
            var value = 0.0
            for (harmonic, harmonicAmplitude) in harmonicAmplitudes.enumerated() {
                let harmonicFrequency = frequency * Double(harmonic + 1)
                guard harmonicFrequency < sampleRate / 2 else { continue }
                value += harmonicAmplitude * sin(2 * .pi * harmonicFrequency * time + phases[harmonic])
            }
            value *= exp(-decay * time)
            if noise > 0 {
                value += noise * generator.nextGaussian()
            }
            output[index] = Float(value * amplitude)
        }

        return output
    }

    /// Deterministic pseudo random source so failures reproduce.
    struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func nextUnit() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }

        mutating func nextGaussian() -> Double {
            let u1 = max(1e-12, nextUnit())
            let u2 = nextUnit()
            return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        }
    }
}

/// Runs a whole buffer through the analyser and returns the last frame that
/// produced a pitch, which is what the engine would be displaying.
private func detect(_ samples: [Float],
                    sampleRate: Double = Signal.sampleRate,
                    configuration: PitchDetector.Configuration = PitchDetector.Configuration()) -> PitchEstimate? {
    let analyzer = TunerAnalyzer(inputSampleRate: sampleRate, configuration: configuration)
    var last: PitchEstimate?
    samples.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        // Feed in realistic tap sized chunks.
        var offset = 0
        while offset < buffer.count {
            let chunk = min(1024, buffer.count - offset)
            if let frame = analyzer.process(base + offset, count: chunk), let estimate = frame.estimate {
                last = estimate
            }
            offset += chunk
        }
    }
    return last
}

private func cents(_ measured: Double, _ expected: Double) -> Double {
    1200 * log2(measured / expected)
}

// MARK: - Music theory

struct MusicTests {
    @Test func a4IsMidi69() {
        #expect(abs(Music.midi(forFrequency: 440) - 69) < 1e-9)
        #expect(abs(Music.frequency(forMidi: 69) - 440) < 1e-9)
    }

    @Test func middleCIsMidi60() {
        #expect(abs(Music.midi(forFrequency: 261.6255653) - 60) < 1e-6)
        #expect(Music.noteName(forMidi: 60) == "C")
        #expect(Music.octave(forMidi: 60) == 4)
    }

    @Test func guitarStringsMatchStandardTuning() {
        let expected: [(number: Int, name: String, octave: Int, frequency: Double)] = [
            (6, "E", 2, 82.41),
            (5, "A", 2, 110.00),
            (4, "D", 3, 146.83),
            (3, "G", 3, 196.00),
            (2, "B", 3, 246.94),
            (1, "E", 4, 329.63),
        ]

        #expect(GuitarString.standardTuning.count == 6)
        for (string, reference) in zip(GuitarString.standardTuning, expected) {
            #expect(string.number == reference.number)
            #expect(string.noteName == reference.name)
            #expect(string.octave == reference.octave)
            #expect(abs(string.frequency - reference.frequency) < 0.01)
        }
    }

    @Test func stringLookupByMidi() {
        #expect(GuitarString.string(forMidi: 40)?.number == 6)
        #expect(GuitarString.string(forMidi: 64)?.number == 1)
        #expect(GuitarString.string(forMidi: 41) == nil)
    }

    @Test func centsAreSymmetric() {
        #expect(abs(Music.cents(from: 440, to: 440)) < 1e-9)
        #expect(abs(Music.cents(from: 880, to: 440) - 1200) < 1e-9)
        #expect(abs(Music.cents(from: 220, to: 440) + 1200) < 1e-9)
    }
}

// MARK: - Filtering

struct SignalConditionerTests {
    @Test func decimatesToRoughlyTheTargetRate() {
        let conditioner = SignalConditioner(inputSampleRate: 48_000)
        #expect(conditioner.decimation == 4)
        #expect(conditioner.outputSampleRate == 12_000)

        let odd = SignalConditioner(inputSampleRate: 44_100)
        #expect(odd.decimation == 3)
        #expect(abs(odd.outputSampleRate - 14_700) < 1)
    }

    @Test func outputsOneSamplePerDecimationFactor() {
        let conditioner = SignalConditioner(inputSampleRate: 48_000)
        var produced = 0
        for _ in 0..<4_000 {
            if conditioner.push(0.1) != nil { produced += 1 }
        }
        #expect(produced == 1_000)
    }

    @Test func passesTheGuitarBandAndRejectsWhatIsOutsideIt() {
        func gain(of frequency: Double) -> Double {
            let sampleRate = 48_000.0
            let conditioner = SignalConditioner(inputSampleRate: sampleRate)
            var peak = 0.0
            // Skip the first 20 ms so the filters have settled.
            for index in 0..<Int(sampleRate * 0.2) {
                let sample = Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
                if let output = conditioner.push(sample), index > Int(sampleRate * 0.02) {
                    peak = max(peak, abs(Double(output)))
                }
            }
            return peak
        }

        // The fundamentals we care about survive.
        #expect(gain(of: 82.41) > 0.7)
        #expect(gain(of: 329.63) > 0.9)
        // Rumble and hiss do not.
        #expect(gain(of: 12) < 0.1)
        #expect(gain(of: 5_000) < 0.02)
    }
}

// MARK: - Pitch detection

struct PitchDetectorTests {
    /// Every open string, detected to within a couple of cents.
    @Test(arguments: GuitarString.standardTuning)
    func detectsOpenStrings(string: GuitarString) throws {
        let samples = Signal.pluck(frequency: string.frequency, duration: 0.8)
        let estimate = try #require(detect(samples), "no pitch for string \(string.number)")
        #expect(abs(cents(estimate.frequency, string.frequency)) < 2,
                "string \(string.number): got \(estimate.frequency) Hz, want \(string.frequency) Hz")
        #expect(estimate.clarity > 0.8)
    }

    /// Small detunings have to survive: this is the whole point of a tuner.
    @Test(arguments: [-47.0, -21.0, -8.0, -3.0, 0.0, 4.0, 11.0, 33.0, 49.0])
    func resolvesSmallDetunings(offset: Double) throws {
        let target = 110.0 * pow(2, offset / 1200)
        let samples = Signal.pluck(frequency: target, duration: 0.8)
        let estimate = try #require(detect(samples))
        #expect(abs(cents(estimate.frequency, target)) < 2,
                "offset \(offset)¢: got \(estimate.frequency) Hz, want \(target) Hz")
    }

    @Test func staysAccurateAtOtherHardwareSampleRates() throws {
        for sampleRate in [44_100.0, 48_000.0] {
            let samples = Signal.pluck(frequency: 146.83, duration: 0.8, sampleRate: sampleRate)
            let estimate = try #require(detect(samples, sampleRate: sampleRate))
            #expect(abs(cents(estimate.frequency, 146.83)) < 3, "at \(sampleRate) Hz")
        }
    }

    /// A phone microphone rolls off badly under 100 Hz, so the low E arrives
    /// with almost no energy at its fundamental. The period must still be found.
    @Test func handlesAMissingFundamental() throws {
        let samples = Signal.pluck(frequency: 82.41,
                                   duration: 0.8,
                                   harmonicAmplitudes: [0.05, 1.0, 0.7, 0.4, 0.2])
        let estimate = try #require(detect(samples), "octave error on weak fundamental")
        #expect(abs(cents(estimate.frequency, 82.41)) < 5,
                "got \(estimate.frequency) Hz, want 82.41 Hz")
    }

    /// A bright, harmonic heavy note must not read an octave high.
    @Test func doesNotReportAHarmonic() throws {
        let samples = Signal.pluck(frequency: 82.41,
                                   duration: 0.8,
                                   harmonicAmplitudes: [0.5, 1.0, 0.9, 0.8, 0.5, 0.3, 0.2])
        let estimate = try #require(detect(samples))
        #expect(abs(cents(estimate.frequency, 82.41)) < 10,
                "got \(estimate.frequency) Hz, want 82.41 Hz")
    }

    @Test func survivesRoomNoise() throws {
        let samples = Signal.pluck(frequency: 196.0, duration: 0.8, noise: 0.1)
        let estimate = try #require(detect(samples))
        #expect(abs(cents(estimate.frequency, 196.0)) < 6)
    }

    @Test func survivesADecayingNote() throws {
        // Two seconds in, a real pluck is a shadow of itself.
        let samples = Signal.pluck(frequency: 246.94, duration: 2.0, decay: 2.5, amplitude: 0.4)
        let estimate = try #require(detect(samples))
        #expect(abs(cents(estimate.frequency, 246.94)) < 5)
    }

    @Test func reportsNothingForSilence() {
        let samples = [Float](repeating: 0, count: 24_000)
        #expect(detect(samples) == nil)
    }

    @Test func reportsNothingForNoise() {
        var generator = Signal.SplitMix64(seed: 7)
        let samples = (0..<48_000).map { _ in Float(generator.nextGaussian() * 0.05) }
        let estimate = detect(samples)
        // Noise is not periodic; if anything slips through it must be flagged as
        // low clarity rather than presented as a pitch.
        #expect(estimate == nil || estimate!.clarity < 0.8)
    }

    /// Playing the octave harmonic at the twelfth fret is a normal way to tune,
    /// and it has to read as the open string it belongs to.
    @Test func readsAnOctaveHarmonicAsTheOpenString() throws {
        let samples = Signal.pluck(frequency: 329.63 * 2, duration: 0.8, harmonicAmplitudes: [1.0, 0.2])
        let estimate = try #require(detect(samples))
        #expect(abs(cents(estimate.frequency, 329.63)) < 5,
                "got \(estimate.frequency) Hz, want 329.63 Hz")
    }

    /// Whatever comes in, the reading stays inside the range the tuner searches,
    /// so the display can never show a note no guitar can make.
    @Test func neverReportsOutsideTheSearchRange() {
        let configuration = PitchDetector.Configuration()
        for frequency in [1_500.0, 900.0, 700.0, 55.0, 40.0] {
            guard let estimate = detect(Signal.pluck(frequency: frequency,
                                                     duration: 0.6,
                                                     harmonicAmplitudes: [1.0, 0.3])) else { continue }
            #expect(estimate.frequency >= configuration.minFrequency - 1)
            #expect(estimate.frequency <= configuration.maxFrequency + 1)
        }
    }

    @Test func analyzerWindowCoversTheLowestStringManyTimesOver() {
        let analyzer = TunerAnalyzer(inputSampleRate: 48_000)
        let windowSeconds = Double(analyzer.windowSize) / analyzer.workingSampleRate
        #expect(windowSeconds * 82.41 > 15, "window too short for a decisive low E")
        #expect(analyzer.windowSize % 2 == 0, "phase refinement needs equal halves")
        // Update rate fast enough to feel live.
        #expect(Double(analyzer.hopSize) / analyzer.workingSampleRate < 0.1)
    }

    @Test func emitsFramesAtTheHopRate() {
        let analyzer = TunerAnalyzer(inputSampleRate: 48_000)
        let samples = Signal.pluck(frequency: 110, duration: 1.0)
        var frames = 0
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let chunk = min(analyzer.hopSize * analyzer.decimation, buffer.count - offset)
                if analyzer.process(base + offset, count: chunk) != nil { frames += 1 }
                offset += chunk
            }
        }
        // One second of audio, one frame per hop, minus the initial fill.
        let expected = 1.0 / (Double(analyzer.hopSize) / analyzer.workingSampleRate)
        #expect(Double(frames) > expected * 0.6)
    }
}

// MARK: - Smoothing

struct PitchSmootherTests {
    @Test func firstValuePassesStraightThrough() {
        var smoother = PitchSmoother()
        #expect(abs(smoother.update(midi: 45.0) - 45.0) < 1e-9)
    }

    @Test func settlesOnASteadyNote() {
        var smoother = PitchSmoother()
        var value = 0.0
        for _ in 0..<20 {
            value = smoother.update(midi: 45.1)
        }
        #expect(abs(value - 45.1) < 0.001)
    }

    @Test func rejectsAnIsolatedOctaveOutlier() {
        var smoother = PitchSmoother()
        for _ in 0..<6 { _ = smoother.update(midi: 40.0) }
        let after = smoother.update(midi: 52.0)
        #expect(abs(after - 40.0) < 0.05, "one bad frame moved the reading to \(after)")
    }

    @Test func followsARealNoteChangeQuickly() {
        var smoother = PitchSmoother()
        for _ in 0..<6 { _ = smoother.update(midi: 40.0) }
        var value = 0.0
        for _ in 0..<3 { value = smoother.update(midi: 64.0) }
        #expect(abs(value - 64.0) < 0.05, "took too long to move, at \(value)")
    }

    @Test func dampsJitterWithoutLosingTheAverage() {
        var smoother = PitchSmoother()
        let jitter = [45.0, 45.08, 44.94, 45.06, 44.97, 45.03, 44.99, 45.05, 45.0, 44.96]
        var value = 0.0
        for sample in jitter { value = smoother.update(midi: sample) }
        #expect(abs(value - 45.0) < 0.03)
    }

    @Test func resetForgetsHistory() {
        var smoother = PitchSmoother()
        for _ in 0..<6 { _ = smoother.update(midi: 40.0) }
        smoother.reset()
        #expect(smoother.value == nil)
        #expect(abs(smoother.update(midi: 64.0) - 64.0) < 1e-9)
    }
}

// MARK: - Reading

@MainActor
struct TuningReadingTests {
    @Test func mapsToTheNearestNoteByDefault() {
        let engine = TunerEngine.simulated(frequency: 110.0 * pow(2, 8.0 / 1200))
        let reading = engine.reading!
        #expect(reading.targetMidi == 45)
        #expect(reading.noteName == "A")
        #expect(reading.octave == 2)
        #expect(abs(reading.cents - 8) < 0.01)
        #expect(reading.string?.number == 5)
        #expect(!reading.isInTune)
        #expect(reading.isClose)
    }

    @Test func inTuneWithinTolerance() {
        let engine = TunerEngine.simulated(frequency: 196.0 * pow(2, 3.0 / 1200))
        #expect(engine.reading!.isInTune)
    }

    @Test func aNoteBetweenStringsIsNotAString() {
        // F2, a semitone above the low E.
        let engine = TunerEngine.simulated(frequency: Music.frequency(forMidi: 41))
        #expect(engine.reading!.string == nil)
        #expect(engine.reading!.noteName == "F")
    }

    /// A very slack string reads as a lower note unless locked to a target.
    @Test func lockedStringMeasuresAgainstThatString() {
        let slack = GuitarString.standardTuning[0].frequency * pow(2, -300.0 / 1200)

        let auto = TunerEngine.simulated(frequency: slack)
        #expect(auto.reading!.targetMidi == 37)

        let locked = TunerEngine.simulated(frequency: slack,
                                           targetString: GuitarString.standardTuning[0])
        #expect(locked.reading!.targetMidi == 40)
        #expect(abs(locked.reading!.cents + 300) < 0.01)
    }

    /// Beyond a tritone the lock is dropped: the player is on a different string.
    @Test func lockIsAbandonedForADistantNote() {
        let locked = TunerEngine.simulated(frequency: GuitarString.standardTuning[5].frequency,
                                           targetString: GuitarString.standardTuning[0])
        #expect(locked.reading!.targetMidi == 64)
    }
}
