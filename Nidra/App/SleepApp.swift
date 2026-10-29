import SwiftUI
import SwiftData
import UserNotifications

@main
struct SleepApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
        NightEngine.shared.container = container
    }

    /// Opens the night store. If an older version's store can't be opened (its format changed),
    /// it is moved aside to Application Support/OldNights rather than crashing or being deleted.
    private static func makeContainer() -> ModelContainer {
        if let c = try? ModelContainer(for: SleepSession.self) { return c }
        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = support.appendingPathComponent("OldNights", isDirectory: true)
            try? fm.createDirectory(at: old, withIntermediateDirectories: true)
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                let src = support.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = old.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(name)")
                try? fm.moveItem(at: src, to: dst)
            }
        }
        if let c = try? ModelContainer(for: SleepSession.self) { return c }
        return try! ModelContainer(for: SleepSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(NightEngine.shared)
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(NightEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var hideBedtime = false
    @State private var report: SleepSession?

    var body: some View {
        TabView {
            Tab("Summary", systemImage: "moon.fill") { SummaryView() }
            Tab("Nights", systemImage: "list.bullet") { NightsView() }
            Tab("Trends", systemImage: "chart.bar.fill") { TrendsView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
        .tint(.accentSleep)
        .safeAreaInset(edge: .top) {
            if engine.isArmed && hideBedtime {
                Button { hideBedtime = false } label: {
                    Label("Listening · tap to return", systemImage: "waveform")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { engine.isArmed && !hideBedtime }, set: { if !$0 { hideBedtime = true } })) {
            BedtimeView(onHide: { hideBedtime = true })
                .environment(engine)
        }
        .sheet(item: $report) { s in
            NavigationStack {
                NightReportView(session: s)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { report = nil } } }
            }
        }
        .alert("Heads up", isPresented: Binding(get: { engine.lastMessage != nil }, set: { if !$0 { engine.lastMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(engine.lastMessage ?? "")
        }
        .onChange(of: engine.justFinished) { _, id in
            guard let id else { return }
            engine.justFinished = nil
            // Let the bedtime screen finish closing before the report slides up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                report = try? context.fetch(FetchDescriptor<SleepSession>(predicate: #Predicate { $0.id == id })).first
            }
        }
        .onChange(of: engine.isArmed) { _, armed in if armed { hideBedtime = false } }
        .onChange(of: scenePhase) { _, p in engine.appIsActive = (p == .active) }
        .onOpenURL { url in
            if url.host == "bedtime" { hideBedtime = false }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Notifier.registerCategories()
        let d = UserDefaults.standard
        Notifier.scheduleBedtime(enabled: d.object(forKey: "bedtimeReminder") as? Bool ?? true,
                                 secondsAfterMidnight: d.object(forKey: "bedtimeSeconds") as? Double ?? 22.75 * 3600)
        ClipStore.prune()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        await MainActor.run {
            let engine = NightEngine.shared
            switch (category, action) {
            case (Notifier.Category.bedtime, Notifier.Action.startListening),
                 (Notifier.Category.bedtime, UNNotificationDefaultActionIdentifier):
                Task { await engine.arm() }
            case (_, Notifier.Action.sleepingNow): engine.snoozeNudges()
            case (_, Notifier.Action.snooze): engine.snoozeNudges()
            case (_, Notifier.Action.upForReason): engine.upForAReason()
            default: break
            }
        }
    }
}
