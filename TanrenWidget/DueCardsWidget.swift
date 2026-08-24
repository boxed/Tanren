//
//  DueCardsWidget.swift
//  TanrenWidget
//
//  What is waiting to be practiced, on the home and lock screens.
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

// MARK: - Views

struct DueCardsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DueEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.dueCount == 0 ? "Nothing due" : "\(entry.dueCount) due")
        case .accessoryCircular:
            CircularDueView(entry: entry)
        case .accessoryRectangular:
            RectangularDueView(entry: entry)
        case .systemSmall:
            SmallDueView(entry: entry)
                .widgetURL(entry.decks.first?.deepLink ?? PracticeSnapshot.deckListDeepLink)
        default:
            ListDueView(entry: entry, rowLimit: family == .systemLarge ? 6 : 3)
        }
    }
}

/// The headline number, sized to fill whatever space it's given.
private struct DueCount: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(count == 0 ? .secondary : Color.dueTint)
    }
}

private struct SmallDueView: View {
    let entry: DueEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .bold))
                Text("Tanren")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            DueCount(count: entry.dueCount)

            Text(entry.dueCount == 1 ? "card due" : "cards due")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text(entry.footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Medium and large: the actual list of what's waiting, a row per deck.
private struct ListDueView: View {
    let entry: DueEntry
    let rowLimit: Int

    private var decks: [DeckSnapshot] { Array(entry.decks.prefix(rowLimit)) }
    private var hiddenDeckCount: Int { max(0, entry.decks.count - rowLimit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.dueCount == 0 ? "Nothing due" : "\(entry.dueCount) due")
                    .font(.headline)
                    .foregroundStyle(entry.dueCount == 0 ? .secondary : Color.dueTint)
                Spacer(minLength: 4)
                Text(entry.footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if decks.isEmpty {
                Spacer(minLength: 0)
                Text(entry.emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 6) {
                    ForEach(decks) { deck in
                        Link(destination: deck.deepLink) {
                            DeckRow(deck: deck, date: entry.date)
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
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.dueTint.opacity(0.18)))
                .foregroundStyle(Color.dueTint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .foregroundStyle(.primary)
    }
}

private struct CircularDueView: View {
    let entry: DueEntry

    var body: some View {
        Gauge(value: Double(min(entry.dueCount, 20)), in: 0...20) {
            Image(systemName: "music.note")
        } currentValueLabel: {
            Text("\(entry.dueCount)")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
    }
}

private struct RectangularDueView: View {
    let entry: DueEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Tanren")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text(entry.dueCount == 0 ? "Nothing due" : "\(entry.dueCount) cards due")
                .font(.headline)
            Text(entry.decks.first?.name ?? entry.footnote)
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Copy and colour

private extension Color {
    /// The same orange the deck list uses for its "due" pill.
    static let dueTint = Color.orange
}

private extension DueEntry {
    var footnote: String {
        guard hasSnapshot else { return "Open Tanren" }
        if practicedToday > 0 {
            return "\(practicedToday) done today"
        }
        return snapshot.decks.isEmpty ? "No decks" : "Not started today"
    }

    var emptyMessage: String {
        guard hasSnapshot else { return "Open Tanren to set up your decks." }
        if snapshot.decks.isEmpty { return "Create a deck to start practicing." }
        if practicedToday > 0 { return "Everything due today is done. Nice." }
        return "Nothing is due yet — come back later."
    }
}

// MARK: - Previews

extension PracticeSnapshot {
    /// Stand-in for the widget gallery and Xcode previews.
    static var preview: PracticeSnapshot {
        let now = Date()
        func card(_ name: String, days: Double, reviewed: Bool = true) -> CardSnapshot {
            CardSnapshot(
                name: name,
                nextReviewDate: now.addingTimeInterval(days * 86_400),
                lastReviewDate: reviewed ? now.addingTimeInterval(-3 * 86_400) : nil,
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
}

#Preview("Small", as: .systemSmall) {
    DueCardsWidget()
} timeline: {
    DueEntry(date: .now, snapshot: .preview)
    DueEntry(date: .now, snapshot: .empty)
}

#Preview("Medium", as: .systemMedium) {
    DueCardsWidget()
} timeline: {
    DueEntry(date: .now, snapshot: .preview)
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
}
