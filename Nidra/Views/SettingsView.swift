import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [SleepSession]

    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("sleepNeed") private var need = 480
    @AppStorage("bedtimeReminder") private var bedtimeOn = true
    @AppStorage("bedtimeSeconds") private var bedtimeSeconds: Double = 22.75 * 3600
    @AppStorage("listeningNotice") private var noticeOn = true
    @AppStorage("nudges") private var nudgesOn = true
    @AppStorage("stayArmed") private var stayArmed = false
    @AppStorage("alarmEnabled") private var alarmOn = true
    @AppStorage("alarmSeconds") private var alarmSeconds: Double = 7 * 3600
    @AppStorage("alarmWindow") private var alarmWindow = 30
    @AppStorage("clipsEnabled") private var clipsOn = true
    @AppStorage("saveToHealth") private var saveToHealth = false

    @State private var status: String?
    @State private var importing = false
    @State private var confirmDelete = false

    private func timeBinding(_ seconds: Binding<Double>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(seconds.wrappedValue) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                seconds.wrappedValue = Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60)
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.card)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your iPhone's Light and Dark setting. The bedtime screen always stays dark.")
                }

                Section {
                    Toggle("Bedtime reminder", isOn: $bedtimeOn)
                    if bedtimeOn {
                        DatePicker("Remind me at", selection: timeBinding($bedtimeSeconds), displayedComponents: .hourAndMinute)
                    }
                    Toggle("Listening notice on Lock Screen", isOn: $noticeOn)
                    Toggle("Late-night nudges", isOn: $nudgesOn)
                    Toggle("Stay armed all day", isOn: $stayArmed)
                } header: {
                    Text("Bedtime and listening")
                } footer: {
                    Text("Tap the reminder to start listening; iOS only lets an open app turn the microphone on. Stay armed keeps the mic on so you never need to tap, but shows the orange dot all day and uses more battery.")
                }

                Section("Smart alarm") {
                    Toggle("Wake me gently", isOn: $alarmOn)
                    if alarmOn {
                        DatePicker("Latest wake-up", selection: timeBinding($alarmSeconds), displayedComponents: .hourAndMinute)
                        Picker("Window", selection: $alarmWindow) {
                            ForEach([0, 10, 20, 30, 45], id: \.self) { Text($0 == 0 ? "Exact time" : "\($0) minutes").tag($0) }
                        }
                    }
                }

                Section("Sleep need") {
                    Stepper(value: $need, in: 360...660, step: 15) {
                        LabeledContent("Each night", value: hm(need))
                    }
                }

                Section {
                    Toggle("Save sound clips", isOn: $clipsOn)
                    LabeledContent("Kept for", value: "30 days")
                } header: {
                    Text("Recordings")
                } footer: {
                    Text("Short clips of snoring, sleep talk and coughs. Audio is analysed on this iPhone and never sent anywhere.")
                }

                Section {
                    Toggle("Save nights to Apple Health", isOn: $saveToHealth)
                    Button {
                        importing = true
                        Task { @MainActor in
                            do {
                                let n = try await HealthImporter.importRecentNights(days: 30, context: context, need: need)
                                status = n == 0 ? "No new Apple Watch nights found." : "Imported \(n) night\(n == 1 ? "" : "s")."
                            } catch { status = error.localizedDescription }
                            importing = false
                        }
                    } label: {
                        HStack { Text("Import Apple Watch nights"); Spacer(); if importing { ProgressView() } }
                    }
                    .disabled(importing)
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Apple Health")
                }

                Section {
                    Button("Add 14 sample nights") { DemoData.generate(nights: 14, context: context, need: need); status = "Added 14 sample nights." }
                    Button("Delete all data…", role: .destructive) { confirmDelete = true }
                } header: {
                    Text("Data")
                } footer: {
                    Text("\(sessions.count) nights stored on this iPhone. Nothing leaves your device.")
                }

                Section {
                    HStack(spacing: 14) {
                        Dusk(pose: .awake, size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(AppInfo.name) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.headline)
                            Text("Free and open source. Your nights stay on this iPhone and in Apple Health.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Link(destination: URL(string: "https://github.com/mrdebayanD/halcyon/issues/new/choose")!) {
                        Label("Send feedback or report a bug", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    Link(destination: URL(string: "https://github.com/mrdebayanD/halcyon")!) {
                        Label("Halcyon on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Feedback goes to GitHub Issues. Don't paste anything you'd rather keep private; your sleep data never leaves this iPhone unless you share it.")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: bedtimeOn) { _, _ in reschedule() }
            .onChange(of: bedtimeSeconds) { _, _ in reschedule() }
            .confirmationDialog("Delete every night and clip?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    try? context.delete(model: SleepSession.self)
                    try? context.save()
                    ClipStore.deleteAll()
                    status = "All data deleted."
                }
            }
        }
    }

    private func reschedule() { Notifier.scheduleBedtime(enabled: bedtimeOn, secondsAfterMidnight: bedtimeSeconds) }
}
