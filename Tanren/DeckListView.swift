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
        .overlay {
            if decks.isEmpty {
                ContentUnavailableView {
                    Label("No Decks", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Create a deck to start building a practice routine.")
                } actions: {
                    Button("New Deck") { showingNewDeckSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            }
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

    /// Share of the deck that has been practiced at least once.
    private var startedFraction: Double {
        guard !deck.cards.isEmpty else { return 0 }
        return Double(startedCount) / Double(deck.cards.count)
    }

    private var startedCount: Int {
        deck.cards.filter { $0.reviewCount > 0 }.count
    }

    private var subtitle: String {
        let cards = "\(deck.cards.count) card\(deck.cards.count == 1 ? "" : "s")"
        guard !deck.cards.isEmpty else { return "Empty deck" }
        return startedCount == 0
            ? "\(cards) · not started"
            : "\(cards) · \(startedCount) started"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: startedFraction)
                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if dueCount > 0 {
                Pill("\(dueCount) due", systemImage: "clock.fill", tint: .orange)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        DeckListView()
    }
    .modelContainer(for: [Deck.self, Card.self], inMemory: true)
}
