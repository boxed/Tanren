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
