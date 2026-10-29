import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct SleepWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ListeningLiveActivity()
    }
}

struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.fill").foregroundStyle(Self.cyan)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(Self.title(context.state.phase)).font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(Self.subtitle(context)).font(.footnote).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "moon.fill").foregroundStyle(Self.cyan)
            } compactTrailing: {
                Image(systemName: "waveform").foregroundStyle(Self.cyan)
            } minimal: {
                Image(systemName: "moon.fill").foregroundStyle(Self.cyan)
            }
            .widgetURL(URL(string: "halcyon://bedtime"))
        }
    }

    static let cyan = Color(red: 0.56, green: 0.85, blue: 1)
    static let warm = Color(red: 0.914, green: 0.725, blue: 0.541)

    static func title(_ phase: String) -> String {
        switch phase {
        case "asleep": "Asleep · listening"
        case "awake": "Awake · still listening"
        case "alarm": "Good morning"
        default: "Listening for sleep"
        }
    }

    static func subtitle(_ c: ActivityViewContext<ListeningAttributes>) -> String {
        var s = "Since \(c.attributes.startedAt.formatted(date: .omitted, time: .shortened))"
        if let a = c.attributes.alarmStart, let b = c.attributes.alarmEnd {
            s += " · alarm \(a.formatted(date: .omitted, time: .shortened))–\(b.formatted(date: .omitted, time: .shortened))"
        }
        return s
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ListeningAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(context.state.phase == "alarm" ? "DuskAwake" : "DuskSleep")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .accessibilityLabel("Dusk the nightjar")
                VStack(alignment: .leading, spacing: 1) {
                    Text(ListeningLiveActivity.title(context.state.phase)).font(.headline)
                    Text(ListeningLiveActivity.subtitle(context)).font(.footnote).foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 0)
                Image(systemName: "waveform").foregroundStyle(ListeningLiveActivity.cyan)
            }
            HStack(spacing: 10) {
                if context.state.phase == "alarm" || context.state.phase == "awake" {
                    Button(intent: ImUpIntent()) {
                        Text("I'm up").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .tint(ListeningLiveActivity.warm)
                } else if let lo = context.state.lightsOut {
                    Text("Lights out at \(lo.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(.white.opacity(0.16), in: Capsule())
                } else {
                    Button(intent: GoingToSleepIntent()) {
                        Text("I'm going to sleep").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .tint(ListeningLiveActivity.warm)
                }
                Link(destination: URL(string: "halcyon://bedtime")!) {
                    Text("More").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(minHeight: 36)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .foregroundStyle(.white)
        }
        .padding(16)
    }
}
