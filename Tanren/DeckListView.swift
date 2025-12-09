//
//  DeckListView.swift
//  Tanren
//

import SwiftUI
import SwiftData

struct DeckListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [Deck]
    @State private var showingNewDeckSheet = false

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
                Button(action: { showingNewDeckSheet = true }) {
                    Label("Add Deck", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewDeckSheet) {
            NewDeckView()
        }
        .onAppear {
            DataSeeder.seedIfNeeded(modelContext: modelContext)
        }
    }

    private func deleteDecks(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(decks[index])
        }
    }
}

struct NewDeckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var deckName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck name", text: $deckName)
                }

                Section("Presets") {
                    Button("Chord Changes") {
                        createChordChangesDeck()
                    }
                }
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createEmptyDeck()
                    }
                    .disabled(deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createEmptyDeck() {
        let name = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let newDeck = Deck(name: name)
        modelContext.insert(newDeck)
        dismiss()
    }

    private func createChordChangesDeck() {
        let basicChords = ["A", "B", "C", "D", "E", "F", "G", "Am", "Em"]
        let deck = Deck(name: "Chord Changes")
        modelContext.insert(deck)

        for i in 0..<basicChords.count {
            for j in (i + 1)..<basicChords.count {
                let card = Card(
                    chord1: basicChords[i],
                    chord2: basicChords[j],
                    deck: deck
                )
                modelContext.insert(card)
                deck.cards.append(card)
            }
        }

        try? modelContext.save()
        dismiss()
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
