//
//  Deck.swift
//  Tanren
//

import Foundation
import SwiftData

@Model
final class Deck {
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \Card.deck) var cards: [Card]

    init(name: String) {
        self.name = name
        self.cards = []
    }
}
