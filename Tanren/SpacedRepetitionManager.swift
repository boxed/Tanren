//
//  SpacedRepetitionManager.swift
//  Tanren
//

import Foundation
import SwiftData

/// Manages spaced repetition scheduling optimized for motor skills
struct SpacedRepetitionManager {

    /// Motor skill intervals are longer than verbal learning
    /// Initial: 1-2 days, then weekly, then monthly
    static let initialInterval = 1
    static let secondInterval = 3

    /// A ceiling on how far out a card can be pushed. Without one, multiplying
    /// by `easeFactor` on every success compounds without bound: cards have
    /// reached intervals of 10^16 days, which drops them out of the rotation
    /// for good and eventually overflows `Int`. Six months is already past the
    /// point where a motor skill needs checking on.
    static let maximumInterval = 180

    /// The ceiling that applies to one card: its own cap when it has one, but
    /// never more than the global maximum.
    static func intervalCeiling(for card: Card) -> Int {
        guard let cap = card.maxIntervalDays else { return maximumInterval }
        return min(max(cap, initialInterval), maximumInterval)
    }

    /// Brings a computed interval back into range, and copes with the absurd
    /// values already sitting in stores written before there was a ceiling.
    private static func clampInterval(_ days: Double, ceiling: Int) -> Int {
        guard days.isFinite else { return ceiling }
        return Int(min(max(days, Double(initialInterval)), Double(ceiling)))
    }

    /// Reviews are scheduled in whole days, so a card comes due at the start of
    /// a day rather than at whatever time it happened to be practiced. A daily
    /// card done tonight is then due first thing tomorrow, not tomorrow night.
    static func nextReviewDate(after date: Date, intervalDays: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: intervalDays, to: start) ?? start
    }

    /// Called after completing all three stages of a card review
    /// Updates the card's scheduling based on the challenge stage performance
    static func completeReview(card: Card, challengeSuccessful: Bool) {
        let now = Date()
        let ceiling = intervalCeiling(for: card)
        card.lastReviewDate = now
        card.reviewCount += 1

        if challengeSuccessful {
            // Good performance - increase interval
            if card.reviewCount == 1 {
                card.intervalDays = initialInterval
            } else if card.reviewCount == 2 {
                card.intervalDays = secondInterval
            } else {
                card.intervalDays = clampInterval(Double(card.intervalDays) * card.easeFactor, ceiling: ceiling)
            }
            card.easeFactor = min(2.5, card.easeFactor + 0.1)
        } else {
            // Struggled at challenge level - shorter interval
            card.intervalDays = clampInterval(Double(card.intervalDays) / 2, ceiling: ceiling)
            card.easeFactor = max(1.3, card.easeFactor - 0.1)
        }

        // Add 10-20% randomness to prevent clustering
        let randomFactor = 0.9 + Double.random(in: 0..<0.2)
        card.intervalDays = clampInterval(Double(card.intervalDays) * randomFactor, ceiling: ceiling)

        card.nextReviewDate = nextReviewDate(after: now, intervalDays: card.intervalDays)
    }

    /// Brings a card's schedule back under its ceiling, for when the ceiling
    /// was lowered after the card was scheduled (or never existed, for the
    /// runaway intervals of old stores). Rescheduled from the last review, so a
    /// well-learned card keeps its interval rather than being dumped back into
    /// today's session. Returns whether anything needed changing.
    @discardableResult
    static func enforceIntervalCeiling(on card: Card) -> Bool {
        let ceiling = intervalCeiling(for: card)
        guard card.intervalDays > ceiling else { return false }

        card.intervalDays = ceiling
        let anchor = card.lastReviewDate ?? Date()
        card.nextReviewDate = min(
            card.nextReviewDate,
            nextReviewDate(after: anchor, intervalDays: ceiling)
        )
        return true
    }

    /// Pulls back cards that a previously uncapped interval pushed past the
    /// horizon — without this they are never due again, so they would never be
    /// rescheduled and never come back. Idempotent: only touches cards that are
    /// actually out of range. Returns the names it repaired.
    @discardableResult
    static func repairRunawayIntervals(modelContext: ModelContext) -> [String] {
        let cards = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        let repaired = cards.filter { enforceIntervalCeiling(on: $0) }.map(\.name)

        if !repaired.isEmpty {
            try? modelContext.save()
        }
        return repaired
    }

    /// How many cards were already practiced today in this deck
    static func cardsPracticedToday(in deck: Deck) -> Int {
        deck.cards.filter { $0.wasPracticedToday }.count
    }

    /// Selects cards for practice from a deck
    /// Prioritizes due cards and weak spots, but includes some randomness
    static func selectCardsForPractice(from deck: Deck, maxCards: Int? = nil) -> [Card] {
        // Exclude suspended cards and cards already practiced today
        let allCards = deck.cards.filter(\.isEligibleForPractice)

        // Reduce max cards by how many were already done today
        let remainingQuota = max(0, (maxCards ?? deck.dailyCardLimit) - cardsPracticedToday(in: deck))
        guard remainingQuota > 0 else { return [] }

        // Separate due and not-due cards
        let dueCards = allCards.filter { $0.isDue }
        let notDueCards = allCards.filter { !$0.isDue }

        // Sort due cards by priority (lower score = higher priority)
        let sortedDueCards = dueCards.sorted { $0.priorityScore < $1.priorityScore }

        var selectedCards: [Card] = []

        // Take up to 80% from due cards
        let dueCount = min(sortedDueCards.count, Int(Double(remainingQuota) * 0.8))
        selectedCards.append(contentsOf: sortedDueCards.prefix(dueCount))

        // Fill remaining slots with random not-due cards (for exposure)
        let remainingSlots = remainingQuota - selectedCards.count
        if remainingSlots > 0 && !notDueCards.isEmpty {
            let randomNotDue = notDueCards.shuffled().prefix(remainingSlots)
            selectedCards.append(contentsOf: randomNotDue)
        }

        // If we still don't have enough, add more due cards
        if selectedCards.count < remainingQuota && sortedDueCards.count > dueCount {
            let additionalDue = sortedDueCards.dropFirst(dueCount).prefix(remainingQuota - selectedCards.count)
            selectedCards.append(contentsOf: additionalDue)
        }

        // Shuffle to interleave (contextual interference effect)
        return selectedCards.shuffled()
    }

    /// Everything due today across the given decks, most urgent first.
    ///
    /// Urgency is what a skipped day would cost: a card on a daily cycle loses a
    /// whole repetition per day missed, one on a five day cycle only a fifth of
    /// one. So shorter intervals come first, and cards on the same interval are
    /// in random order. Each deck's daily limit still applies to its own cards,
    /// and only due cards are included — no random exposure cards, unlike a
    /// single deck's session.
    static func selectDueCardsAcrossDecks(from decks: [Deck]) -> [Card] {
        let perDeck = decks.flatMap { deck -> [Card] in
            let remainingQuota = max(0, deck.dailyCardLimit - cardsPracticedToday(in: deck))
            let due = deck.cards.filter(\.isWaitingForReview)
            return Array(byUrgency(due).prefix(remainingQuota))
        }
        return byUrgency(perDeck)
    }

    /// Shortest interval first; ties broken randomly rather than by insertion
    /// order, so the same few cards don't always lead.
    private static func byUrgency(_ cards: [Card]) -> [Card] {
        cards
            .map { (card: $0, tiebreak: Double.random(in: 0..<1)) }
            .sorted { ($0.card.intervalDays, $0.tiebreak) < ($1.card.intervalDays, $1.tiebreak) }
            .map(\.card)
    }

    /// Gets the next card to practice, avoiding repetition
    static func nextCard(from cards: [Card], excluding lastCard: Card?) -> Card? {
        let available = cards.filter { $0.id != lastCard?.id }
        return available.first ?? cards.first
    }
}
