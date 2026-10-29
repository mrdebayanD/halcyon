import Foundation
import ActivityKit
import AppIntents

/// Shared by the app and the widget extension: the Lock Screen "Listening" notice.
struct ListeningAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "waiting", "asleep", "awake", "alarm"
        var phase: String
        var lightsOut: Date?
        var since: Date
    }

    var startedAt: Date
    var alarmStart: Date?
    var alarmEnd: Date?
}

/// "I'm going to sleep" from the Lock Screen. Runs inside the app process.
struct GoingToSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "I'm going to sleep"
    static var description = IntentDescription("Marks lights-out for tonight.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { NightEngine.shared.goingToSleep() }
        #endif
        return .result()
    }
}

/// "I'm up" from the Lock Screen when the alarm rings or in the morning.
struct ImUpIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "I'm up"
    static var description = IntentDescription("Ends tonight's tracking.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { NightEngine.shared.endNight(reason: .userWokeUp) }
        #endif
        return .result()
    }
}
