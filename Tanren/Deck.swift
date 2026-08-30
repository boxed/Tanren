//
//  Deck.swift
//  Tanren
//

import Foundation
import SwiftData

@Model
final class Deck {
    var name: String = ""
    var metronomeEnabled: Bool = true
    var side2Enabled: Bool = true
    var imagesEnabled: Bool = false
    var urlEnabled: Bool = false
    var intervalTimersEnabled: Bool = false

    /// Stable identifier for widget deep links: survives a rename, and is short
    /// enough to sit in a URL. Optional and assigned on first use, so existing
    /// decks pick one up without a migration step.
    var linkID: UUID?

    /// How many cards a day's session asks for in this deck. Optional so
    /// existing decks need no migration; nil means the app-wide default.
    var maxCardsPerDay: Int?

    var dailyCardLimit: Int {
        get { maxCardsPerDay ?? PracticePolicy.defaultMaxCardsPerDay }
        set { maxCardsPerDay = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Card.deck) var cardsRelation: [Card]?

    var cards: [Card] {
        get { cardsRelation ?? [] }
        set { cardsRelation = newValue }
    }

    init(name: String, metronomeEnabled: Bool = true, side2Enabled: Bool = true, imagesEnabled: Bool = false, urlEnabled: Bool = false, intervalTimersEnabled: Bool = false) {
        self.name = name
        self.metronomeEnabled = metronomeEnabled
        self.side2Enabled = side2Enabled
        self.imagesEnabled = imagesEnabled
        self.urlEnabled = urlEnabled
        self.intervalTimersEnabled = intervalTimersEnabled
        self.cardsRelation = []
    }
}
