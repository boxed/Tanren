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
                Section("Name") {
                    TextField("Deck name", text: $deck.name)
                }

                Section {
                    Toggle("Metronome", isOn: $deck.metronomeEnabled)
                    Toggle("Interval Timers", isOn: $deck.intervalTimersEnabled)
                } header: {
                    Text("Practice Tools")
                } footer: {
                    Text("The metronome adds BPM stages to every card. Interval timers add timed work/rest periods, configured per card.")
                }

                Section {
                    Toggle("Side 2", isOn: $deck.side2Enabled)
                    Toggle("Images", isOn: $deck.imagesEnabled)
                    Toggle("URLs", isOn: $deck.urlEnabled)
                } header: {
                    Text("Card Fields")
                } footer: {
                    Text("Choose which fields cards in this deck can use.")
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
