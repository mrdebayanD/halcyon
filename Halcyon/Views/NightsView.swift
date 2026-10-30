import SwiftUI
import SwiftData

struct NightsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SleepSession.end, order: .reverse) private var sessions: [SleepSession]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView("No nights yet", systemImage: "moon.stars",
                                           description: Text("Your nights appear here after the first morning."))
                } else {
                    List {
                        ForEach(sessions) { s in
                            NavigationLink(value: s) { NightRow(session: s) }
                        }
                        .onDelete { idx in
                            for i in idx {
                                for c in sessions[i].events.compactMap(\.clipFile) {
                                    try? FileManager.default.removeItem(at: ClipStore.url(c))
                                }
                                context.delete(sessions[i])
                            }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Nights")
            .navigationDestination(for: SleepSession.self) { NightReportView(session: $0) }
        }
    }
}

struct NightRow: View {
    let session: SleepSession

    var body: some View {
        HStack(spacing: 14) {
            Text("\(session.score)")
                .font(.rounded(17))
                .frame(width: 46, height: 46)
                .background(Circle().stroke(Color.accentSleep.opacity(0.35 + Double(session.score) / 160), lineWidth: 3))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(session.end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(hm(session.totalSleepMinutes)).font(.subheadline).monospacedDigit()
                }
                StageBar(deep: session.deepMinutes, light: session.lightMinutes, rem: session.remMinutes,
                         awake: session.awakeMinutes, height: 6)
                Text("\((session.lightsOut ?? session.start).shortTime) – \(session.end.shortTime) · \(session.source.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
