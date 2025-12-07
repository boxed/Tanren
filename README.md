# Tanren

Tanren (鍛錬, "training/forging") is an iOS app for learning motor skills through spaced repetition, initially focused on guitar chord switching practice.

## Features

- **Spaced Repetition for Motor Skills**: Optimized scheduling algorithm with longer intervals than verbal learning (daily → weekly → monthly progression)
- **Three-Stage Practice**: Each card progresses through Comfortable → Stretch → Challenge BPM levels
- **Built-in Metronome**: Programmatically generated click sound with visual beat indicator
- **Progress Tracking**: Tracks BPM levels and review history for each chord combination
- **Daily Practice Quota**: 10 cards per day with smart selection (prioritizes due cards, adds variety)

## Requirements

- iOS 17.0+
- Xcode 15+

## Building

1. Open `Tanren.xcodeproj` in Xcode
2. Select an iOS simulator or device
3. Press Cmd+R to build and run

## Running Tests

- Cmd+U in Xcode runs all tests
- Or via command line:
  ```
  xcodebuild test -project Tanren.xcodeproj -scheme Tanren -destination 'platform=iOS Simulator,name=iPhone 16'
  ```

## Architecture

- **SwiftUI** for UI
- **SwiftData** for persistence
- **AVFoundation** for metronome audio

### Data Models

- `Deck` - Contains cards with one-to-many relationship
- `Card` - Chord switching exercise with BPM levels and spaced repetition fields

### Practice Flow

1. User selects deck and taps "Start Practice"
2. SpacedRepetitionManager selects up to 10 cards (prioritizes due/weak cards)
3. For each card, user practices at three BPM stages: Comfortable, Stretch, Challenge
4. Card scheduling is updated based on completion
5. Cards practiced today are excluded from future sessions that day
