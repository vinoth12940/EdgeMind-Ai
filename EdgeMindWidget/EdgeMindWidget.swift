import WidgetKit
import SwiftUI

/// Widgets only ever deep-link into the app. They show no chat content and read
/// no shared data — the timeline is static (spec §4).
struct EdgeMindEntry: TimelineEntry {
    let date: Date
}

struct EdgeMindProvider: TimelineProvider {
    func placeholder(in context: Context) -> EdgeMindEntry {
        EdgeMindEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (EdgeMindEntry) -> Void) {
        completion(EdgeMindEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EdgeMindEntry>) -> Void) {
        completion(Timeline(entries: [EdgeMindEntry(date: .now)], policy: .never))
    }
}

private enum WidgetLink {
    static func url(mode: String) -> URL {
        URL(string: "edgemindai://ask?mode=\(mode)")!
    }
}

struct EdgeMindWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumContent
        case .accessoryCircular:
            circularContent
        default:
            smallContent
        }
    }

    // MARK: - Families

    private var smallContent: some View {
        actionLink(mode: "text", title: "Ask", icon: "bubble.left.and.text.bubble.right.fill")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mediumContent: some View {
        HStack(spacing: 10) {
            actionLink(mode: "text", title: "Ask", icon: "bubble.left.and.text.bubble.right.fill")
            actionLink(mode: "voice", title: "Voice", icon: "waveform.circle.fill")
            actionLink(mode: "camera", title: "Camera", icon: "camera.viewfinder")
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var circularContent: some View {
        actionLink(mode: "text", title: "Ask", icon: "bubble.left.and.text.bubble.right.fill")
            .labelStyle(.iconOnly)
            .font(.system(size: 20, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionLink(mode: String, title: String, icon: String) -> some View {
        Link(destination: WidgetLink.url(mode: mode)) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
            )
        }
    }
}

struct EdgeMindWidget: Widget {
    let kind = "EdgeMindWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EdgeMindProvider()) { _ in
            EdgeMindWidgetEntryView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Edge Mind AI")
        .description("Start a chat, talk, or point the camera — all on device.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

@main
struct EdgeMindWidgetBundle: WidgetBundle {
    var body: some Widget {
        EdgeMindWidget()
    }
}
