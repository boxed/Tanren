//
//  PracticeSnapshotWriter.swift
//  Tanren
//
//  Publishes the current practice state to the shared app group container so
//  the widget has something to draw, then nudges WidgetKit to redraw it.
//

import Foundation
import SwiftData
import WidgetKit

extension Card {
    /// Suspended cards and cards already practiced today are out of rotation.
    var isEligibleForPractice: Bool {
        !isSuspended && !wasPracticedToday
    }

    /// Waiting to be practiced right now.
    var isWaitingForReview: Bool {
        isEligibleForPractice && isDue
    }
}

extension Deck {
    /// Cards today's session still asks for: the due backlog, capped by what
    /// remains of the daily quota. The deck list and the widget both apply
    /// this cap, so the two never disagree about what "due" means.
    var dueCount: Int {
        let remainingQuota = PracticePolicy.maxCardsPerDay - SpacedRepetitionManager.cardsPracticedToday(in: self)
        return min(cards.filter(\.isWaitingForReview).count, max(0, remainingQuota))
    }
}

struct PracticeSnapshotWriter {

    /// Rebuilds the snapshot from the store and reloads the widget timelines.
    /// Cheap enough to call on any app lifecycle change.
    @MainActor
    static func refresh(modelContext: ModelContext) {
        let decks = (try? modelContext.fetch(FetchDescriptor<Deck>())) ?? []
        let published = decks.map(snapshot(of:))

        // Any link ids handed out above need to stick around for the deep link
        // to resolve later.
        if modelContext.hasChanges {
            try? modelContext.save()
        }

        // WidgetKit only grants so many reloads a day, and this runs on every
        // return to the deck list — so stay quiet when nothing has moved.
        guard PracticeSnapshotStore.load()?.decks != published else { return }

        PracticeSnapshotStore.save(PracticeSnapshot(generatedAt: Date(), decks: published))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func snapshot(of deck: Deck) -> DeckSnapshot {
        DeckSnapshot(
            id: DeckReference.token(for: deck),
            name: deck.name,
            cards: deck.cards.map { card in
                CardSnapshot(
                    name: card.name,
                    nextReviewDate: card.nextReviewDate,
                    lastReviewDate: card.lastReviewDate,
                    isSuspended: card.isSuspended
                )
            }
        )
    }
}

/// Turns a deck into a string a widget can carry in a URL, and back again.
/// The token is the deck's own identity, so renaming a deck doesn't break a
/// widget that's already on the home screen; the name travels alongside as a
/// fallback for decks that predate the identifier.
enum DeckReference {
    @MainActor
    static func token(for deck: Deck) -> String {
        if let existing = deck.linkID { return existing.uuidString }
        let assigned = UUID()
        deck.linkID = assigned
        return assigned.uuidString
    }

    /// Resolves a deep link back to a deck, by identity if possible and by name
    /// otherwise. A deleted deck simply doesn't resolve.
    @MainActor
    static func resolve(token: String?, name: String?, in modelContext: ModelContext) -> Deck? {
        let decks = (try? modelContext.fetch(FetchDescriptor<Deck>())) ?? []

        if let token,
           let id = UUID(uuidString: token),
           let match = decks.first(where: { $0.linkID == id }) {
            return match
        }

        if let name {
            return decks.first { $0.name == name }
        }

        return nil
    }
}
