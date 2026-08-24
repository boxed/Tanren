# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tanren is an iOS app for learning motor skills through spaced repetition, initially focused on guitar chord switching practice. The name "Tanren" (鍛錬) is Japanese for "training/forging."

## Build and Run

This is an Xcode project (Swift/SwiftUI). Build and run using:
- Open `Tanren.xcodeproj` in Xcode
- Select an iOS simulator or device
- Press Cmd+R to build and run

Run tests:
- Cmd+U in Xcode runs all tests
- Or: `xcodebuild test -project Tanren.xcodeproj -scheme Tanren -destination 'platform=iOS Simulator,name=iPhone 16'`

## Architecture

- **SwiftUI** for UI
- **SwiftData** for persistence
- **AVFoundation** for metronome audio
- iOS 26.1+ deployment target

### Data Models

- `Deck.swift` - Contains cards, has one-to-many relationship with Card; `linkID` is a stable UUID for widget deep links
- `Card.swift` - Chord switching exercise with BPM levels (mastered/mostlyMastered/struggling) and spaced repetition fields (nextReviewDate, easeFactor, intervalDays)

### Core Components

- `MetronomeEngine.swift` - AVAudioEngine-based metronome with programmatically generated click sound
- `SpacedRepetitionManager.swift` - Motor-skill optimized SM-2 algorithm (24hr+ initial intervals, weekly progression)
- `DataSeeder.swift` - Seeds 36 chord combinations from 9 basic chords on first launch

### Widget

`TanrenWidget` is a WidgetKit extension showing what is due. It does **not** open
the SwiftData store — the app publishes a JSON snapshot to a shared app group
container and the widget reads that:

- `TanrenShared/PracticeSnapshot.swift` - Codable snapshot, due-date maths, deep
  link format, and the app group container path. Compiled into **both** the app
  and the widget target (a synchronized group listed in both).
- `Tanren/PracticeSnapshotWriter.swift` - Builds the snapshot from SwiftData and
  reloads the widget timelines. Called when the app leaves the foreground
  (`TanrenApp`) and when the deck list appears (`DeckListView`).
- `TanrenWidget/DueCardsWidget.swift` - Timeline provider and views for small,
  medium, large and the three lock screen families.

Two things follow from the snapshot design:

- The snapshot stores *dates*, not pre-computed counts, so the widget works out
  what's due at each timeline entry. Reload points come from
  `PracticeSnapshot.refreshDates(after:)`: each future review date plus the next
  few midnights (when "practiced today" resets).
- The app group is `group.net.kodare.Tanren`, declared in both entitlements
  files. Without it `SharedContainer.snapshotURL` is nil and the widget shows an
  "Open Tanren" placeholder.

Tapping the widget deep links via `tanren://deck?id=…&name=…` (or
`tanren://decks`), handled in `ContentView`. The id is `Deck.linkID`, a UUID
assigned on first use, so a placed widget survives a deck rename.

Note for tests touching SwiftData: **hold on to the `ModelContainer`** for as
long as you use its context. `try ModelContainer(...).mainContext` releases the
container straight away, and the next insert traps inside SwiftData — killing
the whole test process, so every other test in the bundle reports as failed too.
See `TestStore` in `PracticeSnapshotTests`.

### Views

- `ContentView.swift` - NavigationStack container, handles widget deep links
- `DeckListView.swift` - Shows all decks with due card counts
- `DeckDetailView.swift` - Cards list with BPM badges, practice button
- `PracticeView.swift` - Main practice UI with metronome, ±10 BPM controls, performance rating

### Practice Flow

1. User selects deck → taps "Start Practice"
2. SpacedRepetitionManager selects cards (prioritizes due/weak, adds randomness)
3. PracticeView shows card with metronome at appropriate BPM
4. User rates performance (Struggling/Getting There/Mastered)
5. Card BPM and scheduling updated, moves to next card
