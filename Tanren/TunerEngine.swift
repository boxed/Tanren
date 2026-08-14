//
//  TunerEngine.swift
//  Tanren
//
//  Microphone plumbing and observable state for the tuner. All signal analysis
//  lives in PitchDetection.swift; this type owns the audio session, feeds the
//  analyser from the input tap and publishes a display ready reading.
//

import AVFoundation
import Observation
import UIKit

/// A pitch as the tuner wants to show it: which note is being aimed at, and how
/// far off the played string is.
struct TuningReading: Equatable, Sendable {
    /// Smoothed fundamental in Hz.
    let frequency: Double
    /// The note being tuned towards.
    let targetMidi: Int
    /// Signed distance from the target note. Negative is flat.
    let cents: Double
    /// The guitar string this target corresponds to, if any.
    let string: GuitarString?

    var noteName: String { Music.noteName(forMidi: targetMidi) }
    var octave: Int { Music.octave(forMidi: targetMidi) }
    var targetFrequency: Double { Music.frequency(forMidi: Double(targetMidi)) }

    var isInTune: Bool { abs(cents) <= TunerEngine.inTuneTolerance }
    var isClose: Bool { abs(cents) <= TunerEngine.closeTolerance }
}

@MainActor
@Observable
final class TunerEngine {
    /// Deviation treated as in tune. Tighter than the ±10 cents a player can
    /// hear on a single string, because beating between two strings gives away
    /// smaller errors than that.
    static let inTuneTolerance = 4.0
    /// Deviation still shown as nearly there.
    static let closeTolerance = 20.0

    enum MicrophoneAccess {
        case undetermined, granted, denied
    }

    enum Mode {
        /// Reads the microphone.
        case live
        /// Holds whatever state is assigned to it. For previews and tests.
        case simulated
    }

    // MARK: Observable state

    private(set) var access: MicrophoneAccess = .undetermined
    private(set) var isListening = false
    /// Input loudness, 0...1, for the level meter.
    private(set) var level: Double = 0
    /// Periodicity of the current reading, 0...1.
    private(set) var clarity: Double = 0
    private(set) var reading: TuningReading?
    /// True when nothing has been heard recently, so the last reading is only
    /// still on screen as a memory.
    private(set) var isStale = true
    private(set) var failureMessage: String?

    /// Strings confirmed in tune during this session.
    private(set) var tunedStrings: Set<Int> = []

    /// When set, deviation is measured against this string instead of the
    /// nearest note, so a badly slack string still reads as "very flat" rather
    /// than as some unrelated note.
    var targetString: GuitarString? {
        didSet {
            guard targetString != oldValue else { return }
            heldFrames = 0
            heldString = nil
            if let smoothed = smoother.value {
                reading = makeReading(midi: smoothed)
            }
        }
    }

    // MARK: Private state

    private let mode: Mode
    private var smoother = PitchSmoother()

    private var audioEngine: AVAudioEngine?
    private var analyzer: TunerAnalyzer?
    private var frames: AsyncStream<TunerFrame>.Continuation?
    private var consumer: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var wasInterrupted = false

    private var quietFrames = 0
    private var heldFrames = 0
    private var heldString: Int?
    private var wasInTune = false

    private let tickHaptics = UIImpactFeedbackGenerator(style: .rigid)
    private let confirmHaptics = UINotificationFeedbackGenerator()

    init(mode: Mode = .live) {
        self.mode = mode
        if mode == .live {
            access = Self.currentAccess()
        } else {
            access = .granted
        }
    }

    // MARK: Lifecycle

    func start() async {
        guard mode == .live, !isListening else { return }

        if access != .granted {
            let granted = await AVAudioApplication.requestRecordPermission()
            access = granted ? .granted : .denied
            guard granted else { return }
        }

        failureMessage = nil
        do {
            try beginListening()
        } catch {
            failureMessage = "Could not start listening: \(error.localizedDescription)"
            teardownAudio()
        }
    }

    func stop() {
        guard mode == .live else { return }
        removeObservers()
        teardownAudio()
        deactivateSession()
        level = 0
        clarity = 0
        isStale = true
    }

    /// Forgets which strings have been tuned. Called when the tuner is opened.
    func resetProgress() {
        tunedStrings.removeAll()
        heldFrames = 0
        heldString = nil
    }

    private func beginListening() throws {
        let session = AVAudioSession.sharedInstance()
        // .measurement disables the input processing (AGC, noise suppression,
        // EQ) that would otherwise chew up a decaying guitar note. Bluetooth
        // input is deliberately not allowed: headset mics are narrowband and
        // heavily processed.
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TunerError.noInputAvailable
        }

        let analyzer = TunerAnalyzer(inputSampleRate: format.sampleRate)
        let (stream, continuation) = AsyncStream<TunerFrame>.makeStream(bufferingPolicy: .bufferingNewest(4))

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            if let frame = analyzer.process(channel, count: Int(buffer.frameLength)) {
                continuation.yield(frame)
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        self.analyzer = analyzer
        frames = continuation
        consumer = Task { [weak self] in
            for await frame in stream {
                self?.apply(frame)
            }
        }

        smoother.reset()
        quietFrames = 0
        isStale = true
        isListening = true
        observeSystemEvents()
        tickHaptics.prepare()
        confirmHaptics.prepare()
    }

    private func teardownAudio() {
        consumer?.cancel()
        consumer = nil
        frames?.finish()
        frames = nil
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
        analyzer = nil
        smoother.reset()
        isListening = false
    }

    /// Hands the session back in a state the metronome can use.
    private func deactivateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Not fatal; the metronome reasserts the session when it plays.
        }
    }

    private static func currentAccess() -> MicrophoneAccess {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    // MARK: Frame handling

    private func apply(_ frame: TunerFrame) {
        level = Self.displayLevel(rms: frame.level)

        guard let estimate = frame.estimate else {
            quietFrames += 1
            // Roughly a third of a second of silence ends the note: drop the
            // smoothing history so the next string is picked up immediately.
            if quietFrames >= 5 {
                isStale = true
                clarity = 0
                smoother.reset()
                heldFrames = 0
                wasInTune = false
            }
            return
        }

        quietFrames = 0
        isStale = false
        clarity = estimate.clarity

        let smoothed = smoother.update(midi: Music.midi(forFrequency: estimate.frequency))
        let reading = makeReading(midi: smoothed)
        self.reading = reading
        updateProgress(with: reading)
    }

    private func makeReading(midi: Double) -> TuningReading {
        let targetMidi: Int
        if let targetString, abs(midi - Double(targetString.midi)) <= 6 {
            targetMidi = targetString.midi
        } else {
            targetMidi = Int(midi.rounded())
        }

        return TuningReading(frequency: Music.frequency(forMidi: midi),
                             targetMidi: targetMidi,
                             cents: (midi - Double(targetMidi)) * 100,
                             string: GuitarString.string(forMidi: targetMidi))
    }

    private func updateProgress(with reading: TuningReading) {
        if reading.isInTune, !wasInTune {
            tickHaptics.impactOccurred(intensity: 0.7)
        }
        wasInTune = reading.isInTune

        guard let string = reading.string else {
            heldFrames = 0
            heldString = nil
            return
        }

        if reading.isInTune {
            if heldString == string.number {
                heldFrames += 1
            } else {
                heldString = string.number
                heldFrames = 1
            }
            // Held steady for roughly a quarter of a second.
            if heldFrames >= 4, tunedStrings.insert(string.number).inserted {
                confirmHaptics.notificationOccurred(.success)
            }
        } else {
            heldFrames = 0
            heldString = nil
            if abs(reading.cents) > Self.inTuneTolerance * 2 {
                tunedStrings.remove(string.number)
            }
        }
    }

    /// Maps RMS onto a meter friendly 0...1 using decibels, so quiet notes still
    /// move the bar.
    private static func displayLevel(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(1, max(0, (decibels + 55) / 45))
    }

    // MARK: System events

    private func observeSystemEvents() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                           object: AVAudioSession.sharedInstance(),
                                           queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            Task { @MainActor in self?.handleInterruption(raw: raw) }
        })

        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                           object: nil,
                                           queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restartAfterConfigurationChange() }
        })
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func handleInterruption(raw: UInt) {
        switch AVAudioSession.InterruptionType(rawValue: raw) {
        case .began:
            wasInterrupted = true
            teardownAudio()
        case .ended:
            guard wasInterrupted else { return }
            wasInterrupted = false
            Task { await start() }
        default:
            break
        }
    }

    /// The engine's input format changes when the route does — plugging in a
    /// headset, for instance. The tap and analyser have to be rebuilt for the
    /// new sample rate.
    private func restartAfterConfigurationChange() {
        guard isListening else { return }
        teardownAudio()
        do {
            try beginListening()
        } catch {
            failureMessage = "Audio input changed and could not be restarted."
        }
    }

    // MARK: Previews

    /// Builds an engine with a fixed reading, for previews.
    static func simulated(frequency: Double,
                          targetString: GuitarString? = nil,
                          level: Double = 0.7,
                          tunedStrings: Set<Int> = []) -> TunerEngine {
        let engine = TunerEngine(mode: .simulated)
        engine.level = level
        engine.clarity = 0.95
        engine.isStale = false
        engine.tunedStrings = tunedStrings
        engine.targetString = targetString
        engine.reading = engine.makeReading(midi: Music.midi(forFrequency: frequency))
        return engine
    }

    static func simulatedSilence() -> TunerEngine {
        let engine = TunerEngine(mode: .simulated)
        engine.level = 0.04
        return engine
    }

    static func simulatedDenied() -> TunerEngine {
        let engine = TunerEngine(mode: .simulated)
        engine.access = .denied
        return engine
    }
}

enum TunerError: LocalizedError {
    case noInputAvailable

    var errorDescription: String? {
        switch self {
        case .noInputAvailable:
            return "No audio input is available."
        }
    }
}
