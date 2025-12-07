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
                card.intervalDays = Int(Double(card.intervalDays) * card.easeFactor)
            }
            card.easeFactor = min(2.5, card.easeFactor + 0.1)
        } else {
            // Struggled at challenge level - shorter interval
            card.intervalDays = max(initialInterval, card.intervalDays / 2)
            card.easeFactor = max(1.3, card.easeFactor - 0.1)
        }

        // Add 10-20% randomness to prevent clustering
        let randomFactor = 0.9 + Double.random(in: 0..<0.2)
        card.intervalDays = max(1, Int(Double(card.intervalDays) * randomFactor))

        // Schedule next review
        card.nextReviewDate = Calendar.current.date(
            byAdding: .day,
            value: card.intervalDays,
            to: Date()
        ) ?? Date()
    }

    /// Selects cards for practice from a deck
    /// Prioritizes due cards and weak spots, but includes some randomness
    static func selectCardsForPractice(from deck: Deck, maxCards: Int = 10) -> [Card] {
        let allCards = deck.cards

        // Separate due and not-due cards
        let dueCards = allCards.filter { $0.isDue }
        let notDueCards = allCards.filter { !$0.isDue }

        // Sort due cards by priority (lower score = higher priority)
        let sortedDueCards = dueCards.sorted { $0.priorityScore < $1.priorityScore }

        var selectedCards: [Card] = []

        // Take up to 80% from due cards
        let dueCount = min(sortedDueCards.count, Int(Double(maxCards) * 0.8))
        selectedCards.append(contentsOf: sortedDueCards.prefix(dueCount))

        // Fill remaining slots with random not-due cards (for exposure)
        let remainingSlots = maxCards - selectedCards.count
        if remainingSlots > 0 && !notDueCards.isEmpty {
            let randomNotDue = notDueCards.shuffled().prefix(remainingSlots)
            selectedCards.append(contentsOf: randomNotDue)
        }

        // If we still don't have enough, add more due cards
        if selectedCards.count < maxCards && sortedDueCards.count > dueCount {
            let additionalDue = sortedDueCards.dropFirst(dueCount).prefix(maxCards - selectedCards.count)
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
