//
//  DataSeeder.swift
//  Tanren
//

import Foundation
import SwiftData

struct DataSeeder {
    static let basicChords = ["A", "B", "C", "D", "E", "F", "G", "Am", "Em"]

    /// Seeds the database with default chord combinations if no decks exist
    static func seedIfNeeded(modelContext: ModelContext) {
        // Check if any decks exist
        let descriptor = FetchDescriptor<Deck>()
        let existingDecks = (try? modelContext.fetch(descriptor)) ?? []

        if existingDecks.isEmpty {
            seedDefaultChords(modelContext: modelContext)
        }
    }

    /// Creates the default "Chords" deck with all chord switching combinations
    private static func seedDefaultChords(modelContext: ModelContext) {
        let chordsDeck = Deck(name: "Chords")
        modelContext.insert(chordsDeck)

        // Create all unique chord pair combinations
        for i in 0..<basicChords.count {
            for j in (i + 1)..<basicChords.count {
                let card = Card(
                    chord1: basicChords[i],
                    chord2: basicChords[j],
                    deck: chordsDeck
                )
                modelContext.insert(card)
                chordsDeck.cards.append(card)
            }
        }

        try? modelContext.save()
    }
}
