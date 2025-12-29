//
//  TunerView.swift
//  Tanren
//

import SwiftUI

struct TunerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tuner = GuitarTunerEngine()

    private let previewMode: Bool
    private let previewNote: TunerNote?
    private let previewCents: Double

    init(previewMode: Bool = false, previewNote: TunerNote? = nil, previewCents: Double = 0) {
        self.previewMode = previewMode
        self.previewNote = previewNote
        self.previewCents = previewCents
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if previewMode || tuner.hasPermission {
                    tunerContentView
                } else {
                    permissionView
                }
            }
            .padding()
            .navigationTitle("Guitar Tuner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        tuner.stop()
                        dismiss()
                    }
                }
            }
            .task {
                if previewMode {
                    if let note = previewNote {
                        tuner.setPreviewData(note: note, cents: previewCents, frequency: note.frequency)
                    }
                } else {
                    await tuner.start()
                }
            }
            .onDisappear {
                tuner.stop()
            }
        }
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Microphone Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("The tuner needs microphone access to detect the pitch of your guitar strings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Grant Access") {
                Task {
                    _ = await tuner.requestPermission()
                    if tuner.hasPermission {
                        await tuner.start()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var tunerContentView: some View {
        VStack(spacing: 32) {
            // Guitar strings reference
            stringReferenceView

            Spacer()

            // Note display
            noteDisplayView
            
            Spacer()

            // Tuning gauge
            tuningGaugeView

            // Frequency display
            if tuner.detectedFrequency > 0 {
                Text(String(format: "%.1f Hz", tuner.detectedFrequency))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Signal level indicator
            signalLevelView
        }
    }

    private var stringReferenceView: some View {
        HStack(spacing: 12) {
            ForEach(GuitarTunerEngine.guitarStrings.reversed(), id: \.stringNumber) { string in
                VStack(spacing: 4) {
                    Text("\(string.stringNumber ?? 0)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(string.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isCurrentString(string) ? .blue : .primary)

                    Text(String(format: "%.0f", string.frequency))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isCurrentString(string) ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func isCurrentString(_ string: TunerNote) -> Bool {
        guard let detected = tuner.detectedNote else { return false }
        return detected.stringNumber == string.stringNumber
    }

    private var noteDisplayView: some View {
        VStack(spacing: 8) {
            if let note = tuner.detectedNote {
                HStack(alignment: .bottom, spacing: 2) {
                    Text(note.name)
                        .font(.system(size: 72, weight: .bold, design: .rounded))

                    Text("\(note.octave)")
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .offset(y: -8)
                }
                .foregroundStyle(tuner.isInTune ? .green : .primary)

                if let stringNum = note.stringNumber {
                    Text("String \(stringNum)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("--")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("Play a string")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tuningGaugeView: some View {
        VStack(spacing: 8) {
            // Gauge with needle
            ZStack(alignment: .bottom) {
                // Background arc
                TuningArc()
                    .stroke(
                        LinearGradient(
                            colors: [.red, .yellow, .green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 12
                    )
                    .frame(height: 60)

                // Center indicator
                Rectangle()
                    .fill(.green)
                    .frame(width: 3, height: 24)
                    .offset(y: 18)

                // Needle
                if tuner.detectedNote != nil {
                    TuningNeedle(cents: tuner.centsDeviation)
                        .animation(.spring(response: 0.3), value: tuner.centsDeviation)
                }
            }
            .frame(height: 100)
            .padding(.horizontal)
            .padding(.top, 20)

            // Cents display
            HStack {
                Text("-50")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if tuner.detectedNote != nil {
                    Text(centsText)
                        .font(.headline)
                        .foregroundStyle(tuner.isInTune ? .green : .primary)
                }

                Spacer()

                Text("+50")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private var centsText: String {
        let cents = Int(round(tuner.centsDeviation))
        if cents == 0 {
            return "In Tune"
        } else if cents > 0 {
            return "+\(cents) cents"
        } else {
            return "\(cents) cents"
        }
    }

    private var signalLevelView: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))

                    Rectangle()
                        .fill(signalColor)
                        .frame(width: geometry.size.width * CGFloat(min(tuner.signalLevel * 10, 1)))
                }
            }
            .frame(height: 8)
            .cornerRadius(4)

            Text("Signal Level")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var signalColor: Color {
        if tuner.signalLevel < 0.01 {
            return .gray
        } else if tuner.signalLevel < 0.1 {
            return .yellow
        } else {
            return .green
        }
    }
}

struct TuningArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = rect.width / 2
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        return path
    }
}

struct TuningNeedle: View {
    let cents: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let center = CGPoint(x: width / 2, y: geometry.size.height)

            // Clamp cents to -50...50 range
            let clampedCents = max(-50, min(50, cents))
            // Map cents to angle: -50 = 180 degrees, 0 = 90 degrees, 50 = 0 degrees
            let angle = 90 - (clampedCents / 50 * 90)

            Path { path in
                path.move(to: center)
                let needleLength = width / 2 - 20
                let endX = center.x + needleLength * cos(angle * .pi / 180)
                let endY = center.y - needleLength * sin(angle * .pi / 180)
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(.primary, lineWidth: 3)

            // Needle tip indicator
            Circle()
                .fill(.primary)
                .frame(width: 12, height: 12)
                .position(
                    x: center.x + CGFloat(width / 2 - 20) * cos(angle * .pi / 180),
                    y: center.y - CGFloat(width / 2 - 20) * sin(angle * .pi / 180)
                )
        }
    }
}

#Preview("Tuner") {
    TunerView(previewMode: true)
}

#Preview("Playing A String") {
    TunerView(
        previewMode: true,
        previewNote: GuitarTunerEngine.guitarStrings[1], // A2, string 5
        previewCents: -5
    )
}

#Preview("Permission Required") {
    TunerView()
}
