//
//  MetronomeEngine.swift
//  Tanren
//

import AVFoundation
import Combine

@MainActor
class MetronomeEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var bpm: Int = 60 {
        didSet {
            if isPlaying {
                // Restart with new tempo
                stop()
                start()
            }
        }
    }
    @Published var currentBeat: Int = 0
    @Published var beatsPerMeasure: Int = 4

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var clickBuffer: AVAudioPCMBuffer?
    private var quietClickBuffer: AVAudioPCMBuffer?
    private var timer: Timer?

    // Timing based on elapsed time to prevent drift
    private var startTime: Date?
    private var lastPlayedBeat: Int = -1

    private let sampleRate: Double = 44100
    private let clickDuration: Double = 0.05 // 50ms click

    init() {
        setupAudio()
    }

    private func setupAudio() {
        // Configure audio session early to avoid lag on first play
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

        // Generate click sound buffers
        clickBuffer = generateClickBuffer(format: format, volume: 1.0)
        quietClickBuffer = generateClickBuffer(format: format, volume: 0.5)

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }

        // Warm up the audio pipeline with a silent buffer
        if let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) {
            silentBuffer.frameLength = 1
            silentBuffer.floatChannelData?[0][0] = 0
            playerNode.scheduleBuffer(silentBuffer, at: nil, options: [], completionHandler: nil)
            playerNode.play()
            playerNode.stop()
        }
    }

    private func generateClickBuffer(format: AVAudioFormat, volume: Float) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * clickDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        // Generate a woody tick sound using filtered noise with fast decay
        // This mimics the sound of a mechanical metronome or wood block
        for frame in 0..<Int(frameCount) {
            let t = Float(frame) / Float(sampleRate)

            // Very fast exponential decay for a sharp transient
            let decay = exp(-t * 200)

            // Mix of noise and a low "thock" frequency for woody character
            let noise = Float.random(in: -1...1)
            let thock = sin(2.0 * .pi * 80 * t) // Low frequency thump

            // Combine: mostly the initial noise transient with a bit of low thump
            var sample = (noise * 0.7 + thock * 0.3) * decay

            // High-pass filter effect: reduce low frequencies after initial hit
            if frame > 0 {
                let hipass = 0.85 as Float
                sample = sample - hipass * channelData[frame - 1] * 0.1
            }

            channelData[frame] = sample * 0.6 * volume
        }

        return buffer
    }

    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        currentBeat = 0
        lastPlayedBeat = -1
        startTime = Date()
        scheduleBeats()
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        playerNode?.stop()
        currentBeat = 0
        startTime = nil
        lastPlayedBeat = -1
    }

    func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    func increaseBPM() {
        bpm = min(300, bpm + 10)
    }

    func decreaseBPM() {
        bpm = max(20, bpm - 10)
    }

    func setBPM(_ newBPM: Int) {
        bpm = max(20, min(300, newBPM))
    }

    private func scheduleBeats() {
        // Use a high-frequency timer to check if we should play a beat
        // This prevents drift by calculating beat position from elapsed time
        timer = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkAndPlayBeat()
            }
        }

        // Play first beat immediately
        lastPlayedBeat = 0
        currentBeat = 1
        playClick()
    }

    private func checkAndPlayBeat() {
        guard isPlaying, let startTime = startTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let beatInterval = 60.0 / Double(bpm)
        let currentBeatNumber = Int(elapsed / beatInterval)

        // Only play if we've moved to a new beat
        if currentBeatNumber > lastPlayedBeat {
            lastPlayedBeat = currentBeatNumber
            currentBeat = (currentBeatNumber % beatsPerMeasure) + 1
            playClick()
        }
    }

    private func playClick() {
        guard let playerNode = playerNode, let clickBuffer = clickBuffer else { return }

        // At high BPM (200+), play every 4th beat at full volume, others at half volume
        let buffer: AVAudioPCMBuffer
        if bpm >= 200 && currentBeat != 1 {
            buffer = quietClickBuffer ?? clickBuffer
        } else {
            buffer = clickBuffer
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func cleanup() {
        stop()
        audioEngine?.stop()
    }
}
