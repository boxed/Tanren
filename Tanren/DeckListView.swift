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
    @State private var showingPractice = false

    private var dueCount: Int {
        SpacedRepetitionManager.selectDueCardsAcrossDecks(from: decks).count
    }

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
        .safeAreaInset(edge: .bottom) {
            if !decks.isEmpty {
                practiceBar
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
        .fullScreenCover(isPresented: $showingPractice, onDismiss: {
            PracticeSnapshotWriter.refresh(modelContext: modelContext)
        }) {
            PracticeView(decks: decks)
        }
        .onAppear {
            DataSeeder.seedIfNeeded(modelContext: modelContext)
            SpacedRepetitionManager.repairRunawayIntervals(modelContext: modelContext)
            // Also the moment a practice session hands control back, so the
            // widget reflects what was just practiced.
            PracticeSnapshotWriter.refresh(modelContext: modelContext)
        }
    }

    /// One session for everything due today, whichever deck it lives in.
    /// Same shape as the deck screen's bar so the two read as the same action.
    private var practiceBar: some View {
        VStack(spacing: 6) {
            Button(action: { showingPractice = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Start Practice")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(dueCount > 0 ? Color.accentColor : Color.secondary.opacity(0.25))
                )
                .foregroundStyle(dueCount > 0 ? Color.white : Color.secondary)
            }
            .disabled(dueCount == 0)

            Text(dueCount > 0
                 ? "\(dueCount) card\(dueCount == 1 ? "" : "s") due across all decks"
                 : "Nothing due — everything is practiced for today")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
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

            if deck.dueCount > 0 {
                Pill("\(deck.dueCount) left", systemImage: "clock.fill", tint: .orange)
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
