//
//  ContentView.swift
//  Tanren
//
//  Created by Anders Hovmöller on 2025-12-07.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationStack {
            DeckListView()
                .navigationDestination(for: Deck.self) { deck in
                    DeckDetailView(deck: deck)
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Deck.self, Card.self], inMemory: true)
}
