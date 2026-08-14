//
//  TunerView.swift
//  Tanren
//

import SwiftUI

struct TunerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tuner: TunerEngine

    init(tuner: TunerEngine? = nil) {
        _tuner = State(initialValue: tuner ?? TunerEngine())
    }

    var body: some View {
        NavigationStack {
            TunerScreen(tuner: tuner)
                .navigationTitle("Tuner")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
                .task {
                    tuner.resetProgress()
                    await tuner.start()
                }
                .onDisappear { tuner.stop() }
        }
    }
}

/// The tuner itself, without navigation chrome.
struct TunerScreen: View {
    let tuner: TunerEngine

    var body: some View {
        ZStack {
            ambientGlow
            content
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tuner.access {
        case .denied:
            permissionView(denied: true)
        case .undetermined:
            permissionView(denied: false)
        case .granted:
            meterView
        }
    }

    private var meterView: some View {
        VStack(spacing: 0) {
            if let message = tuner.failureMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }

            // Note and meter float together in the space above the strings.
            VStack(spacing: 36) {
                noteDisplay
                    .opacity(tuner.isStale ? 0.4 : 1)

                VStack(spacing: 12) {
                    centsReadout
                    CentsMeter(cents: tuner.reading?.cents,
                               tolerance: TunerEngine.inTuneTolerance,
                               color: tuningColor)
                        .opacity(tuner.isStale ? 0.4 : 1)
                    guidance
                    frequencyLine
                    levelMeter
                }
            }
            .frame(maxHeight: .infinity)

            stringPicker
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.25), value: tuner.isStale)
    }

    /// A wash of the current tuning colour, readable out of the corner of the
    /// eye while looking at the fretboard.
    private var ambientGlow: some View {
        RadialGradient(colors: [tuningColor.opacity(tuner.isStale ? 0.04 : 0.18), .clear],
                       center: .init(x: 0.5, y: 0.32),
                       startRadius: 0,
                       endRadius: 320)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.35), value: tuningColor)
        .animation(.easeOut(duration: 0.35), value: tuner.isStale)
    }

    private var noteDisplay: some View {
        VStack(spacing: 2) {
            ZStack {
                if let reading = tuner.reading {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(reading.noteName)
                            .font(.system(size: 104, weight: .bold, design: .rounded))
                            .foregroundStyle(tuningColor)
                            .contentTransition(.numericText())

                        Text("\(reading.octave)")
                            .font(.system(size: 34, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: "tuningfork")
                        .font(.system(size: 66, weight: .light))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(height: 112)
            .animation(.easeOut(duration: 0.2), value: tuner.reading?.targetMidi)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var subtitle: String {
        guard let reading = tuner.reading else { return "Play a string" }
        if let string = reading.string {
            return "\(ordinal(string.number)) string"
        }
        return "Not a guitar string"
    }

    private var centsReadout: some View {
        Text(centsText)
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tuner.isStale ? Color.secondary : tuningColor)
            .opacity(tuner.reading == nil ? 0 : 1)
            .contentTransition(.numericText(value: tuner.reading?.cents ?? 0))
            .animation(.easeOut(duration: 0.15), value: tuner.reading?.cents)
    }

    private var centsText: String {
        guard let cents = tuner.reading?.cents else { return "0¢" }
        let rounded = Int(cents.rounded())
        if rounded == 0 { return "0¢" }
        return "\(rounded > 0 ? "+" : "−")\(abs(rounded))¢"
    }

    private var guidance: some View {
        HStack(spacing: 6) {
            if let reading = tuner.reading, !tuner.isStale {
                if reading.isInTune {
                    Image(systemName: "checkmark.circle.fill")
                    Text("In tune")
                } else if reading.cents < 0 {
                    Image(systemName: "arrow.up")
                    Text("Tighten")
                } else {
                    Image(systemName: "arrow.down")
                    Text("Loosen")
                }
            } else {
                Image(systemName: "waveform")
                Text("Listening")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tuner.isStale ? Color.secondary : tuningColor)
        .frame(height: 20)
    }

    private var frequencyLine: some View {
        Text(frequencyText)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .opacity(tuner.reading == nil ? 0 : 1)
            .frame(height: 14)
    }

    private var frequencyText: String {
        guard let reading = tuner.reading else { return " " }
        return String(format: "%.1f Hz → %.1f Hz", reading.frequency, reading.targetFrequency)
    }

    // MARK: Strings

    private var stringPicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(GuitarString.standardTuning) { string in
                    stringButton(string)
                }
            }

            Text(tuner.targetString == nil
                 ? "Tap a string to tune only to it"
                 : "Locked to \(tuner.targetString?.displayName ?? "") — tap again to unlock")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func stringButton(_ string: GuitarString) -> some View {
        let isDetected = tuner.reading?.string == string && !tuner.isStale
        let isLocked = tuner.targetString == string
        let isTuned = tuner.tunedStrings.contains(string.number)

        return Button {
            tuner.targetString = isLocked ? nil : string
        } label: {
            VStack(spacing: 1) {
                Text(string.noteName)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text("\(string.number)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDetected ? tuningColor.opacity(0.22)
                          : isTuned ? Color.green.opacity(0.12)
                          : Color(.systemGray6))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isLocked ? Color.accentColor : isDetected ? tuningColor : .clear,
                                  lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if isTuned {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isDetected)
        .animation(.easeOut(duration: 0.2), value: isTuned)
        .accessibilityLabel("\(ordinal(string.number)) string, \(string.displayName)")
        .accessibilityValue(isTuned ? "in tune" : "not tuned")
        .accessibilityAddTraits(isLocked ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Level

    /// Shows the microphone is hearing something, and warns when the input is
    /// hot enough to clip.
    private var levelMeter: some View {
        HStack(spacing: 5) {
            Image(systemName: "mic.fill")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(width: 80)
                Capsule()
                    .fill(tuner.level > 0.92 ? Color.orange : Color.secondary.opacity(0.6))
                    .frame(width: max(2, 80 * tuner.level))
            }
            .frame(width: 80, height: 2.5)
        }
        .animation(.easeOut(duration: 0.1), value: tuner.level)
        .accessibilityHidden(true)
    }

    // MARK: Permission

    private func permissionView(denied: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: denied ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text(denied ? "Microphone Access Denied" : "Microphone Access Needed")
                .font(.title3.weight(.semibold))

            Text(denied
                 ? "Enable microphone access in Settings to use the tuner."
                 : "The tuner listens to your guitar to work out how far each string is off pitch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(denied ? "Open Settings" : "Allow Microphone") {
                if denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    Task { await tuner.start() }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    // MARK: Helpers

    private var tuningColor: Color {
        guard let reading = tuner.reading, !tuner.isStale else { return .secondary }
        if reading.isInTune { return .green }
        if reading.isClose { return .orange }
        return .red
    }

    private var accessibilityDescription: String {
        guard let reading = tuner.reading else { return "No pitch detected" }
        let cents = Int(reading.cents.rounded())
        if reading.isInTune { return "\(reading.noteName)\(reading.octave), in tune" }
        return "\(reading.noteName)\(reading.octave), \(abs(cents)) cents \(cents < 0 ? "flat" : "sharp")"
    }

    private func ordinal(_ number: Int) -> String {
        switch number {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(number)th"
        }
    }
}

// MARK: - Cents meter

/// A linear scale from −50 to +50 cents with a needle. Linear reads more
/// precisely than a dial at this size, and the tick spacing makes "three cents
/// flat" look different from "twenty cents flat" at a glance.
private struct CentsMeter: View {
    let cents: Double?
    let tolerance: Double
    let color: Color

    private let range = 50.0
    private let needleHeight = 78.0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let center = width / 2
            let halfSpan = width / 2 - 10
            let clamped = min(range, max(-range, cents ?? 0))
            // Stop just short of the ends so the off-scale arrow has room.
            let position = center + min(range * 0.92, max(-range * 0.92, clamped)) / range * halfSpan

            ZStack {
                ticks(width: width, height: height, center: center, halfSpan: halfSpan)

                // The in-tune window.
                Capsule()
                    .fill(color.opacity(0.16))
                    .frame(width: max(6, tolerance / range * halfSpan * 2), height: needleHeight)
                    .position(x: center, y: height / 2)

                if cents != nil {
                    Capsule()
                        .fill(color)
                        .frame(width: 7, height: needleHeight)
                        .shadow(color: color.opacity(0.7),
                                radius: abs(clamped) <= tolerance ? 12 : 0)
                        .position(x: position, y: height / 2)
                        .animation(.interpolatingSpring(stiffness: 130, damping: 15), value: clamped)

                    if let cents, abs(cents) > range {
                        Image(systemName: cents < 0 ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(color)
                            .position(x: cents < 0 ? 5 : width - 5, y: height / 2)
                    }
                }
            }
        }
        .frame(height: needleHeight + 26)
        .overlay(alignment: .bottom) { scaleLabels }
        .accessibilityHidden(true)
    }

    private func ticks(width: Double, height: Double, center: Double, halfSpan: Double) -> some View {
        Canvas { context, size in
            let midY = size.height / 2
            for step in -10...10 {
                let value = Double(step) * 5
                let x = center + value / range * halfSpan
                let isMajor = step % 5 == 0
                let isCenter = step == 0
                let tickHeight = isCenter ? needleHeight : isMajor ? 30.0 : 16.0
                let line = Path { path in
                    path.move(to: CGPoint(x: x, y: midY - tickHeight / 2))
                    path.addLine(to: CGPoint(x: x, y: midY + tickHeight / 2))
                }
                context.stroke(line,
                               with: .color(isCenter ? .primary : .secondary.opacity(isMajor ? 0.55 : 0.28)),
                               style: StrokeStyle(lineWidth: isCenter ? 2 : 1, lineCap: .round))
            }
        }
    }

    private var scaleLabels: some View {
        HStack {
            Text("−50")
            Spacer()
            Text("−25")
            Spacer()
            Text("0")
            Spacer()
            Text("+25")
            Spacer()
            Text("+50")
        }
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Previews

#Preview("In tune") {
    TunerView(tuner: .simulated(frequency: 110.02, tunedStrings: [6]))
}

#Preview("Flat low E") {
    TunerView(tuner: .simulated(frequency: 80.9, tunedStrings: [1, 2]))
}

#Preview("Sharp, locked to D") {
    TunerView(tuner: .simulated(frequency: 148.9,
                                targetString: GuitarString.standardTuning[2],
                                tunedStrings: [6, 5]))
}

#Preview("Way off") {
    TunerView(tuner: .simulated(frequency: 172.0))
}

#Preview("Silence") {
    TunerView(tuner: .simulatedSilence())
}

#Preview("Denied") {
    TunerView(tuner: .simulatedDenied())
}
