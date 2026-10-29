import SwiftUI
import UIKit

/// Shown full screen while armed. Always dark, warm and dim.
struct BedtimeView: View {
    @Environment(NightEngine.self) private var engine
    @State private var dimmed = false
    @State private var lastTouch = Date()
    @State private var savedBrightness: CGFloat?
    @State private var confirmDiscard = false
    var onHide: () -> Void = {}

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ZStack {
                Color.black.ignoresSafeArea()
                if engine.phase == .alarm { alarmContent(ctx.date) } else { listeningContent(ctx.date) }
            }
            .onChange(of: ctx.date) { _, now in
                if !dimmed && engine.phase != .alarm && now.timeIntervalSince(lastTouch) > 60 { dim(true) }
            }
        }
        .foregroundStyle(Color.nightInk)
        .contentShape(Rectangle())
        .onTapGesture { wake() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onDisappear { dim(false) }
        .onChange(of: engine.phase) { _, p in if p == .alarm { dim(false) } }
        .confirmationDialog("Discard tonight?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Stop and discard", role: .destructive) { engine.discardTonight() }
        } message: {
            Text("Nothing from tonight will be saved.")
        }
    }

    // MARK: Listening

    private func listeningContent(_ now: Date) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { dim(false); onHide() } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Hide bedtime screen; listening continues")
                Spacer()
            }
            .padding(.horizontal, 16)
            Dusk(pose: engine.phase == .awake && engine.lightsOut != nil ? .nudge : .sleep, size: 104)
                .opacity(0.92)
                .id(engine.phase)
                .transition(.opacity)
            Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.headline.weight(.medium))
                .foregroundStyle(Color.nightQuiet)
            Text(now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.system(size: 96, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            HStack(spacing: 10) {
                ListeningBars(level: engine.liveDB, active: engine.micActive)
                Text(statusText).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Color.nightCard, in: Capsule())
            .padding(.top, 26)

            Text(hintText)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.nightQuiet)
                .padding(.horizontal, 48)
                .padding(.top, 20)

            if let t = engine.alarmTarget, let ws = engine.alarmWindowStart {
                HStack {
                    Image(systemName: "alarm")
                    Text("Smart alarm")
                    Spacer()
                    Text(ws == t ? t.shortTime : "\(ws.shortTime) – \(t.shortTime)").foregroundStyle(Color.nightQuiet)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.nightCard, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 32)
                .padding(.top, 36)
            }

            Spacer()

            HStack(spacing: 10) {
                if engine.lightsOut == nil {
                    Button {
                        engine.goingToSleep()
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        dim(true)
                    } label: {
                        Label("I'm going to sleep", systemImage: "moon.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.nightButton, in: Capsule())
                            .foregroundStyle(Color.black)
                    }
                } else if let lo = engine.lightsOut {
                    Text("Lights out at \(lo.shortTime). Sleep well.")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.nightCard, in: Capsule())
                }
                Menu {
                    Button { engine.pauseForTonight() } label: { Label("Pause for tonight", systemImage: "pause.fill") }
                    Button { engine.endNight(reason: .userWokeUp) } label: { Label("I'm up, end the night", systemImage: "sun.max") }
                    Button(role: .destructive) { confirmDiscard = true } label: { Label("Stop and discard tonight", systemImage: "xmark") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .background(Color.nightCard, in: Circle())
                }
                .accessibilityLabel("More options")
            }
            .padding(.horizontal, 32)

            Text("No audio leaves this iPhone.")
                .font(.footnote)
                .foregroundStyle(Color.nightQuiet)
                .padding(.top, 14)
                .padding(.bottom, 30)
        }
        .opacity(dimmed ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.6), value: dimmed)
    }

    private var statusText: String {
        switch engine.phase {
        case .asleep: "Listening · asleep"
        case .awake: "Listening · awake"
        default: "Listening · waiting for sleep"
        }
    }

    private var hintText: String {
        if engine.phase == .awake { return "Up for a moment? Put the phone back down and \(AppInfo.name) keeps going." }
        if engine.lightsOut != nil { return "Put your phone down. \(AppInfo.name) will notice when you fall asleep." }
        return "Tap I'm going to sleep when you're ready, or just put your phone down."
    }

    // MARK: Alarm

    private func alarmContent(_ now: Date) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Dusk(pose: .awake, size: 160)
            Text("Good morning").font(.largeTitle.bold())
            Text(now.formatted(date: .omitted, time: .shortened)).font(.rounded(44, .light))
            Spacer()
            Button {
                engine.endNight(reason: .alarmDismissed)
            } label: {
                Text("I'm awake").font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Color.nightButton, in: Capsule())
                    .foregroundStyle(Color.black)
            }
            Button { engine.snoozeAlarm() } label: {
                Text("Snooze 9 minutes").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.nightCard, in: Capsule())
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 32)
    }

    // MARK: Dimming

    private func wake() {
        lastTouch = Date()
        if dimmed { dim(false) }
    }

    private func dim(_ on: Bool) {
        guard let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen else { return }
        if on {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 0.02
        } else if let b = savedBrightness {
            screen.brightness = b
            savedBrightness = nil
        }
        dimmed = on
        if !on { lastTouch = Date() }
    }
}

/// Six bars that follow the room's loudness.
struct ListeningBars: View {
    let level: Double
    let active: Bool
    private let shape: [Double] = [0.3, 0.7, 1, 0.5, 0.8, 0.3]

    var body: some View {
        let norm = active ? min(1, max(0.15, (level - 25) / 35)) : 0.15
        HStack(spacing: 3) {
            ForEach(0..<shape.count, id: \.self) { i in
                Capsule()
                    .fill(Color.nightButton)
                    .frame(width: 3, height: 4 + 14 * shape[i] * norm)
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.4), value: norm)
        .accessibilityHidden(true)
    }
}
