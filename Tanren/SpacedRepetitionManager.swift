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

    /// Brings a computed interval back into range, and copes with the absurd
    /// values already sitting in stores written before there was a ceiling.
    private static func clampInterval(_ days: Double) -> Int {
        guard days.isFinite else { return maximumInterval }
        return Int(min(max(days, Double(initialInterval)), Double(maximumInterval)))
    }

    /// Called after completing all three stages of a card review
    /// Updates the card's scheduling based on the challenge stage performance
    static func completeReview(card: Card, challengeSuccessful: Bool) {
        card.lastReviewDate = Date()
        card.reviewCount += 1

        if challengeSuccessful {
            // Good performance - increase interval
            if card.reviewCount == 1 {
                card.intervalDays = initialInterval
            } else if card.reviewCount == 2 {
                card.intervalDays = secondInterval
            } else {
                card.intervalDays = clampInterval(Double(card.intervalDays) * card.easeFactor)
            }
            card.easeFactor = min(2.5, card.easeFactor + 0.1)
        } else {
            // Struggled at challenge level - shorter interval
            card.intervalDays = clampInterval(Double(card.intervalDays) / 2)
            card.easeFactor = max(1.3, card.easeFactor - 0.1)
        }

        // Add 10-20% randomness to prevent clustering
        let randomFactor = 0.9 + Double.random(in: 0..<0.2)
        card.intervalDays = clampInterval(Double(card.intervalDays) * randomFactor)

        // Schedule next review
        card.nextReviewDate = Calendar.current.date(
            byAdding: .day,
            value: card.intervalDays,
            to: Date()
        ) ?? Date()
    }

    /// Pulls back cards that a previously uncapped interval pushed past the
    /// horizon — without this they are never due again, so they would never be
    /// rescheduled and never come back. Idempotent: only touches cards that are
    /// actually out of range. Returns the names it repaired.
    @discardableResult
    static func repairRunawayIntervals(modelContext: ModelContext) -> [String] {
        let cards = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        var repaired: [String] = []

        for card in cards where card.intervalDays > maximumInterval {
            card.intervalDays = maximumInterval
            // Reschedule from the last review, so a well-learned card keeps its
            // long interval rather than being dumped back into today's session.
            let anchor = card.lastReviewDate ?? Date()
            card.nextReviewDate = min(
                card.nextReviewDate,
                Calendar.current.date(byAdding: .day, value: maximumInterval, to: anchor) ?? Date()
            )
            repaired.append(card.name)
        }

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
    static func selectCardsForPractice(from deck: Deck, maxCards: Int = PracticePolicy.maxCardsPerDay) -> [Card] {
        // Exclude suspended cards and cards already practiced today
        let allCards = deck.cards.filter(\.isEligibleForPractice)

        // Reduce max cards by how many were already done today
        let remainingQuota = max(0, maxCards - cardsPracticedToday(in: deck))
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

    /// Gets the next card to practice, avoiding repetition
    static func nextCard(from cards: [Card], excluding lastCard: Card?) -> Card? {
        let available = cards.filter { $0.id != lastCard?.id }
        return available.first ?? cards.first
    }
}
