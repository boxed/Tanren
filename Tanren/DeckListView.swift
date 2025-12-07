//
//  DeckListView.swift
//  Tanren
//

import SwiftUI
import SwiftData

struct DeckListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [Deck]
    @State private var showingNewDeckAlert = false
    @State private var newDeckName = ""

    var body: some View {
        List {
            ForEach(decks) { deck in
                NavigationLink(value: deck) {
                    DeckRowView(deck: deck)
                }
            }
            .onDelete(perform: deleteDecks)
        }
        .navigationTitle("Tanren")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingNewDeckAlert = true }) {
                    Label("Add Deck", systemImage: "plus")
                }
            }
        }
        .alert("New Deck", isPresented: $showingNewDeckAlert) {
            TextField("Deck name", text: $newDeckName)
            Button("Cancel", role: .cancel) {
                newDeckName = ""
            }
            Button("Create") {
                addDeck()
            }
        }
        .onAppear {
            DataSeeder.seedIfNeeded(modelContext: modelContext)
        }
    }

    private func addDeck() {
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let newDeck = Deck(name: name)
        modelContext.insert(newDeck)
        newDeckName = ""
    }

    private func deleteDecks(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(decks[index])
        }
    }
}

struct DeckRowView: View {
    let deck: Deck

    var dueCount: Int {
        SpacedRepetitionManager.selectCardsForPractice(from: deck).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.name)
                .font(.headline)

            HStack {
                Text("\(deck.cards.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if dueCount > 0 {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(dueCount) due")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        DeckListView()
    }
    .modelContainer(for: [Deck.self, Card.self], inMemory: true)
}
