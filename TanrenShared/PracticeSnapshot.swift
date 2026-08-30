//
//  PracticeSnapshot.swift
//  TanrenShared
//
//  The slice of practice state that lives outside the app. The app owns the
//  SwiftData store; extensions read this JSON snapshot instead, so a widget
//  never has to open — or migrate — the store itself.
//
//  Compiled into both the app and the widget extension.
//

import Foundation

// MARK: - Shared container

/// Where the app and its extensions meet on disk.
enum SharedContainer {
    static let appGroup = "group.net.kodare.Tanren"

    /// The deep link scheme the widget uses to hand a deck back to the app.
    static let urlScheme = "tanren"

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("practice-snapshot.json", isDirectory: false)
    }
}

// MARK: - Practice policy

/// A practice session asks for at most so many cards per deck per day.
/// Every "due" number shown to the user is capped by it: a backlog larger
/// than a day's session can clear reads as un-finishable pile-up, so the UI
/// only ever asks for what today's session can actually absorb. Each deck can
/// set its own limit; this is what applies when it hasn't.
enum PracticePolicy {
    static let defaultMaxCardsPerDay = 10
}

// MARK: - Deep links

/// The links the widget hands back to the app. Constructing and parsing live
/// together so the two ends cannot drift apart.
enum PracticeDeepLink: Equatable {
    case deckList
    case deck(id: String?, name: String?)

    var url: URL {
        var components = URLComponents()
        components.scheme = SharedContainer.urlScheme

        switch self {
        case .deckList:
            components.host = "decks"
        case let .deck(id, name):
            components.host = "deck"
            components.queryItems = [
                id.map { URLQueryItem(name: "id", value: $0) },
                name.map { URLQueryItem(name: "name", value: $0) },
            ].compactMap { $0 }
        }

        // Every case above produces a valid URL; the fallback only keeps the
        // type non-optional.
        return components.url ?? URL(string: "\(SharedContainer.urlScheme)://decks")!
    }

    init?(url: URL) {
        guard url.scheme == SharedContainer.urlScheme else { return nil }

        guard url.host == "deck" else {
            self = .deckList
            return
        }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        self = .deck(
            id: query.first { $0.name == "id" }?.value,
            name: query.first { $0.name == "name" }?.value
        )
    }
}

// MARK: - Dates

extension Date {
    /// Anything outside this is not a date anybody meant. Runaway
    /// spaced-repetition intervals have produced review dates ~10^13 years out
    /// (see `SpacedRepetitionManager.maximumInterval`), and such a date is not
    /// merely useless — some date formatters trap on it instead of failing.
    static let plausibleRange =
        Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 7_258_118_400)  // 1970...2200

    func clampedToPlausibleRange() -> Date {
        min(max(self, Date.plausibleRange.lowerBound), Date.plausibleRange.upperBound)
    }
}

// MARK: - Snapshot

/// One card, reduced to what is needed to tell whether it is waiting to be
/// practiced. Dates rather than pre-computed flags, so the widget can work out
/// its own answer hours after the app last ran.
struct CardSnapshot: Codable, Hashable, Sendable {
    var name: String
    var nextReviewDate: Date
    var lastReviewDate: Date?
    var isSuspended: Bool

    init(name: String, nextReviewDate: Date, lastReviewDate: Date? = nil, isSuspended: Bool = false) {
        self.name = name
        self.nextReviewDate = nextReviewDate.clampedToPlausibleRange()
        self.lastReviewDate = lastReviewDate?.clampedToPlausibleRange()
        self.isSuspended = isSuspended
    }

    var isNew: Bool { lastReviewDate == nil }

    func wasPracticed(onDayOf date: Date, calendar: Calendar = .current) -> Bool {
        guard let lastReviewDate else { return false }
        return calendar.isDate(lastReviewDate, inSameDayAs: date)
    }

    /// Suspended cards and cards already done today are out of rotation.
    func isEligible(at date: Date, calendar: Calendar = .current) -> Bool {
        !isSuspended && !wasPracticed(onDayOf: date, calendar: calendar)
    }

    func isDue(at date: Date, calendar: Calendar = .current) -> Bool {
        isEligible(at: date, calendar: calendar) && nextReviewDate <= date
    }
}

struct DeckSnapshot: Codable, Hashable, Sendable, Identifiable {
    /// The deck's stable link identifier, so a tap can reopen it in the app.
    var id: String
    var name: String
    /// The deck's own daily limit; nil means the default applies. Optional so
    /// snapshots written before the field existed still decode.
    var maxCardsPerDay: Int?
    var cards: [CardSnapshot]

    init(id: String, name: String, maxCardsPerDay: Int? = nil, cards: [CardSnapshot]) {
        self.id = id
        self.name = name
        self.maxCardsPerDay = maxCardsPerDay
        self.cards = cards
    }

    var dailyLimit: Int { maxCardsPerDay ?? PracticePolicy.defaultMaxCardsPerDay }

    /// Cards waiting to be practiced, the longest-overdue one first.
    func dueCards(at date: Date, calendar: Calendar = .current) -> [CardSnapshot] {
        cards
            .filter { $0.isDue(at: date, calendar: calendar) }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    /// How many cards today's session still asks for: the due backlog, capped
    /// by what remains of the daily quota. Reaches zero once the day's session
    /// is done, however large the backlog behind it.
    func dueCount(at date: Date, calendar: Calendar = .current) -> Int {
        let remainingQuota = dailyLimit - practicedCount(onDayOf: date, calendar: calendar)
        let backlog = cards.filter { $0.isDue(at: date, calendar: calendar) }.count
        return min(backlog, max(0, remainingQuota))
    }

    func practicedCount(onDayOf date: Date, calendar: Calendar = .current) -> Int {
        cards.filter { $0.wasPracticed(onDayOf: date, calendar: calendar) }.count
    }

    /// Opens this deck in the app.
    var deepLink: URL { PracticeDeepLink.deck(id: id, name: name).url }
}

struct PracticeSnapshot: Codable, Hashable, Sendable {
    /// Bumped when the shape changes; a snapshot from a different version is
    /// discarded rather than guessed at. 2: dates are numbers, not ISO 8601.
    static let currentVersion = 2

    var version: Int = Self.currentVersion
    var generatedAt: Date
    var decks: [DeckSnapshot]

    static let empty = PracticeSnapshot(generatedAt: .distantPast, decks: [])

    /// Opens the deck list.
    static var deckListDeepLink: URL { PracticeDeepLink.deckList.url }

    func totalDueCount(at date: Date, calendar: Calendar = .current) -> Int {
        decks.reduce(0) { $0 + $1.dueCount(at: date, calendar: calendar) }
    }

    /// Decks with something waiting, busiest first.
    func decksWithDueCards(at date: Date, calendar: Calendar = .current) -> [DeckSnapshot] {
        decks
            .filter { $0.dueCount(at: date, calendar: calendar) > 0 }
            .sorted {
                let left = $0.dueCount(at: date, calendar: calendar)
                let right = $1.dueCount(at: date, calendar: calendar)
                return left == right ? $0.name < $1.name : left > right
            }
    }

    /// Whether anything was practiced on the given day at all.
    func practicedCount(onDayOf date: Date, calendar: Calendar = .current) -> Int {
        decks.reduce(0) { $0 + $1.practicedCount(onDayOf: date, calendar: calendar) }
    }

    /// Moments after `date` at which the due list changes: a card coming due,
    /// or midnight resetting "practiced today". Used to drive widget reloads
    /// without the app having to run.
    func refreshDates(after date: Date, limit: Int = 8, calendar: Calendar = .current) -> [Date] {
        let futureReviews = Set(
            decks
                .lazy
                .flatMap(\.cards)
                .filter { !$0.isSuspended && $0.nextReviewDate > date }
                .map(\.nextReviewDate)
        )
        var dates = futureReviews

        // Midnight boundaries, so cards practiced today reappear tomorrow.
        var midnight = calendar.startOfDay(for: date)
        for _ in 0..<3 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { break }
            dates.insert(next)
            midnight = next
        }

        return Array(dates.sorted().prefix(limit))
    }
}

// MARK: - Storage

/// Reads and writes the snapshot in the shared app group container.
enum PracticeSnapshotStore {
    static func load() -> PracticeSnapshot? {
        guard let url = SharedContainer.snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder.snapshot.decode(PracticeSnapshot.self, from: data),
              snapshot.version == PracticeSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    static func save(_ snapshot: PracticeSnapshot) {
        guard let url = SharedContainer.snapshotURL,
              let data = try? JSONEncoder.snapshot.encode(snapshot)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// Deliberately the default date strategy (a plain number) rather than
// `.iso8601`: ISO 8601 formatting *traps* on a date it can't represent, and a
// runaway review interval produces exactly such a date. This file is only ever
// read by the code that wrote it, so there is nothing to gain from a
// human-readable date and a crash to lose.
private extension JSONDecoder {
    static var snapshot: JSONDecoder { JSONDecoder() }
}

private extension JSONEncoder {
    static var snapshot: JSONEncoder { JSONEncoder() }
}
