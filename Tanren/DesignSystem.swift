//
//  DesignSystem.swift
//  Tanren
//
//  Small shared vocabulary of colours, badges and surfaces so the list, deck
//  and practice screens read as one app.
//

import SwiftUI

// MARK: - Stage styling

extension PracticeStage {
    /// The colour this stage is always drawn in: cool for warm-up, hot for the
    /// edge of your ability. Orange rather than yellow for the middle stage —
    /// yellow text is unreadable on a light tinted fill.
    var tint: Color {
        switch self {
        case .comfortable: return .green
        case .stretch: return .orange
        case .challenge: return .red
        }
    }

    var symbolName: String {
        switch self {
        case .comfortable: return "leaf.fill"
        case .stretch: return "flame.fill"
        case .challenge: return "bolt.fill"
        }
    }
}

// MARK: - Surfaces

extension View {
    /// A raised panel used to group a self-contained control cluster.
    func panel(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Badges

/// A compact capsule for counts and states. Tinted fill rather than a solid
/// colour so several can sit side by side without shouting.
struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    init(_ text: String, systemImage: String? = nil, tint: Color = .secondary) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.15)))
        .foregroundStyle(tint)
    }
}

/// The three stage tempos of a card as a rising ramp, or a "New" marker when
/// nothing has been established yet.
struct BPMRamp: View {
    let card: Card

    private var established: [(stage: PracticeStage, bpm: Int)] {
        PracticeStage.allCases.compactMap { stage in
            card.bpm(for: stage).map { (stage, $0) }
        }
    }

    var body: some View {
        if established.isEmpty {
            Pill("New", tint: .accentColor)
        } else {
            HStack(spacing: 4) {
                ForEach(established, id: \.stage.rawValue) { entry in
                    Text("\(entry.bpm)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(entry.stage.tint.opacity(0.16))
                        )
                        .foregroundStyle(entry.stage.tint)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                established
                    .map { "\($0.stage.title) \($0.bpm) BPM" }
                    .joined(separator: ", ")
            )
        }
    }
}

/// Thin ring used in the deck list to show how much of a deck has been started.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3.5
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Pills") {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            Pill("12 due", systemImage: "clock.fill", tint: .orange)
            Pill("New", tint: .accentColor)
            Pill("Suspended", systemImage: "pause.fill")
        }

        BPMRamp(card: {
            let card = Card(chord1: "C", chord2: "G")
            card.comfortableBPM = 72
            card.stretchBPM = 84
            card.challengeBPM = 96
            return card
        }())

        BPMRamp(card: Card(chord1: "C", chord2: "G"))

        ProgressRing(progress: 0.4)
            .frame(width: 34, height: 34)
    }
    .padding()
}
