//
//  DeckDetailView.swift
//  Tanren
//

import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @State private var showingPractice = false
    @State private var selectedCard: Card?

    var dueCount: Int {
        SpacedRepetitionManager.selectCardsForPractice(from: deck).count
    }

    var body: some View {
        List {
            Section {
                Button(action: { showingPractice = true }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Practice")
                        Spacer()
                        if dueCount > 0 {
                            Text("\(dueCount) due")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(deck.cards.isEmpty)
            }

            Section("Cards (\(deck.cards.count))") {
                ForEach(deck.cards.sorted { $0.name < $1.name }) { card in
                    Button(action: { selectedCard = card }) {
                        CardRowView(card: card)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(deck.name)
        .fullScreenCover(isPresented: $showingPractice) {
            PracticeView(deck: deck)
        }
        .fullScreenCover(item: $selectedCard) { card in
            PracticeView(deck: deck, startingCard: card)
        }
    }
}

struct CardRowView: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(card.name)
                    .font(.headline)

                Spacer()

                if card.isDue {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            HStack(spacing: 12) {
                if let bpm = card.comfortableBPM {
                    BPMBadge(label: "C", bpm: bpm, color: .green)
                }
                if let bpm = card.stretchBPM {
                    BPMBadge(label: "S", bpm: bpm, color: .yellow)
                }
                if let bpm = card.challengeBPM {
                    BPMBadge(label: "X", bpm: bpm, color: .red)
                }

                Spacer()

                if card.reviewCount > 0 {
                    Text("\(card.reviewCount) reviews")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct BPMBadge: View {
    let label: String
    let bpm: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
            Text("\(bpm)")
                .font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .foregroundStyle(color)
        .cornerRadius(4)
    }
}

#Preview {
    NavigationStack {
        DeckDetailView(deck: {
            let deck = Deck(name: "Chords")
            let card = Card(chord1: "C", chord2: "D", deck: deck)
            card.comfortableBPM = 60
            card.stretchBPM = 80
            card.challengeBPM = 100
            deck.cards.append(card)
            return deck
        }())
    }
    .modelContainer(for: [Deck.self, Card.self], inMemory: true)
}
