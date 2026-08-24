//
//  ContentView.swift
//  Tanren
//
//  Created by Anders Hovmöller on 2025-12-07.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var path: [Deck] = []

    var body: some View {
        NavigationStack(path: $path) {
            DeckListView()
                .navigationDestination(for: Deck.self) { deck in
                    DeckDetailView(deck: deck)
                }
        }
        .onOpenURL(perform: open)
    }

    /// Handles the widget's deep links: `tanren://decks` for the list,
    /// `tanren://deck?id=…&name=…` for one deck.
    private func open(_ url: URL) {
        switch PracticeDeepLink(url: url) {
        case .none:
            return
        case .deckList:
            path.removeAll()
        case let .deck(id, name):
            let deck = DeckReference.resolve(token: id, name: name, in: modelContext)
            path = deck.map { [$0] } ?? []
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Deck.self, Card.self], inMemory: true)
}
