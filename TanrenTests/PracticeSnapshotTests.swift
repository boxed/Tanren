//
//  PracticeSnapshotTests.swift
//  TanrenTests
//

import Foundation
import SwiftData
import Testing
@testable import Tanren

private let calendar = Calendar(identifier: .gregorian)

/// A fixed "now" so the tests don't drift with the wall clock.
private let now = Date(timeIntervalSince1970: 1_700_000_000)

private func card(
    _ name: String,
    due: TimeInterval,
    lastReview: TimeInterval? = nil,
    suspended: Bool = false
) -> CardSnapshot {
    CardSnapshot(
        name: name,
        nextReviewDate: now.addingTimeInterval(due),
        lastReviewDate: lastReview.map { now.addingTimeInterval($0) },
        isSuspended: suspended
    )
}

private let day: TimeInterval = 86_400

struct CardSnapshotTests {

    @Test func overdueCardIsDue() {
        #expect(card("C ↔ G", due: -day).isDue(at: now, calendar: calendar))
    }

    @Test func futureCardIsNotDue() {
        #expect(!card("C ↔ G", due: day).isDue(at: now, calendar: calendar))
    }

    @Test func suspendedCardIsNeverDue() {
        let suspended = card("C ↔ G", due: -day, suspended: true)
        #expect(!suspended.isDue(at: now, calendar: calendar))
        #expect(!suspended.isEligible(at: now, calendar: calendar))
    }

    @Test func cardPracticedTodayIsOutOfRotation() {
        let practiced = card("C ↔ G", due: -day, lastReview: -60)
        #expect(!practiced.isDue(at: now, calendar: calendar))
    }

    @Test func cardPracticedYesterdayIsBackInRotation() {
        let practiced = card("C ↔ G", due: -day, lastReview: -day)
        #expect(practiced.isDue(at: now, calendar: calendar))
    }

    @Test func newCardHasNoReviewHistory() {
        #expect(card("C ↔ G", due: 0).isNew)
        #expect(!card("C ↔ G", due: 0, lastReview: -day).isNew)
    }
}

struct DeckSnapshotTests {

    private let deck = DeckSnapshot(id: "deck-1", name: "Chords", cards: [
        card("C ↔ G", due: -2 * day),
        card("D ↔ A", due: -day),
        card("Em ↔ Am", due: day),                  // not due yet
        card("F ↔ C", due: -day, suspended: true),  // suspended
        card("G ↔ D", due: -day, lastReview: -60),  // done today
    ])

    @Test func dueCountIgnoresSuspendedFutureAndDoneToday() {
        #expect(deck.dueCount(at: now, calendar: calendar) == 2)
    }

    @Test func dueCardsAreOrderedByHowLongTheyHaveWaited() {
        let names = deck.dueCards(at: now, calendar: calendar).map(\.name)
        #expect(names == ["C ↔ G", "D ↔ A"])
    }

    @Test func practicedCountCountsOnlyToday() {
        #expect(deck.practicedCount(onDayOf: now, calendar: calendar) == 1)
        #expect(deck.practicedCount(onDayOf: now.addingTimeInterval(day), calendar: calendar) == 0)
    }

    @Test func cardsBecomeDueAsTimePasses() {
        let later = now.addingTimeInterval(2 * day)
        // "Em ↔ Am" has come due, and "G ↔ D" is no longer counted as done today.
        #expect(deck.dueCount(at: later, calendar: calendar) == 4)
    }

    @Test func dueCountIsCappedAtTheDailyQuota() {
        let backlog = DeckSnapshot(id: "deck-2", name: "Backlog", cards:
            (0..<21).map { card("Card \($0)", due: -day) }
        )
        #expect(backlog.dueCount(at: now, calendar: calendar) == PracticePolicy.maxCardsPerDay)
    }

    @Test func todaysPracticeEatsIntoTheQuota() {
        let cards = (0..<21).map { card("Card \($0)", due: -day) }
            + (0..<4).map { card("Done \($0)", due: -day, lastReview: -60) }
        let deck = DeckSnapshot(id: "deck-3", name: "Backlog", cards: cards)
        #expect(deck.dueCount(at: now, calendar: calendar) == 6)
    }

    @Test func aFinishedSessionShowsNothingDueDespiteTheBacklog() {
        let cards = (0..<21).map { card("Card \($0)", due: -day) }
            + (0..<PracticePolicy.maxCardsPerDay).map { card("Done \($0)", due: -day, lastReview: -60) }
        let deck = DeckSnapshot(id: "deck-4", name: "Backlog", cards: cards)
        #expect(deck.dueCount(at: now, calendar: calendar) == 0)
        // The quota comes back at midnight.
        #expect(deck.dueCount(at: now.addingTimeInterval(day), calendar: calendar) == PracticePolicy.maxCardsPerDay)
    }
}

struct PracticeSnapshotTests {

    private let snapshot = PracticeSnapshot(
        generatedAt: now,
        decks: [
            DeckSnapshot(id: "quiet", name: "Scales", cards: [card("A minor", due: -day)]),
            DeckSnapshot(id: "busy", name: "Chords", cards: [
                card("C ↔ G", due: -day),
                card("D ↔ A", due: -day),
            ]),
            DeckSnapshot(id: "empty", name: "Riffs", cards: [card("Smoke", due: day)]),
        ]
    )

    @Test func totalDueCountSumsAcrossDecks() {
        #expect(snapshot.totalDueCount(at: now, calendar: calendar) == 3)
    }

    @Test func decksWithDueCardsAreBusiestFirstAndSkipEmptyOnes() {
        let names = snapshot.decksWithDueCards(at: now, calendar: calendar).map(\.name)
        #expect(names == ["Chords", "Scales"])
    }

    @Test func refreshDatesCoverFutureReviewsAndMidnight() {
        let dates = snapshot.refreshDates(after: now, calendar: calendar)

        #expect(dates.contains(now.addingTimeInterval(day)))
        #expect(dates.allSatisfy { $0 > now })
        #expect(dates == dates.sorted())
        // Three midnights plus the one future review.
        #expect(dates.count == 4)
    }

    @Test func refreshDatesIgnorePastReviews() {
        let dates = snapshot.refreshDates(after: now, calendar: calendar)
        #expect(!dates.contains(now.addingTimeInterval(-day)))
    }

    @Test func refreshDatesRespectTheLimit() {
        #expect(snapshot.refreshDates(after: now, limit: 2, calendar: calendar).count == 2)
    }

    @Test func emptySnapshotReadsAsNeverWritten() {
        #expect(PracticeSnapshot.empty.generatedAt == .distantPast)
        #expect(PracticeSnapshot.empty.totalDueCount(at: now, calendar: calendar) == 0)
    }

    @Test func snapshotSurvivesAJSONRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(PracticeSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.version == PracticeSnapshot.currentVersion)
    }
}

struct PracticeDeepLinkTests {

    @Test func deckLinkRoundTrips() {
        let link = PracticeDeepLink.deck(id: "abc==", name: "Chord Changes")
        #expect(PracticeDeepLink(url: link.url) == link)
    }

    @Test func deckListLinkRoundTrips() {
        #expect(PracticeDeepLink(url: PracticeDeepLink.deckList.url) == .deckList)
    }

    @Test func deckSnapshotLinkCarriesIdentityAndName() {
        let deck = DeckSnapshot(id: "token", name: "Scales", cards: [])
        #expect(PracticeDeepLink(url: deck.deepLink) == .deck(id: "token", name: "Scales"))
    }

    @Test func foreignSchemesAreRejected() {
        #expect(PracticeDeepLink(url: URL(string: "https://example.com/deck")!) == nil)
    }
}

/// A throwaway store for one test. The container has to be *held* for as long
/// as the test uses it — `try ModelContainer(...).mainContext` releases the
/// container immediately and the next insert takes the whole process down with
/// a SwiftData trap.
@MainActor
private struct TestStore {
    let container: ModelContainer

    var context: ModelContext { container.mainContext }

    init() throws {
        let schema = Schema([Deck.self, Card.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}

@MainActor
@Suite(.serialized)
struct PracticeSnapshotWriterTests {

    @Test func deckDueCountMatchesTheSnapshotDefinition() throws {
        let store = try TestStore()
        let context = store.context
        let deck = Deck(name: "Chords")
        context.insert(deck)

        let due = Card(chord1: "C", chord2: "G", deck: deck)
        let later = Card(chord1: "D", chord2: "A", deck: deck)
        later.nextReviewDate = Date().addingTimeInterval(day)
        let suspended = Card(chord1: "F", chord2: "C", deck: deck)
        suspended.isSuspended = true
        let doneToday = Card(chord1: "G", chord2: "D", deck: deck)
        doneToday.lastReviewDate = Date()

        for card in [due, later, suspended, doneToday] {
            context.insert(card)
            deck.cards.append(card)
        }

        #expect(deck.dueCount == 1)
        #expect(due.isWaitingForReview)
        #expect(!later.isWaitingForReview)
        #expect(!suspended.isEligibleForPractice)
        #expect(!doneToday.isEligibleForPractice)
    }

    @Test func deckDueCountIsCappedByTheDailyQuota() throws {
        let store = try TestStore()
        let context = store.context
        let deck = Deck(name: "Chords")
        context.insert(deck)

        for i in 0..<(PracticePolicy.maxCardsPerDay + 2) {
            let card = Card(chord1: "C\(i)", chord2: "G", deck: deck)
            context.insert(card)
            deck.cards.append(card)
        }
        #expect(deck.dueCount == PracticePolicy.maxCardsPerDay)

        // Practicing uses up the quota even while the backlog stays larger.
        deck.cards[0].lastReviewDate = Date()
        deck.cards[1].lastReviewDate = Date()
        #expect(deck.dueCount == PracticePolicy.maxCardsPerDay - 2)
    }

    @Test func deckReferenceResolvesByIdentityEvenAfterARename() throws {
        let store = try TestStore()
        let context = store.context
        let deck = Deck(name: "Chords")
        context.insert(deck)
        try context.save()

        let token = DeckReference.token(for: deck)
        #expect(UUID(uuidString: token) != nil)

        deck.name = "Chord Changes"
        try context.save()

        let resolved = DeckReference.resolve(token: token, name: "Chords", in: context)
        #expect(resolved === deck)
    }

    @Test func deckReferenceHandsOutTheSameTokenEveryTime() throws {
        let store = try TestStore()
        let context = store.context
        let deck = Deck(name: "Chords")
        context.insert(deck)

        #expect(DeckReference.token(for: deck) == DeckReference.token(for: deck))
    }

    @Test func deckReferenceFallsBackToTheName() throws {
        let store = try TestStore()
        let context = store.context
        let deck = Deck(name: "Scales")
        context.insert(deck)
        try context.save()

        // A deck that predates link ids, or a token from a deleted deck.
        #expect(DeckReference.resolve(token: nil, name: "Scales", in: context) === deck)
        #expect(DeckReference.resolve(token: UUID().uuidString, name: "Scales", in: context) === deck)
        #expect(DeckReference.resolve(token: "not-a-uuid", name: "Scales", in: context) === deck)
        #expect(DeckReference.resolve(token: nil, name: "Nope", in: context) == nil)
        #expect(DeckReference.resolve(token: nil, name: nil, in: context) == nil)
    }

    @Test func refreshAssignsLinkIDsToEveryDeck() throws {
        let store = try TestStore()
        let context = store.context
        let deck = Deck(name: "Chords")
        context.insert(deck)
        let card = Card(chord1: "C", chord2: "G", deck: deck)
        context.insert(card)
        deck.cards.append(card)

        PracticeSnapshotWriter.refresh(modelContext: context)

        // Every deck now carries a link id, whether or not the shared container
        // was reachable to write to.
        #expect(deck.linkID != nil)
    }
}

/// Regression cover for the crash that stopped the app launching: a review date
/// pushed ~10^13 years out by a runaway interval. `JSONEncoder.iso8601` *traps*
/// on such a date rather than throwing, and the snapshot is written at startup.
struct AbsurdDateTests {

    private let absurd = Date(timeIntervalSinceReferenceDate: 1.2486769798855988e+21)

    @Test func absurdDatesAreClampedOnTheWayIn() {
        let card = CardSnapshot(name: "Grip strength", nextReviewDate: absurd, lastReviewDate: absurd)
        #expect(card.nextReviewDate == Date.plausibleRange.upperBound)
        #expect(card.lastReviewDate == Date.plausibleRange.upperBound)
    }

    @Test func ordinaryDatesArePassedThroughUntouched() {
        let card = CardSnapshot(name: "C ↔ G", nextReviewDate: now, lastReviewDate: now)
        #expect(card.nextReviewDate == now)
        #expect(card.lastReviewDate == now)
    }

    @Test func datesBeforeTheRangeAreClampedUp() {
        #expect(Date.distantPast.clampedToPlausibleRange() == Date.plausibleRange.lowerBound)
    }

    @Test func aSnapshotHoldingAnAbsurdDateStillEncodes() throws {
        let snapshot = PracticeSnapshot(
            generatedAt: now,
            decks: [DeckSnapshot(id: "d", name: "Strength", cards: [
                CardSnapshot(name: "Grip strength", nextReviewDate: absurd),
            ])]
        )

        // Would have trapped, not thrown, before the fix.
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PracticeSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test func aClampedCardIsNotDue() {
        let card = CardSnapshot(name: "Grip strength", nextReviewDate: absurd)
        #expect(!card.isDue(at: now, calendar: calendar))
    }
}

@MainActor
@Suite(.serialized)
struct RunawayIntervalTests {

    private func card(intervalDays: Int, lastReview: Date?, in context: ModelContext) -> Card {
        let deck = Deck(name: "Strength")
        context.insert(deck)
        let card = Card(chord1: "Grip strength", chord2: "", deck: deck)
        context.insert(card)
        deck.cards.append(card)
        card.intervalDays = intervalDays
        card.lastReviewDate = lastReview
        card.nextReviewDate = Date(timeIntervalSinceReferenceDate: 1.2486769798855988e+21)
        return card
    }

    @Test func reviewsNeverPushACardPastTheCeiling() throws {
        let store = try TestStore()
        let deck = Deck(name: "Strength")
        store.context.insert(deck)
        let card = Card(chord1: "Grip strength", chord2: "", deck: deck)
        store.context.insert(card)

        // 60 straight successes used to compound to ~10^16 days.
        for _ in 0..<60 {
            card.lastReviewDate = nil
            SpacedRepetitionManager.completeReview(card: card, challengeSuccessful: true)
        }

        #expect(card.intervalDays <= SpacedRepetitionManager.maximumInterval)
        #expect(card.intervalDays >= 1)
        #expect(Date.plausibleRange.contains(card.nextReviewDate))
    }

    @Test func aFailedReviewFromARunawayIntervalComesBackInRange() throws {
        let store = try TestStore()
        let card = card(intervalDays: 14_452_279_859_777_780, lastReview: nil, in: store.context)

        SpacedRepetitionManager.completeReview(card: card, challengeSuccessful: false)

        #expect(card.intervalDays <= SpacedRepetitionManager.maximumInterval)
    }

    @Test func repairPullsBackCardsPastTheHorizon() throws {
        let store = try TestStore()
        let lastReview = Date().addingTimeInterval(-200 * 86_400)
        let runaway = card(intervalDays: 14_452_279_859_777_780, lastReview: lastReview, in: store.context)

        let repaired = SpacedRepetitionManager.repairRunawayIntervals(modelContext: store.context)

        #expect(repaired == ["Grip strength"])
        #expect(runaway.intervalDays == SpacedRepetitionManager.maximumInterval)
        #expect(Date.plausibleRange.contains(runaway.nextReviewDate))
        // Last reviewed 200 days ago with a 180 day ceiling, so it is due again.
        #expect(runaway.isDue)
    }

    @Test func repairLeavesHealthyCardsAlone() throws {
        let store = try TestStore()
        let healthy = card(intervalDays: 30, lastReview: Date(), in: store.context)
        let scheduled = Date().addingTimeInterval(30 * 86_400)
        healthy.nextReviewDate = scheduled

        #expect(SpacedRepetitionManager.repairRunawayIntervals(modelContext: store.context).isEmpty)
        #expect(healthy.intervalDays == 30)
        #expect(healthy.nextReviewDate == scheduled)
    }

    @Test func repairIsIdempotent() throws {
        let store = try TestStore()
        _ = card(intervalDays: 77_745, lastReview: Date(), in: store.context)

        #expect(SpacedRepetitionManager.repairRunawayIntervals(modelContext: store.context).count == 1)
        #expect(SpacedRepetitionManager.repairRunawayIntervals(modelContext: store.context).isEmpty)
    }
}
