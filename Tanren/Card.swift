//
//  Card.swift
//  Tanren
//

import Foundation
import SwiftData

/// The three stages of practicing a card
enum PracticeStage: Int, CaseIterable {
    case comfortable = 0  // Warm up at a comfortable pace
    case stretch = 1      // Push a bit - can do it but not easy
    case challenge = 2    // Slightly past current level

    var title: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .stretch: return "Stretch"
        case .challenge: return "Challenge"
        }
    }

    var description: String {
        switch self {
        case .comfortable: return "Warm up at your comfortable pace"
        case .stretch: return "Push a bit - you can do it but it's not easy"
        case .challenge: return "Go slightly past your current level"
        }
    }

    /// Short label for compact contexts where "Comfortable" won't fit.
    var shortTitle: String {
        switch self {
        case .comfortable: return "Comfort"
        case .stretch: return "Stretch"
        case .challenge: return "Challenge"
        }
    }
}

@Model
final class Card {
    var name: String = ""
    var chord1: String = ""
    var chord2: String = ""

    // Optional image and URL
    @Attribute(.externalStorage) var imageData: Data?
    var url: String?

    // BPM tracking for each stage - nil means not yet established
    var comfortableBPM: Int?
    var stretchBPM: Int?
    var challengeBPM: Int?

    // Spaced repetition fields
    var lastReviewDate: Date?
    var nextReviewDate: Date = Date()
    var easeFactor: Double = 2.5
    var intervalDays: Int = 1
    var reviewCount: Int = 0

    /// The longest this card waits between reviews, in days. Nil means the
    /// scheduler's own ceiling applies. Set it to 1 for something you want in
    /// every session — a warm-up, say — that spaced repetition would otherwise
    /// push months out once it goes well. Optional so existing stores need no
    /// migration.
    var maxIntervalDays: Int?

    var deck: Deck?

    // Suspended cards are excluded from practice
    var isSuspended: Bool = false

    // Interval timer fields
    var intervalTimerSeconds: String = ""  // Comma separated seconds, e.g., "10, 50"
    var intervalTimerReps: Int = 1         // Number of repetitions

    /// The meter the metronome counts for this card, stored as its notation
    /// ("3/4"). Optional so existing stores need no migration; nil means 4/4.
    var timeSignatureRaw: String?

    var timeSignature: TimeSignature {
        get { timeSignatureRaw.flatMap(TimeSignature.init(rawValue:)) ?? .default }
        set { timeSignatureRaw = newValue.rawValue }
    }

    init(chord1: String, chord2: String, deck: Deck? = nil, imageData: Data? = nil, url: String? = nil) {
        self.chord1 = chord1
        self.chord2 = chord2
        self.name = chord2.isEmpty ? chord1 : "\(chord1) ↔ \(chord2)"
        self.deck = deck
        self.imageData = imageData
        self.url = url

        // BPM starts unestablished
        self.comfortableBPM = nil
        self.stretchBPM = nil
        self.challengeBPM = nil

        // Spaced repetition defaults for motor skills
        self.lastReviewDate = nil
        self.nextReviewDate = Date() // Due immediately for new cards
        self.easeFactor = 2.5 // Standard SM-2 starting ease
        self.intervalDays = 1 // Start with 1 day (motor skill minimum)
        self.reviewCount = 0
    }

    /// Returns the BPM for a given practice stage
    func bpm(for stage: PracticeStage) -> Int? {
        switch stage {
        case .comfortable: return comfortableBPM
        case .stretch: return stretchBPM
        case .challenge: return challengeBPM
        }
    }

    /// Sets the BPM for a given practice stage
    func setBPM(_ bpm: Int, for stage: PracticeStage) {
        switch stage {
        case .comfortable: comfortableBPM = bpm
        case .stretch: stretchBPM = bpm
        case .challenge: challengeBPM = bpm
        }
    }

    /// Starting BPM for a stage (uses previous value or suggests based on other stages)
    func startingBPM(for stage: PracticeStage) -> Int {
        // If we have a value for this stage, use it
        if let existing = bpm(for: stage) {
            return existing
        }

        // Otherwise, suggest based on other stages
        switch stage {
        case .comfortable:
            return 60 // Default starting BPM
        case .stretch:
            if let comfortable = comfortableBPM {
                return comfortable + 10
            }
            return 70
        case .challenge:
            if let stretch = stretchBPM {
                return stretch + 10
            } else if let comfortable = comfortableBPM {
                return comfortable + 20
            }
            return 80
        }
    }

    /// Whether this card is due for review
    var isDue: Bool {
        nextReviewDate <= Date()
    }

    /// Whether this card was already practiced today
    var wasPracticedToday: Bool {
        guard let lastReview = lastReviewDate else { return false }
        return Calendar.current.isDateInToday(lastReview)
    }

    /// Priority score for card selection (lower = higher priority)
    var priorityScore: Double {
        var score = easeFactor // Lower ease = harder = higher priority

        // Overdue cards get priority boost
        if isDue {
            let overdueDays = Calendar.current.dateComponents([.day], from: nextReviewDate, to: Date()).day ?? 0
            score -= Double(overdueDays) * 0.1
        }

        // Cards with no established BPM are new and need attention
        if comfortableBPM == nil && stretchBPM == nil && challengeBPM == nil {
            score -= 1.0
        }

        return score
    }

    /// Parses intervalTimerSeconds into an array of integers
    var parsedIntervalSeconds: [Int] {
        intervalTimerSeconds
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }
    }

    /// Returns the full list of intervals (seconds repeated by reps)
    var intervalTimerList: [Int] {
        let baseIntervals = parsedIntervalSeconds
        guard !baseIntervals.isEmpty else { return [] }
        var result: [Int] = []
        for _ in 0..<max(1, intervalTimerReps) {
            result.append(contentsOf: baseIntervals)
        }
        return result
    }

    /// Total time in seconds for the interval timer
    var intervalTimerTotalSeconds: Int {
        intervalTimerList.reduce(0, +)
    }
}
