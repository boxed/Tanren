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
    @StateObject private var intervalTimer = IntervalTimerEngine()
    @State private var practiceCards: [Card] = []
    @State private var currentCardIndex = 0
    @State private var currentStage: PracticeStage = .comfortable
    @State private var sessionComplete = false
    @State private var showBuryConfirmation = false
    @State private var showSuspendConfirmation = false
    @State private var showTuner = false
    @State private var stageCompletedForCurrentCard = false

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
                        // Record review if any stage was completed for current card
                        if stageCompletedForCurrentCard, let card = currentCard {
                            SpacedRepetitionManager.completeReview(card: card, challengeSuccessful: currentStage == .challenge)
                            try? modelContext.save()
                        }
                        metronome.stop()
                        intervalTimer.stop()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Text("\(currentCardIndex + 1)/\(practiceCards.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Menu {
                            Button("Bury card") {
                                showBuryConfirmation = true
                            }
                            Button("Suspend card", role: .destructive) {
                                showSuspendConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Bury this card?", isPresented: $showBuryConfirmation, titleVisibility: .visible) {
                Button("Bury", role: .destructive) {
                    buryCurrentCard()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This card will be moved to the end of the practice session.")
            }
            .confirmationDialog("Suspend this card?", isPresented: $showSuspendConfirmation, titleVisibility: .visible) {
                Button("Suspend", role: .destructive) {
                    suspendCurrentCard()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This card will be excluded from all future practice sessions until unsuspended.")
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
                    configureIntervalTimer(for: card)
                }
            }
            .onDisappear {
                // Allow screen to turn off again
                UIApplication.shared.isIdleTimerDisabled = false
                metronome.stop()
                intervalTimer.stop()
            }
        }
    }

    private func practiceContentView(card: Card) -> some View {
        VStack(spacing: 16) {
                // Card display - horizontal layout
                HStack(spacing: 12) {
                Text(card.chord1)
                    .font(.system(size: 48, weight: .bold))

                if !card.chord2.isEmpty {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)

                    Text(card.chord2)
                        .font(.system(size: 48, weight: .bold))
                }
            }
            .padding(.top, 8)

            // Card image
            if deck.imagesEnabled, let imageData = card.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
            }

            // Card URL
            if deck.urlEnabled, let urlString = card.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "link")
                        Text(url.host ?? urlString)
                    }
                    .font(.subheadline)
                }
            }

            // Interval Timer
            if deck.intervalTimersEnabled && !card.intervalTimerList.isEmpty {
                intervalTimerView(card: card)
            }

            if deck.metronomeEnabled {
                // Stage indicator with BPM levels
                stageIndicatorView(card: card)
            }

            Spacer()

            if deck.metronomeEnabled {
                // Metronome section
                metronomeView
            }

            Spacer()

            // Stage action button
            stageActionView(card: card)
                .padding()
        }
    }

    private func buryCurrentCard() {
        guard currentCardIndex < practiceCards.count else { return }

        metronome.stop()
        intervalTimer.stop()

        // Remove current card and append to end
        let card = practiceCards.remove(at: currentCardIndex)
        practiceCards.append(card)

        // Reset to comfortable stage for the new current card
        currentStage = .comfortable
        stageCompletedForCurrentCard = false

        if currentCardIndex >= practiceCards.count {
            sessionComplete = true
        } else if let nextCard = currentCard {
            metronome.setBPM(nextCard.startingBPM(for: .comfortable))
            configureIntervalTimer(for: nextCard)
        }
    }

    private func suspendCurrentCard() {
        guard currentCardIndex < practiceCards.count else { return }

        metronome.stop()
        intervalTimer.stop()

        // Mark the card as suspended
        let card = practiceCards[currentCardIndex]
        card.isSuspended = true

        // Remove from practice session
        practiceCards.remove(at: currentCardIndex)

        // Reset to comfortable stage for the new current card
        currentStage = .comfortable
        stageCompletedForCurrentCard = false

        if currentCardIndex >= practiceCards.count {
            sessionComplete = true
        } else if let nextCard = currentCard {
            metronome.setBPM(nextCard.startingBPM(for: .comfortable))
            configureIntervalTimer(for: nextCard)
        }

        try? modelContext.save()
    }

    private func stageIndicatorView(card: Card) -> some View {
        HStack(spacing: 4) {
            ForEach(PracticeStage.allCases, id: \.rawValue) { stage in
                Button(action: { jumpToStage(stage) }) {
                    VStack(spacing: 2) {
                        Circle()
                            .fill(stageColor(stage))
                            .frame(width: 12, height: 12)
                        Text(stage.title)
                            .font(.caption2)
                            .foregroundStyle(stage == currentStage ? .primary : .secondary)
                        if let bpm = card.bpm(for: stage) {
                            Text("\(bpm)")
                                .font(.caption)
                                .foregroundStyle(stageColor(stage))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private func jumpToStage(_ stage: PracticeStage) {
        guard let card = currentCard else { return }
        currentStage = stage
        metronome.setBPM(card.startingBPM(for: stage))
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
                        .lineLimit(1)
                        .fixedSize()
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button(action: { metronome.increaseBPM() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                }
            }
            HStack(spacing: 24) {
                Button(action: { metronome.toggle() }) {
                    Image(systemName: metronome.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(metronome.isPlaying ? .red : .green)
                        .transaction { $0.animation = nil }
                }

                Button(action: {
                    // The tuner needs the audio session for recording.
                    metronome.stop()
                    showTuner = true
                }) {
                    Image(systemName: "tuningfork")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Circle())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .sheet(isPresented: $showTuner, onDismiss: {
            metronome.reclaimAudioSession()
            intervalTimer.reclaimAudioSession()
        }) {
            TunerView()
        }
    }

    private func intervalTimerView(card: Card) -> some View {
        VStack(spacing: 16) {
            // Count-in or Total time display
            if intervalTimer.isCountingIn {
                Text("Get Ready...")
                    .font(.headline)
                    .foregroundStyle(.orange)
            } else {
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                    Text("Total: \(IntervalTimerEngine.formatTime(intervalTimer.totalRemaining))")
                        .font(.headline)
                        .monospacedDigit()
                }
            }

            // Current countdown (count-in or interval)
            if !intervalTimer.isComplete {
                if intervalTimer.isCountingIn {
                    Text("\(intervalTimer.countInRemaining)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                } else {
                    Text("\(intervalTimer.currentIntervalRemaining)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(intervalTimer.isRunning ? .primary : .secondary)
                }
            }

            // Interval list with position marker (dimmed during count-in)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(card.intervalTimerList.enumerated()), id: \.offset) { index, seconds in
                            VStack(spacing: 4) {
                                if index == intervalTimer.currentIntervalIndex && !intervalTimer.isComplete && !intervalTimer.isCountingIn {
                                    Image(systemName: "arrowtriangle.down.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                } else {
                                    Color.clear.frame(height: 10)
                                }

                                Text("\(seconds)s")
                                    .font(.subheadline)
                                    .fontWeight(index == intervalTimer.currentIntervalIndex && !intervalTimer.isCountingIn ? .bold : .regular)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        index < intervalTimer.currentIntervalIndex ? Color.green.opacity(0.3) :
                                        index == intervalTimer.currentIntervalIndex && !intervalTimer.isCountingIn ? Color.blue.opacity(0.3) :
                                        Color(.systemGray5)
                                    )
                                    .foregroundStyle(
                                        index < intervalTimer.currentIntervalIndex ? .green :
                                        index == intervalTimer.currentIntervalIndex && !intervalTimer.isCountingIn ? .blue :
                                        .secondary
                                    )
                                    .cornerRadius(8)
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal)
                }
                .opacity(intervalTimer.isCountingIn ? 0.5 : 1.0)
                .onChange(of: intervalTimer.currentIntervalIndex) { _, newIndex in
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            // Start/Pause button
            Button(action: { intervalTimer.toggle() }) {
                HStack {
                    Image(systemName: intervalTimer.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                    Text(intervalTimer.isRunning ? "Pause" : (intervalTimer.isComplete ? "Complete" : "Start"))
                        .font(.headline)
                }
                .foregroundStyle(intervalTimer.isComplete ? .green : (intervalTimer.isRunning ? .orange : .blue))
            }
            .disabled(intervalTimer.isComplete)

            // Reset button (shown when paused or complete)
            if !intervalTimer.isRunning || intervalTimer.isComplete {
                Button("Reset Timer") {
                    intervalTimer.reset()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func configureIntervalTimer(for card: Card) {
        let intervals = card.intervalTimerList
        intervalTimer.configure(intervals: intervals)
    }

    private func stageActionView(card: Card) -> some View {
        VStack(spacing: 12) {
            if deck.metronomeEnabled {
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
            } else {
                Button(action: { completeCardWithoutMetronome(card: card) }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Done")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .font(.headline)
                }
            }
        }
    }

    private func completeCardWithoutMetronome(card: Card) {
        SpacedRepetitionManager.completeReview(card: card, challengeSuccessful: true)
        intervalTimer.stop()

        currentCardIndex += 1

        if currentCardIndex >= practiceCards.count {
            sessionComplete = true
        } else if let nextCard = currentCard {
            configureIntervalTimer(for: nextCard)
        }

        try? modelContext.save()
    }

    private func completeStage(card: Card) {
        // Save the BPM for this stage
        let completedBPM = metronome.bpm
        card.setBPM(completedBPM, for: currentStage)
        stageCompletedForCurrentCard = true

        // Move to next stage or next card
        if let nextStage = PracticeStage(rawValue: currentStage.rawValue + 1) {
            // Move to next stage - at least 10 BPM higher than completed stage
            currentStage = nextStage
            let minimumBPM = completedBPM + 10
            let nextBPM = max(card.startingBPM(for: nextStage), minimumBPM)
            metronome.setBPM(nextBPM)
        } else {
            // Completed all stages - finish this card's review
            SpacedRepetitionManager.completeReview(card: card, challengeSuccessful: true)
            intervalTimer.stop()

            // Move to next card
            currentCardIndex += 1
            currentStage = .comfortable
            stageCompletedForCurrentCard = false

            if currentCardIndex >= practiceCards.count {
                metronome.stop()
                sessionComplete = true
            } else if let nextCard = currentCard {
                metronome.setBPM(nextCard.startingBPM(for: .comfortable))
                configureIntervalTimer(for: nextCard)
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
