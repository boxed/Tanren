//
//  DeckSettingsView.swift
//  Tanren
//

import SwiftUI
import SwiftData

struct DeckSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: Deck

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $deck.name)
                }

                Section {
                    Toggle("Metronome", isOn: $deck.metronomeEnabled)
                } footer: {
                    Text("When disabled, practice sessions won't show the metronome or BPM controls.")
                }
            }
            .navigationTitle("Deck Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DeckSettingsView(deck: Deck(name: "Test Deck"))
        .modelContainer(for: [Deck.self, Card.self], inMemory: true)
}
