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

    // Timing based on elapsed time to prevent drift
    private var countInStartTime: Date?
    private var timerStartTime: Date?
    private var totalIntervalTime: Int = 0           // Sum of all intervals
    private var lastProcessedSecond: Int = -1        // Track last second to avoid duplicate sounds
    private var lastCountdownBeepPlayed: Int = 0     // Track countdown beeps (3, 2, 1) before intervals

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
        // Double-beep: two identical tones at same frequency
        let duration = 0.35
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        let freq = 880.0  // High A

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate

            // First beep: 0-0.12s, second beep: 0.18-0.30s
            var sample: Float = 0

            if t < 0.12 {
                let fadeIn = min(1.0, t / 0.01)
                let fadeOut = min(1.0, (0.12 - t) / 0.02)
                sample = Float(sin(2.0 * .pi * freq * t)) * Float(fadeIn * fadeOut) * 0.5
            } else if t >= 0.18 && t < 0.30 {
                let localT = t - 0.18
                let fadeIn = min(1.0, localT / 0.01)
                let fadeOut = min(1.0, (0.12 - localT) / 0.02)
                sample = Float(sin(2.0 * .pi * freq * t)) * Float(fadeIn * fadeOut) * 0.5
            }

            channelData[frame] = sample
        }

        return buffer
    }

    func configure(intervals: [Int]) {
        self.intervals = intervals
        self.totalIntervalTime = intervals.reduce(0, +)
        reset()
    }

    func reset() {
        stop()
        currentIntervalIndex = 0
        isComplete = false
        isCountingIn = false
        countInRemaining = countInDuration
        hasStartedOnce = false
        countInStartTime = nil
        timerStartTime = nil
        lastProcessedSecond = -1
        lastCountdownBeepPlayed = 0
        pausedCountInElapsed = 0
        pausedTimerElapsed = 0
        if !intervals.isEmpty {
            currentIntervalRemaining = intervals[0]
            totalRemaining = totalIntervalTime
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
            countInStartTime = Date()
            pausedCountInElapsed = 0
            pausedTimerElapsed = 0
        } else if isCountingIn {
            // Resuming during count-in - restore start time based on paused elapsed
            countInStartTime = Date().addingTimeInterval(-pausedCountInElapsed)
        } else {
            // Resuming during main timer - restore start time based on paused elapsed
            timerStartTime = Date().addingTimeInterval(-pausedTimerElapsed)
        }

        // Use higher frequency timer for more accurate timing
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
    }

    private var pausedCountInElapsed: TimeInterval = 0
    private var pausedTimerElapsed: TimeInterval = 0

    func pause() {
        // Save elapsed time so we can restore on resume
        if isCountingIn, let countInStartTime = countInStartTime {
            pausedCountInElapsed = Date().timeIntervalSince(countInStartTime)
        } else if let timerStartTime = timerStartTime {
            pausedTimerElapsed = Date().timeIntervalSince(timerStartTime)
        }

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
            guard let countInStartTime = countInStartTime else { return }
            let elapsed = Date().timeIntervalSince(countInStartTime)
            let elapsedSeconds = Int(elapsed)
            let newCountInRemaining = max(0, countInDuration - elapsedSeconds)

            // Only process each second once
            if elapsedSeconds != lastProcessedSecond {
                lastProcessedSecond = elapsedSeconds

                // Play beep on each second during count-in (except the last)
                if newCountInRemaining > 0 {
                    playCountInBeep()
                }
            }

            countInRemaining = newCountInRemaining

            if elapsed >= Double(countInDuration) {
                // Count-in finished, start the actual timer
                isCountingIn = false
                timerStartTime = Date()
                lastProcessedSecond = -1
                playTransitionBeep()  // Louder beep to signal start
            }
            return
        }

        // Main timer phase
        guard let timerStartTime = timerStartTime else { return }
        let elapsed = Date().timeIntervalSince(timerStartTime)
        let elapsedSeconds = Int(elapsed)

        // Calculate total remaining
        let newTotalRemaining = max(0, totalIntervalTime - elapsedSeconds)

        // Find which interval we're in and remaining time
        var accumulatedTime = 0
        var newIntervalIndex = 0
        var newIntervalRemaining = 0

        for (index, intervalDuration) in intervals.enumerated() {
            if elapsedSeconds < accumulatedTime + intervalDuration {
                newIntervalIndex = index
                newIntervalRemaining = (accumulatedTime + intervalDuration) - elapsedSeconds
                break
            }
            accumulatedTime += intervalDuration
            newIntervalIndex = index
        }

        // Detect interval transitions (only process each second once)
        if elapsedSeconds != lastProcessedSecond {
            let previousSecond = lastProcessedSecond
            lastProcessedSecond = elapsedSeconds

            // Check if we crossed into a new interval
            if previousSecond >= 0 {
                var prevAccumulated = 0
                var prevIntervalIndex = 0
                for (index, intervalDuration) in intervals.enumerated() {
                    if previousSecond < prevAccumulated + intervalDuration {
                        prevIntervalIndex = index
                        break
                    }
                    prevAccumulated += intervalDuration
                    prevIntervalIndex = index
                }

                if newIntervalIndex > prevIntervalIndex && newTotalRemaining > 0 {
                    playTransitionBeep()
                    lastCountdownBeepPlayed = 0  // Reset countdown tracking for new interval
                }
            }

            // Play countdown beeps (3, 2, 1) before interval ends (if not the last interval)
            if newIntervalRemaining <= 3 && newIntervalRemaining > 0 && newIntervalIndex < intervals.count - 1 {
                if newIntervalRemaining != lastCountdownBeepPlayed {
                    lastCountdownBeepPlayed = newIntervalRemaining
                    playCountInBeep()  // Reuse count-in beep for countdown
                }
            }
        }

        // Update published values
        totalRemaining = newTotalRemaining
        currentIntervalIndex = newIntervalIndex
        currentIntervalRemaining = newIntervalRemaining

        // Check for completion
        if elapsed >= Double(totalIntervalTime) {
            isComplete = true
            pause()
            playCompletionBeep()
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
