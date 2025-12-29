//
//  IntervalTimerEngine.swift
//  Tanren
//

import AVFoundation
import Combine

@MainActor
class IntervalTimerEngine: ObservableObject {
    @Published var isRunning = false
    @Published var isCountingIn = false              // True during count-in phase
    @Published var countInRemaining: Int = 0         // Seconds remaining in count-in
    @Published var currentIntervalIndex: Int = 0
    @Published var currentIntervalRemaining: Int = 0  // Seconds remaining in current interval
    @Published var totalRemaining: Int = 0            // Total seconds remaining in set
    @Published var isComplete = false

    private var intervals: [Int] = []
    private var timer: Timer?
    private var hasStartedOnce = false               // Track if we've ever started

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var transitionBuffer: AVAudioPCMBuffer?
    private var completionBuffer: AVAudioPCMBuffer?
    private var countInBeepBuffer: AVAudioPCMBuffer?

    private let sampleRate: Double = 44100
    private let countInDuration = 10                  // 10 second count-in

    init() {
        setupAudio()
    }

    private func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let audioEngine = audioEngine, let playerNode = playerNode else { return }

        audioEngine.attach(playerNode)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        // Generate beep buffers
        transitionBuffer = generateBeepBuffer(format: format, frequency: 880, duration: 0.15)  // High A
        completionBuffer = generateCompletionBuffer(format: format)  // Two-tone completion sound
        countInBeepBuffer = generateBeepBuffer(format: format, frequency: 440, duration: 0.1)  // Lower A for count-in

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }

        // Warm up
        if let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) {
            silentBuffer.frameLength = 1
            silentBuffer.floatChannelData?[0][0] = 0
            playerNode.scheduleBuffer(silentBuffer, at: nil, options: [], completionHandler: nil)
            playerNode.play()
            playerNode.stop()
        }
    }

    private func generateBeepBuffer(format: AVAudioFormat, frequency: Double, duration: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            // Sine wave with fade in/out
            let fadeIn = min(1.0, t / 0.01)
            let fadeOut = min(1.0, (duration - t) / 0.02)
            let envelope = Float(fadeIn * fadeOut)
            let sample = Float(sin(2.0 * .pi * frequency * t)) * envelope * 0.5
            channelData[frame] = sample
        }

        return buffer
    }

    private func generateCompletionBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Two ascending tones for completion
        let duration = 0.4
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        let freq1 = 660.0  // E5
        let freq2 = 880.0  // A5

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate

            // First tone: 0-0.15s, second tone: 0.2-0.4s
            var sample: Float = 0

            if t < 0.15 {
                let fadeIn = min(1.0, t / 0.01)
                let fadeOut = min(1.0, (0.15 - t) / 0.02)
                sample = Float(sin(2.0 * .pi * freq1 * t)) * Float(fadeIn * fadeOut) * 0.5
            } else if t >= 0.2 {
                let localT = t - 0.2
                let fadeIn = min(1.0, localT / 0.01)
                let fadeOut = min(1.0, (0.2 - localT) / 0.02)
                sample = Float(sin(2.0 * .pi * freq2 * t)) * Float(fadeIn * fadeOut) * 0.5
            }

            channelData[frame] = sample
        }

        return buffer
    }

    func configure(intervals: [Int]) {
        self.intervals = intervals
        reset()
    }

    func reset() {
        stop()
        currentIntervalIndex = 0
        isComplete = false
        isCountingIn = false
        countInRemaining = countInDuration
        hasStartedOnce = false
        if !intervals.isEmpty {
            currentIntervalRemaining = intervals[0]
            totalRemaining = intervals.reduce(0, +)
        } else {
            currentIntervalRemaining = 0
            totalRemaining = 0
        }
    }

    func start() {
        guard !isRunning, !intervals.isEmpty, !isComplete else { return }
        isRunning = true

        // Start count-in if this is the first time starting
        if !hasStartedOnce {
            hasStartedOnce = true
            isCountingIn = true
            countInRemaining = countInDuration
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    func stop() {
        pause()
        playerNode?.stop()
    }

    private func tick() {
        guard isRunning else { return }

        // Handle count-in phase
        if isCountingIn {
            countInRemaining -= 1

            // Play beep on each second during count-in
            if countInRemaining > 0 {
                playCountInBeep()
            }

            if countInRemaining <= 0 {
                // Count-in finished, start the actual timer
                isCountingIn = false
                playTransitionBeep()  // Louder beep to signal start
            }
            return
        }

        currentIntervalRemaining -= 1
        totalRemaining -= 1

        if currentIntervalRemaining <= 0 {
            // Current interval finished
            if currentIntervalIndex < intervals.count - 1 {
                // Move to next interval
                currentIntervalIndex += 1
                currentIntervalRemaining = intervals[currentIntervalIndex]
                playTransitionBeep()
            } else {
                // All intervals complete
                isComplete = true
                pause()
                playCompletionBeep()
            }
        }
    }

    private func playCountInBeep() {
        guard let playerNode = playerNode, let buffer = countInBeepBuffer else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func playTransitionBeep() {
        guard let playerNode = playerNode, let buffer = transitionBuffer else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func playCompletionBeep() {
        guard let playerNode = playerNode, let buffer = completionBuffer else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func cleanup() {
        stop()
        audioEngine?.stop()
    }

    // Helper to format seconds as MM:SS
    static func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
