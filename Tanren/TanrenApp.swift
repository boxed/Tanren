//
//  TanrenApp.swift
//  Tanren
//
//  Created by Anders Hovmöller on 2025-12-07.
//

import SwiftUI
import SwiftData

@main
struct TanrenApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Deck.self,
            Card.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground is when the widget starts to matter, and
            // when any practice results are final.
            if phase != .active {
                PracticeSnapshotWriter.refresh(modelContext: sharedModelContainer.mainContext)
            }
        }
    }
}
