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

- `Deck.swift` - Contains cards, has one-to-many relationship with Card
- `Card.swift` - Chord switching exercise with BPM levels (mastered/mostlyMastered/struggling) and spaced repetition fields (nextReviewDate, easeFactor, intervalDays)

### Core Components

- `MetronomeEngine.swift` - AVAudioEngine-based metronome with programmatically generated click sound
- `SpacedRepetitionManager.swift` - Motor-skill optimized SM-2 algorithm (24hr+ initial intervals, weekly progression)
- `DataSeeder.swift` - Seeds 36 chord combinations from 9 basic chords on first launch

### Views

- `ContentView.swift` - NavigationStack container
- `DeckListView.swift` - Shows all decks with due card counts
- `DeckDetailView.swift` - Cards list with BPM badges, practice button
- `PracticeView.swift` - Main practice UI with metronome, ±10 BPM controls, performance rating

### Practice Flow

1. User selects deck → taps "Start Practice"
2. SpacedRepetitionManager selects cards (prioritizes due/weak, adds randomness)
3. PracticeView shows card with metronome at appropriate BPM
4. User rates performance (Struggling/Getting There/Mastered)
5. Card BPM and scheduling updated, moves to next card
