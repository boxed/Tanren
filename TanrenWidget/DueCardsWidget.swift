//
//  DueCardsWidget.swift
//  TanrenWidget
//
//  What is waiting to be practiced, on the home and lock screens.
//
//  The visual idea: a day of practice is a fixed, finishable unit (the daily
//  quota), drawn as one tick per card — hot ember while a card is waiting,
//  quenched steel once it has been practiced. The day cools as you work,
//  which is the app's name (鍛錬, forging) made visible.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct DueEntry: TimelineEntry {
    var date: Date
    var snapshot: PracticeSnapshot

    /// Nothing has been written yet — the app has never run, or the shared
    /// container is unavailable.
    var hasSnapshot: Bool { snapshot.generatedAt != .distantPast }

    var dueCount: Int { snapshot.totalDueCount(at: date) }
    var decks: [DeckSnapshot] { snapshot.decksWithDueCards(at: date) }
    var practicedToday: Int { snapshot.practicedCount(onDayOf: date) }

    /// Everything today asked for has been practiced.
    var isDoneForToday: Bool { dueCount == 0 && practicedToday > 0 }
}

struct DueProvider: TimelineProvider {
    func placeholder(in context: Context) -> DueEntry {
        DueEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DueEntry) -> Void) {
        // Sample decks belong in the widget gallery only — anywhere else, show
        // the real state, empty or not.
        let fallback: PracticeSnapshot = context.isPreview ? .preview : .empty
        completion(DueEntry(date: Date(), snapshot: PracticeSnapshotStore.load() ?? fallback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DueEntry>) -> Void) {
        let now = Date()
        let snapshot = PracticeSnapshotStore.load() ?? .empty

        // One entry now, then one at each moment the due list changes: a card
        // coming due, or midnight putting today's practiced cards back in
        // rotation. No app launch needed in between.
        var entries = [DueEntry(date: now, snapshot: snapshot)]
        entries += snapshot
            .refreshDates(after: now)
            .map { DueEntry(date: $0, snapshot: snapshot) }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct DueCardsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TanrenDueCards", provider: DueProvider()) { entry in
            DueCardsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Due Cards")
        .description("What is waiting to be practiced.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Palette

private extension Color {
    /// Hot: a card still waiting in today's session.
    static let ember = Color(red: 0.894, green: 0.341, blue: 0.180)
    /// Cool: a card already practiced — the day quenches as you work.
    static let steel = Color(red: 0.439, green: 0.561, blue: 0.659)
}

// MARK: - Shared pieces

/// One tick per card in today's session: steel for practiced, ember for
/// waiting. An untouched day shows the shape of its quota as a faint track.
/// Falls back to a proportional bar when several busy decks would need more
/// ticks than fit legibly.
private struct StrikeMeter: View {
    let done: Int
    let remaining: Int
    var height: CGFloat = 5
    var centered = false

    private static let maxTicks = 14

    var body: some View {
        Group {
            if done + remaining == 0 {
                ticks([(PracticePolicy.maxCardsPerDay, Color.secondary.opacity(0.18))])
            } else if done + remaining <= Self.maxTicks {
                ticks([(done, .steel.opacity(0.65)), (remaining, .ember)])
            } else {
                proportionalBar
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(remaining) cards left today, \(done) practiced")
    }

    private func ticks(_ groups: [(count: Int, color: Color)]) -> some View {
        HStack(spacing: 3) {
            if centered { Spacer(minLength: 0) }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                ForEach(0..<group.count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(group.color)
                        .frame(maxWidth: 20)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var proportionalBar: some View {
        GeometryReader { geo in
            let total = CGFloat(done + remaining)
            HStack(spacing: 2) {
                if done > 0 {
                    Capsule().fill(Color.steel.opacity(0.65))
                        .frame(width: geo.size.width * CGFloat(done) / total)
                }
                if remaining > 0 {
                    Capsule().fill(Color.ember)
                }
            }
        }
    }
}

// MARK: - Views

struct DueCardsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DueEntry

    var body: some View {
        switch family {
        // A finished day leaves the lock screen alone: the accessory families
        // render nothing at all rather than a resting state.
        case .accessoryInline:
            if !entry.isDoneForToday { Text(entry.inlineText) }
        case .accessoryCircular:
            if entry.isDoneForToday { Color.clear } else { CircularDueView(entry: entry) }
        case .accessoryRectangular:
            if entry.isDoneForToday { Color.clear } else { RectangularDueView(entry: entry) }
        case .systemSmall:
            SmallDueView(entry: entry)
                .widgetURL(entry.decks.first?.deepLink ?? PracticeSnapshot.deckListDeepLink)
        default:
            ListDueView(entry: entry, rowLimit: family == .systemLarge ? 5 : 3)
        }
    }
}

private struct SmallDueView: View {
    let entry: DueEntry

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 4)

            if entry.isDoneForToday {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(Color.steel)
                Spacer(minLength: 4)
                Text("Done for today")
                    .font(.subheadline.weight(.semibold))
            } else if entry.dueCount == 0 {
                Text("Nothing due")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(entry.dueCount)")
                    .font(.system(size: 58, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.ember)
                Text(entry.dueCount == 1 ? "card left today" : "cards left today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            StrikeMeter(done: entry.practicedToday, remaining: entry.dueCount, centered: true)

            Text(entry.footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 5)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Medium and large: today's headline and meter, then a row per deck.
private struct ListDueView: View {
    let entry: DueEntry
    let rowLimit: Int

    private var decks: [DeckSnapshot] { Array(entry.decks.prefix(rowLimit)) }
    private var hiddenDeckCount: Int { max(0, entry.decks.count - rowLimit) }

    private var headline: String {
        if entry.isDoneForToday { return "Done for today" }
        if entry.dueCount == 0 { return "Nothing due" }
        return "\(entry.dueCount) left today"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(entry.dueCount > 0 ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                Text(entry.footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            StrikeMeter(done: entry.practicedToday, remaining: entry.dueCount)

            if decks.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 0) {
                    ForEach(decks) { deck in
                        Link(destination: deck.deepLink) {
                            DeckRow(deck: deck, date: entry.date)
                        }
                        if deck.id != decks.last?.id {
                            Divider()
                        }
                    }
                }

                if hiddenDeckCount > 0 {
                    Text("+\(hiddenDeckCount) more deck\(hiddenDeckCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(PracticeSnapshot.deckListDeepLink)
    }

    @ViewBuilder
    private var emptyState: some View {
        if entry.isDoneForToday {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(Color.steel)
                Text("\(entry.practicedToday) card\(entry.practicedToday == 1 ? "" : "s") practiced")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(entry.emptyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DeckRow: View {
    let deck: DeckSnapshot
    let date: Date

    private var count: Int { deck.dueCount(at: date) }

    /// A couple of card names, so the row says what is actually waiting rather
    /// than just how much of it there is.
    private var examples: String {
        deck.dueCards(at: date).prefix(3).map(\.name).joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !examples.isEmpty {
                    Text(examples)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.ember)
        }
        .padding(.vertical, 5)
        .foregroundStyle(.primary)
    }
}

private struct CircularDueView: View {
    let entry: DueEntry

    /// The ring fills as the day's session gets done, not as debt piles up.
    private var progress: Double {
        let total = entry.practicedToday + entry.dueCount
        guard total > 0 else { return 0 }
        return Double(entry.practicedToday) / Double(total)
    }

    var body: some View {
        Gauge(value: progress) {
            Image(systemName: "tornado")
        } currentValueLabel: {
            Text("\(entry.dueCount)")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.ember)
    }
}

private struct RectangularDueView: View {
    let entry: DueEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.inlineText)
                .font(.headline)
                .widgetAccentable()
            StrikeMeter(done: entry.practicedToday, remaining: entry.dueCount, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Copy

private extension DueEntry {
    /// The one-line answer, for the inline and rectangular families.
    var inlineText: String {
        if isDoneForToday { return "Done for today" }
        if dueCount == 0 { return "Nothing due" }
        return "\(dueCount) left today"
    }

    var footnote: String {
        guard hasSnapshot else { return "Open Tanren" }
        if practicedToday > 0 {
            return "\(practicedToday) done today"
        }
        return snapshot.decks.isEmpty ? "No decks yet" : "Not started today"
    }

    var emptyMessage: String {
        guard hasSnapshot else { return "Open Tanren to set up your decks." }
        if snapshot.decks.isEmpty { return "Create a deck to start practicing." }
        return "Nothing is due yet — come back later."
    }
}

// MARK: - Previews

extension PracticeSnapshot {
    /// Stand-in for the widget gallery and Xcode previews.
    static var preview: PracticeSnapshot {
        let now = Date()
        func card(_ name: String, days: Double, reviewed: Bool = true, today: Bool = false) -> CardSnapshot {
            CardSnapshot(
                name: name,
                nextReviewDate: now.addingTimeInterval(days * 86_400),
                lastReviewDate: today ? now : (reviewed ? now.addingTimeInterval(-3 * 86_400) : nil),
                isSuspended: false
            )
        }

        return PracticeSnapshot(
            generatedAt: now,
            decks: [
                DeckSnapshot(id: "preview-chords", name: "Chords", cards: [
                    card("C ↔ G", days: -2),
                    card("D ↔ A", days: -1),
                    card("Em ↔ Am", days: -0.5),
                    card("F ↔ C", days: -0.2),
                    card("A ↔ E", days: -0.1, today: true),
                    card("Am ↔ C", days: -0.1, today: true),
                    card("G ↔ D", days: 2),
                ]),
                DeckSnapshot(id: "preview-scales", name: "Scales", cards: [
                    card("A minor pentatonic", days: -1),
                    card("G major", days: -0.1, reviewed: false),
                    card("E blues", days: 3),
                ]),
            ]
        )
    }

    /// Everything practiced: the state worth designing for.
    static var previewDone: PracticeSnapshot {
        let now = Date()
        return PracticeSnapshot(
            generatedAt: now,
            decks: [
                DeckSnapshot(id: "preview-chords", name: "Chords", cards: (0..<8).map {
                    CardSnapshot(
                        name: "Card \($0)",
                        nextReviewDate: now.addingTimeInterval(-3_600),
                        lastReviewDate: now,
                        isSuspended: false
                    )
                }),
            ]
        )
    }
}

#Preview("Small", as: .systemSmall) {
    DueCardsWidget()
} timeline: {
    DueEntry(date: .now, snapshot: .preview)
    DueEntry(date: .now, snapshot: .previewDone)
    DueEntry(date: .now, snapshot: .empty)
}

#Preview("Medium", as: .systemMedium) {
    DueCardsWidget()
} timeline: {
    DueEntry(date: .now, snapshot: .preview)
    DueEntry(date: .now, snapshot: .previewDone)
    DueEntry(date: .now, snapshot: .empty)
}

#Preview("Large", as: .systemLarge) {
    DueCardsWidget()
} timeline: {
    DueEntry(date: .now, snapshot: .preview)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    DueCardsWidget()
} timeline: {
    DueEntry(date: .now, snapshot: .preview)
    DueEntry(date: .now, snapshot: .previewDone)
}
