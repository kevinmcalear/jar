import SwiftUI
import WidgetKit

private enum Ink {
    static let ground = Color(red: 0x0E / 255, green: 0x0E / 255, blue: 0x0E / 255)
    static let paper = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255)
    static let flare = Color(red: 1, green: 0x4D / 255, blue: 0x1C / 255)
}

struct PileEntry: TimelineEntry {
    var date: Date
    var left: Int?
}

struct PileProvider: TimelineProvider {
    func placeholder(in context: Context) -> PileEntry {
        PileEntry(date: .now, left: 4400)
    }

    func getSnapshot(in context: Context, completion: @escaping (PileEntry) -> Void) {
        let left = PileBoard.read() ?? (context.isPreview ? 4400 : nil)
        completion(PileEntry(date: .now, left: left))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PileEntry>) -> Void) {
        let entry = PileEntry(date: .now, left: PileBoard.read())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct PileWidgetView: View {
    var entry: PileEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.left.map { formatCents($0) } ?? "—")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.paper)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text("left today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ink.flare)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Ink.ground, for: .widget)
    }
}

struct PileWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "pile-left", provider: PileProvider()) { entry in
            PileWidgetView(entry: entry)
        }
        .configurationDisplayName("Left today")
        .description("How much of today's pile is left.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LogEntry: TimelineEntry {
    var date: Date
}

struct LogProvider: TimelineProvider {
    func placeholder(in context: Context) -> LogEntry { LogEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (LogEntry) -> Void) {
        completion(LogEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LogEntry>) -> Void) {
        completion(Timeline(entries: [LogEntry(date: .now)], policy: .never))
    }
}

struct LogWidgetView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Ink.ground)
                .frame(width: 64, height: 64)
                .background(Ink.flare, in: Circle())
            Text("Log a spend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.paper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(PileBoard.add)
        .containerBackground(Ink.ground, for: .widget)
    }
}

struct LogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "log-spend", provider: LogProvider()) { _ in
            LogWidgetView()
        }
        .configurationDisplayName("Log a spend")
        .description("Opens Jar to log a spend.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct JarWidgets: WidgetBundle {
    var body: some Widget {
        PileWidget()
        LogWidget()
    }
}
