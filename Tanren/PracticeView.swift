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
                // Session progress
                ProgressView(value: progress)
                    .tint(.accentColor)
                    .scaleEffect(x: 1, y: 0.6, anchor: .top)
                    .animation(.easeOut(duration: 0.25), value: progress)

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
                        if !practiceCards.isEmpty && !sessionComplete {
                            Text("\(currentCardIndex + 1)/\(practiceCards.count)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

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
        VStack(spacing: 0) {
            // Reference material scrolls; the controls below stay put so the
            // metronome is always under your thumb. The content is centred while
            // it fits and only starts scrolling once it doesn't.
            GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    cardHeader(card: card)

                    if deck.metronomeEnabled {
                        stageIndicatorView(card: card)
                    }

                    if deck.imagesEnabled, let imageData = card.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                    }

                    if deck.urlEnabled, let urlString = card.url, let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack(spacing: 5) {
                                Image(systemName: "link")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(url.host ?? urlString)
                                    .lineLimit(1)
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }

                    if deck.intervalTimersEnabled && !card.intervalTimerList.isEmpty {
                        intervalTimerView(card: card)
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: 14) {
                if deck.metronomeEnabled {
                    metronomeView
                }

                stageActionView(card: card)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    /// The card itself — sized to fit rather than clipped, since sides can hold
    /// anything from "C" to a whole phrase. Short names get to be huge; long
    /// ones step down so they don't push the controls off screen.
    private func cardHeader(card: Card) -> some View {
        let length = card.chord1.count + card.chord2.count
        let size: CGFloat = switch length {
        case 0...6: 64
        case 7...12: 52
        case 13...24: 38
        default: 28
        }

        return HStack(spacing: 14) {
            Text(card.chord1)
                .frame(maxWidth: card.chord2.isEmpty ? .infinity : nil)

            if !card.chord2.isEmpty {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: max(16, size * 0.4), weight: .medium))
                    .foregroundStyle(.tertiary)

                Text(card.chord2)
            }
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .lineLimit(2)
        .minimumScaleFactor(0.4)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.2), value: card.name)
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
        HStack(spacing: 8) {
            ForEach(PracticeStage.allCases, id: \.rawValue) { stage in
                Button(action: { jumpToStage(stage) }) {
                    stageChip(stage, card: card)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.2), value: currentStage)
    }

    private func stageChip(_ stage: PracticeStage, card: Card) -> some View {
        let isCurrent = stage == currentStage
        let isDone = stage.rawValue < currentStage.rawValue
        let tint = stageColor(stage)

        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: isDone ? "checkmark" : stage.symbolName)
                    .font(.system(size: 10, weight: .bold))
                Text(stage.shortTitle)
                    .font(.caption.weight(isCurrent ? .bold : .medium))
            }
            .foregroundStyle(isCurrent || isDone ? tint : Color.secondary)

            Text(card.bpm(for: stage).map(String.init) ?? "—")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isCurrent || isDone ? tint : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? tint.opacity(0.16) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isCurrent ? tint : .clear, lineWidth: 2)
        )
        .accessibilityLabel("\(stage.title) stage")
        .accessibilityValue(card.bpm(for: stage).map { "\($0) BPM" } ?? "not established")
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
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
            return stage.tint
        } else {
            return .gray.opacity(0.3) // Not yet
        }
    }


    private var metronomeView: some View {
        VStack(spacing: 14) {
            HStack {
                panelLabel("Metronome")
                Spacer()
                beatIndicator
            }

            // Tempo, transport and tuner on one row: everything you touch while
            // playing sits within thumb reach of each other.
            HStack(spacing: 12) {
                bpmStepButton("minus", action: metronome.decreaseBPM)

                VStack(spacing: 0) {
                    Text("\(metronome.bpm)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(metronome.bpm)))
                        .animation(.easeOut(duration: 0.15), value: metronome.bpm)
                        .lineLimit(1)
                        .fixedSize()
                    Text("BPM")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                bpmStepButton("plus", action: metronome.increaseBPM)
            }

            // Round transport, so it never reads as the same kind of control as
            // the wide "done with this stage" button below the panel.
            ZStack {
                Button(action: { metronome.toggle() }) {
                    Image(systemName: metronome.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            Circle().fill(metronome.isPlaying ? Color.red : Color.green)
                        )
                        .transaction { $0.animation = nil }
                }
                .accessibilityLabel(metronome.isPlaying ? "Stop metronome" : "Start metronome")

                Button(action: {
                    // The tuner needs the audio session for recording.
                    metronome.stop()
                    showTuner = true
                }) {
                    Image(systemName: "tuningfork")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color.accentColor.opacity(0.14)))
                }
                .accessibilityLabel("Tuner")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .panel()
        .sheet(isPresented: $showTuner, onDismiss: {
            metronome.reclaimAudioSession()
            intervalTimer.reclaimAudioSession()
        }) {
            TunerView()
        }
    }

    /// Names a control cluster, so the two round green transports on screen are
    /// never ambiguous.
    private func panelLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(.tertiary)
    }

    /// The downbeat is drawn larger so you can find beat one at a glance.
    private var beatIndicator: some View {
        HStack(spacing: 10) {
            ForEach(1...metronome.beatsPerMeasure, id: \.self) { beat in
                let isActive = beat == metronome.currentBeat && metronome.isPlaying
                let size: CGFloat = beat == 1 ? 15 : 11

                Circle()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: size, height: size)
                    .scaleEffect(isActive ? 1.35 : 1)
                    .animation(.easeOut(duration: 0.08), value: metronome.currentBeat)
                    .animation(.easeOut(duration: 0.15), value: metronome.isPlaying)
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    private func bpmStepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
        }
        .accessibilityLabel(symbol == "plus" ? "Increase tempo" : "Decrease tempo")
    }

    private func intervalTimerView(card: Card) -> some View {
        VStack(spacing: 10) {
            HStack {
                panelLabel("Interval Timer")

                Spacer()

                if intervalTimer.isCountingIn {
                    Text("Get ready")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .font(.system(size: 11, weight: .semibold))
                        Text(IntervalTimerEngine.formatTime(intervalTimer.totalRemaining))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text("left")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Current countdown (count-in or interval)
            if !intervalTimer.isComplete {
                if intervalTimer.isCountingIn {
                    Text("\(intervalTimer.countInRemaining)")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                } else {
                    Text("\(intervalTimer.currentIntervalRemaining)")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
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
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tint)
                                } else {
                                    Color.clear.frame(height: 10)
                                }

                                Text("\(seconds)s")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .fontWeight(index == intervalTimer.currentIntervalIndex && !intervalTimer.isCountingIn ? .bold : .regular)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(
                                                index < intervalTimer.currentIntervalIndex ? Color.green.opacity(0.18) :
                                                index == intervalTimer.currentIntervalIndex && !intervalTimer.isCountingIn ? Color.accentColor.opacity(0.18) :
                                                Color(.tertiarySystemFill)
                                            )
                                    )
                                    .foregroundStyle(
                                        index < intervalTimer.currentIntervalIndex ? Color.green :
                                        index == intervalTimer.currentIntervalIndex && !intervalTimer.isCountingIn ? Color.accentColor :
                                        Color.secondary
                                    )
                            }
                            .id(index)
                        }
                    }
                }
                .opacity(intervalTimer.isCountingIn ? 0.5 : 1.0)
                .onChange(of: intervalTimer.currentIntervalIndex) { _, newIndex in
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            // Same control language as the metronome: round transport in the
            // middle, round secondary action off to the side.
            ZStack {
                Button(action: { intervalTimer.toggle() }) {
                    Image(systemName: intervalTimer.isComplete
                          ? "checkmark"
                          : (intervalTimer.isRunning ? "pause.fill" : "play.fill"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            Circle().fill(intervalTimer.isComplete
                                          ? Color.green
                                          : (intervalTimer.isRunning ? Color.orange : Color.green))
                        )
                }
                .disabled(intervalTimer.isComplete)
                .accessibilityLabel(intervalTimer.isRunning ? "Pause timer" : "Start timer")

                Button(action: { intervalTimer.reset() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .accessibilityLabel("Reset timer")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .panel()
        .padding(.horizontal, 16)
    }

    private func configureIntervalTimer(for card: Card) {
        let intervals = card.intervalTimerList
        intervalTimer.configure(intervals: intervals)
    }

    private func stageActionView(card: Card) -> some View {
        VStack(spacing: 8) {
            if deck.metronomeEnabled {
                Text(currentStage.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .animation(.easeOut(duration: 0.2), value: currentStage)

                completeButton(
                    title: currentStage == .challenge ? "Finish Card" : "Done with \(currentStage.title)"
                ) {
                    completeStage(card: card)
                }
            } else {
                completeButton(title: "Done") {
                    completeCardWithoutMetronome(card: card)
                }
            }
        }
    }

    /// Always the accent colour: green/red belong to the metronome transport, so
    /// tinting this by stage made two unrelated buttons look like a pair.
    private func completeButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor)
            )
            .foregroundStyle(.white)
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
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.14))
                    .frame(width: 116, height: 116)
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.green)
            }

            Text("Session Complete")
                .font(.system(.title, design: .rounded, weight: .bold))
                .padding(.top, 24)

            Text("\(practiceCards.count) card\(practiceCards.count == 1 ? "" : "s") practiced")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Nothing to Practice", systemImage: "music.note.list")
        } description: {
            Text("Every card in this deck is done for today, or the deck is still empty.")
        } actions: {
            Button("Go Back") { dismiss() }
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
