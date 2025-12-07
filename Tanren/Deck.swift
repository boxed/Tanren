//
//  Deck.swift
//  Tanren
//

import Foundation
import SwiftData

@Model
final class Deck {
    var name: String
    var metronomeEnabled: Bool = true
    @Relationship(deleteRule: .cascade, inverse: \Card.deck) var cards: [Card]

    init(name: String, metronomeEnabled: Bool = true) {
        self.name = name
        self.metronomeEnabled = metronomeEnabled
        self.cards = []
    }
}
