import Foundation

struct Highlight: Identifiable {
    enum Kind { case regular, snoring, debt, short, talking, latency, great }
    let kind: Kind
    let title: String
    let body: String
    var clip: String? = nil
    var id: String { title }
}

/// Plain-language sentences for the Summary and the report. Written from rules, on the device.
enum Story {
    static func line(session s: SleepSession, analysis a: NightAnalysis, usualSleep: Int?) -> String {
        var parts: [String] = []
        let lat = a.latency
        let fell = lat <= 2 ? "You fell asleep almost straight away" : "You fell asleep in \(lat) minutes"
        if let usual = usualSleep {
            let diff = s.totalSleepMinutes - usual
            if abs(diff) < 10 {
                parts.append("\(fell) and slept about as long as usual.")
            } else {
                parts.append("\(fell) and slept \(abs(diff)) minutes \(diff > 0 ? "longer" : "less") than usual.")
            }
        } else {
            parts.append("\(fell) and slept \(hm(s.totalSleepMinutes)).")
        }
        let wakes = s.events.filter { $0.kind == .awake }
        switch wakes.count {
        case 0: parts.append("No wake-ups worth mentioning.")
        case 1:
            let w = wakes[0]
            parts.append("One short wake at \(w.start.shortTime)\(w.phoneUsed ? ", when you checked your phone" : "").")
        default:
            let late = wakes.filter { Calendar.current.component(.hour, from: $0.start) >= 4 && Calendar.current.component(.hour, from: $0.start) < 12 }
            parts.append(late.count == wakes.count ? "You woke \(wakes.count) times, all after 4 AM." : "You woke \(wakes.count) times during the night.")
        }
        return parts.joined(separator: " ")
    }

    static func highlights(session s: SleepSession, analysis a: NightAnalysis, recent: [SleepSession], need: Int) -> [Highlight] {
        var out: [Highlight] = []
        let all = [s] + recent

        let streak = Regularity.steadyStreak(nights: all)
        if streak >= 3 {
            out.append(Highlight(kind: .regular, title: "Regular schedule",
                                 body: "Your bedtime stayed within 20 minutes for \(streak) nights in a row."))
        }

        let snores = s.events.filter { $0.kind == .snoring }
        if s.snoreMinutes >= 5 {
            let clips = s.events.compactMap(\.clipFile).filter { ClipStore.exists($0) && $0.hasPrefix("snoring") }
            let hours = snores.map { Calendar.current.component(.hour, from: $0.start) }
            let window = hours.isEmpty ? "" : (hours.min() == hours.max() ? ", around \(hourText(hours[0]))" : ", mostly between \(hourText(hours.min()!)) and \(hourText(hours.max()! + 1))")
            out.append(Highlight(kind: .snoring, title: "Snoring",
                                 body: "\(s.snoreMinutes) minutes\(window).\(clips.isEmpty ? "" : " \(clips.count) clip\(clips.count == 1 ? "" : "s") saved.")",
                                 clip: clips.first))
        }

        if let talk = s.events.first(where: { $0.kind == .talking }) {
            out.append(Highlight(kind: .talking, title: "Sleep talk",
                                 body: "You said something at \(talk.start.shortTime).\(ClipStore.exists(talk.clipFile) ? " Want to hear it?" : "")",
                                 clip: ClipStore.exists(talk.clipFile) ? talk.clipFile : nil))
        }

        let debt = Regularity.debtMinutes(nights: all, need: need)
        if debt >= 30 {
            let usualBed = all.map { ($0.lightsOut ?? $0.start).minutesFromEvening }.median ?? 300
            let earlier = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now)!
                .addingTimeInterval((usualBed - Double(min(debt, 45))) * 60)
            out.append(Highlight(kind: .debt, title: "Sleep debt",
                                 body: "\(hm(debt)) short over the last 14 nights. Going to bed by \(earlier.shortTime) tonight pays some of it back."))
        }

        if a.latency > 30 {
            out.append(Highlight(kind: .latency, title: "Slow to fall asleep",
                                 body: "It took \(a.latency) minutes. A dim, screen-free half hour before bed usually helps."))
        }

        if out.isEmpty && a.score.total >= 85 {
            out.append(Highlight(kind: .great, title: "A solid night",
                                 body: "Long, steady and on time. Nothing to fix tonight."))
        }
        return out
    }

    private static func hourText(_ h: Int) -> String {
        let hh = ((h % 24) + 24) % 24
        let twelve = hh % 12 == 0 ? 12 : hh % 12
        return "\(twelve) \(hh < 12 ? "AM" : "PM")"
    }
}
