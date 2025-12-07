//
//  PracticeView.swift
//  Tanren
//

import SwiftUI
import SwiftData
import UIKit

struct PracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let deck: Deck
    let startingCard: Card?

    @StateObject private var metronome = MetronomeEngine()
    @State private var practiceCards: [Card] = []
    @State private var currentCardIndex = 0
    @State private var currentStage: PracticeStage = .comfortable
    @State private var sessionComplete = false

    init(deck: Deck, startingCard: Card? = nil) {
        self.deck = deck
        self.startingCard = startingCard
    }

    var currentCard: Card? {
        guard currentCardIndex < practiceCards.count else { return nil }
        return practiceCards[currentCardIndex]
    }

    var progress: Double {
        guard !practiceCards.isEmpty else { return 0 }
        let cardProgress = Double(currentCardIndex) / Double(practiceCards.count)
        let stageProgress = Double(currentStage.rawValue) / 3.0 / Double(practiceCards.count)
        return cardProgress + stageProgress
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: progress)
                    .tint(.blue)

                if sessionComplete {
                    sessionCompleteView
                } else if let card = currentCard {
                    practiceContentView(card: card)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        metronome.stop()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(currentCardIndex + 1)/\(practiceCards.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                // Keep screen on during practice
                UIApplication.shared.isIdleTimerDisabled = true

                if let startingCard = startingCard {
                    practiceCards = [startingCard]
                } else {
                    practiceCards = SpacedRepetitionManager.selectCardsForPractice(from: deck)
                }
                if let card = currentCard {
                    metronome.setBPM(card.startingBPM(for: .comfortable))
                }
            }
            .onDisappear {
                // Allow screen to turn off again
                UIApplication.shared.isIdleTimerDisabled = false
                metronome.stop()
            }
        }
    }

    private func practiceContentView(card: Card) -> some View {
        VStack(spacing: 16) {
            // Card display - horizontal layout
            HStack(spacing: 12) {
                Text(card.chord1)
                    .font(.system(size: 48, weight: .bold))

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)

                Text(card.chord2)
                    .font(.system(size: 48, weight: .bold))
            }
            .padding(.top, 8)

            // Stage indicator
            stageIndicatorView

            // Current BPM levels for this card
            bpmLevelsView(card: card)

            Spacer()

            // Metronome section
            metronomeView

            Spacer()

            // Stage action button
            stageActionView(card: card)
                .padding()
        }
    }

    private var stageIndicatorView: some View {
        HStack(spacing: 4) {
            ForEach(PracticeStage.allCases, id: \.rawValue) { stage in
                VStack(spacing: 2) {
                    Circle()
                        .fill(stageColor(stage))
                        .frame(width: 12, height: 12)
                    Text(stage.title)
                        .font(.caption2)
                        .foregroundStyle(stage == currentStage ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    private func stageColor(_ stage: PracticeStage) -> Color {
        if stage.rawValue < currentStage.rawValue {
            return .green // Completed
        } else if stage == currentStage {
            switch stage {
            case .comfortable: return .green
            case .stretch: return .yellow
            case .challenge: return .red
            }
        } else {
            return .gray.opacity(0.3) // Not yet
        }
    }

    private func bpmLevelsView(card: Card) -> some View {
        Group {
            if card.comfortableBPM != nil || card.stretchBPM != nil || card.challengeBPM != nil {
                HStack(spacing: 16) {
                    if let bpm = card.comfortableBPM {
                        VStack {
                            Text("Comfortable")
                                .font(.caption2)
                            Text("\(bpm)")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                    if let bpm = card.stretchBPM {
                        VStack {
                            Text("Stretch")
                                .font(.caption2)
                            Text("\(bpm)")
                                .font(.subheadline)
                                .foregroundStyle(.yellow)
                        }
                    }
                    if let bpm = card.challengeBPM {
                        VStack {
                            Text("Challenge")
                                .font(.caption2)
                            Text("\(bpm)")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    private var metronomeView: some View {
        VStack(spacing: 12) {
            // Beat indicator
            HStack(spacing: 6) {
                ForEach(1...metronome.beatsPerMeasure, id: \.self) { beat in
                    Circle()
                        .fill(beat == metronome.currentBeat ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 16, height: 16)
                        .animation(.easeInOut(duration: 0.1), value: metronome.currentBeat)
                }
            }

            // BPM display and controls with play button
            HStack(spacing: 20) {
                Button(action: { metronome.decreaseBPM() }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                }

                VStack(spacing: 2) {
                    Text("\(metronome.bpm)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80)

                Button(action: { metronome.increaseBPM() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                }
            }
            Button(action: { metronome.toggle() }) {
                Image(systemName: metronome.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(metronome.isPlaying ? .red : .green)
                    .transaction { $0.animation = nil }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
    }

    private func stageActionView(card: Card) -> some View {
        VStack(spacing: 12) {
            Text(currentStage.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { completeStage(card: card) }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done with \(currentStage.title)")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(stageColor(currentStage))
                .foregroundStyle(.white)
                .cornerRadius(12)
                .font(.headline)
            }
        }
    }

    private func completeStage(card: Card) {
        metronome.stop()

        // Save the BPM for this stage
        card.setBPM(metronome.bpm, for: currentStage)

        // Move to next stage or next card
        if let nextStage = PracticeStage(rawValue: currentStage.rawValue + 1) {
            // Move to next stage
            currentStage = nextStage
            metronome.setBPM(card.startingBPM(for: nextStage))
        } else {
            // Completed all stages - finish this card's review
            SpacedRepetitionManager.completeReview(card: card, challengeSuccessful: true)

            // Move to next card
            currentCardIndex += 1
            currentStage = .comfortable

            if currentCardIndex >= practiceCards.count {
                sessionComplete = true
            } else if let nextCard = currentCard {
                metronome.setBPM(nextCard.startingBPM(for: .comfortable))
            }
        }

        try? modelContext.save()
    }

    private var sessionCompleteView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Session Complete!")
                .font(.title)
                .fontWeight(.bold)

            Text("You practiced \(practiceCards.count) cards")
                .foregroundStyle(.secondary)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No cards to practice")
                .font(.title2)

            Text("Add some cards to this deck first")
                .foregroundStyle(.secondary)

            Button("Go Back") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    PracticeView(deck: {
        let deck = Deck(name: "Chords")
        deck.cards.append(Card(chord1: "C", chord2: "D", deck: deck))
        deck.cards.append(Card(chord1: "G", chord2: "Am", deck: deck))
        return deck
    }())
    .modelContainer(for: [Deck.self, Card.self], inMemory: true)
}
