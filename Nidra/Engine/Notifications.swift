import Foundation
import UserNotifications
import UIKit

/// Local notifications only. Nothing is pushed from a server.
enum Notifier {
    static let bedtimeID = "sleep.bedtime"
    static let alarmBackupID = "sleep.alarm.backup"

    enum Category {
        static let bedtime = "BEDTIME"
        static let nudge = "NUDGE"
        static let report = "REPORT"
    }

    enum Action {
        static let startListening = "START_LISTENING"
        static let sleepingNow = "SLEEPING_NOW"
        static let snooze = "NUDGE_SNOOZE"
        static let upForReason = "UP_FOR_REASON"
    }

    static func registerCategories() {
        let start = UNNotificationAction(identifier: Action.startListening, title: "Start listening", options: [.foreground])
        let bedtime = UNNotificationCategory(identifier: Category.bedtime, actions: [start], intentIdentifiers: [])

        let sleeping = UNNotificationAction(identifier: Action.sleepingNow, title: "Okay, sleeping now",
                                            options: [], icon: UNNotificationActionIcon(systemImageName: "moon.fill"))
        let snooze = UNNotificationAction(identifier: Action.snooze, title: "Give me 15 minutes",
                                          options: [], icon: UNNotificationActionIcon(systemImageName: "clock"))
        let reason = UNNotificationAction(identifier: Action.upForReason, title: "I'm up for a reason",
                                          options: [], icon: UNNotificationActionIcon(systemImageName: "sun.max"))
        let nudge = UNNotificationCategory(identifier: Category.nudge, actions: [sleeping, snooze, reason], intentIdentifiers: [])
        let report = UNNotificationCategory(identifier: Category.report, actions: [], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([bedtime, nudge, report])
    }

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Daily "Ready for bed?" reminder; tapping it opens the app, which is the moment iOS lets us start the mic.
    static func scheduleBedtime(enabled: Bool, secondsAfterMidnight: Double) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [bedtimeID])
        guard enabled else { return }
        let c = UNMutableNotificationContent()
        c.title = "Ready for bed?"
        c.body = "Tap to let \(AppInfo.name) listen tonight. It stops on its own in the morning."
        c.sound = .default
        c.categoryIdentifier = Category.bedtime
        c.interruptionLevel = .timeSensitive
        let s = Int(secondsAfterMidnight)
        var comps = DateComponents()
        comps.hour = (s / 3600) % 24
        comps.minute = (s % 3600) / 60
        center.add(UNNotificationRequest(identifier: bedtimeID, content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }

    private static let nudgeLines: [(String, String)] = [
        ("Weren't you going to sleep?", "You said goodnight %d minutes ago. Everything on here will still be here tomorrow. Tonight's sleep won't wait."),
        ("Psst. It's %@.", "The internet is open 24/7. Your best sleep isn't. Put it down, you'll thank yourself at breakfast."),
        ("Still scrolling?", "Nothing on here is going anywhere. Catch up tomorrow, rested and a lot less grumpy."),
        ("Your pillow misses you", "%d minutes since lights-out. Future you would like a word about this."),
        ("One more video?", "That's what they all say. Sleep now and tomorrow-you gets the good mood."),
    ]

    static func sendNudge(minutesSinceLightsOut: Int, index: Int) {
        let line = nudgeLines[index % nudgeLines.count]
        let c = UNMutableNotificationContent()
        c.title = line.0.contains("%@") ? String(format: line.0, Date().shortTime) : line.0
        c.body = line.1.contains("%d") ? String(format: line.1, minutesSinceLightsOut) : line.1
        c.sound = .default
        c.categoryIdentifier = Category.nudge
        c.interruptionLevel = .timeSensitive
        if let a = mascotAttachment("DuskNudge") { c.attachments = [a] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sleep.nudge.\(UUID().uuidString)",
                                                                     content: c, trigger: nil))
    }

    /// Notification attachments need a file, so the asset is written to a temp PNG first.
    static func mascotAttachment(_ asset: String) -> UNNotificationAttachment? {
        guard let data = UIImage(named: asset)?.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(asset)-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: asset, url: url)
    }

    static func nightReady(score: Int, asleep: Int) {
        let c = UNMutableNotificationContent()
        c.title = "Your night is ready"
        c.body = "\(hm(asleep)) asleep, score \(score). Tap to see what happened."
        c.sound = nil
        c.categoryIdentifier = Category.report
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sleep.report.\(UUID().uuidString)",
                                                                     content: c, trigger: nil))
    }

    static func scheduleAlarmBackup(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [alarmBackupID])
        let c = UNMutableNotificationContent()
        c.title = "Good morning"
        c.body = "Time to wake up."
        c.sound = .default
        c.interruptionLevel = .timeSensitive
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date.addingTimeInterval(60))
        center.add(UNNotificationRequest(identifier: alarmBackupID, content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    static func cancelAlarmBackup() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [alarmBackupID])
    }
}

enum AppInfo {
    /// Display name from the bundle, so a rename needs no code change.
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "Halcyon"
    }
}
