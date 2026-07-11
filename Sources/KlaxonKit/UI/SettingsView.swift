import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    let calendarService: CalendarService
    let onTestAlert: () -> Void

    public init(prefs: Preferences, calendarService: CalendarService,
                onTestAlert: @escaping () -> Void) {
        self.prefs = prefs
        self.calendarService = calendarService
        self.onTestAlert = onTestAlert
    }

    public var body: some View {
        TabView {
            GeneralTab(prefs: prefs, onTestAlert: onTestAlert)
                .tabItem { Label("General", systemImage: "gearshape") }
            CalendarsTab(prefs: prefs, calendarService: calendarService)
                .tabItem { Label("Calendars", systemImage: "calendar") }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General

/// A snooze duration with a stable identity for safe list editing.
private struct SnoozeSlot: Identifiable, Equatable {
    let id = UUID()
    var minutes: Int
}

private struct GeneralTab: View {
    @ObservedObject var prefs: Preferences
    let onTestAlert: () -> Void

    /// Editable mirror of `prefs.snoozeMinutes`, committed back on change.
    @State private var snoozeSlots: [SnoozeSlot] = []

    private let leadOptions: [(String, Double)] = [
        ("At start time", 0), ("1 minute before", 1), ("2 minutes before", 2),
        ("5 minutes before", 5), ("10 minutes before", 10), ("15 minutes before", 15),
    ]

    private var runningFromBundle: Bool { AppInfo.isRunningFromBundle }

    var body: some View {
        Form {
            Section {
                Picker("Show alert:", selection: $prefs.leadTimeMinutes) {
                    ForEach(leadOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }

                Picker("Theme:", selection: $prefs.themeID) {
                    ForEach(Theme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                    Divider()
                    Text("Random").tag(Preferences.randomThemeID)
                    Text("Custom Image…").tag(Preferences.customThemeID)
                }

                if prefs.themeID == Preferences.customThemeID {
                    customImageRow
                }

                HStack {
                    Picker("Sound:", selection: $prefs.soundName) {
                        Text("None").tag("")
                        Divider()
                        ForEach(SoundPlayer.systemSoundNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Button {
                        SoundPlayer.play(prefs.soundName)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .disabled(prefs.soundName.isEmpty)
                    .help("Preview sound")
                }
            }

            Section("Snooze buttons (up to \(Preferences.maxSnoozeButtons))") {
                // Bind over identified slots (stable UUIDs), never array
                // indices: removing a row by index while ForEach iterates it
                // crashes with an out-of-bounds subscript.
                ForEach($snoozeSlots) { $slot in
                    HStack {
                        Stepper(
                            "\(slot.minutes) minute\(slot.minutes == 1 ? "" : "s")",
                            value: $slot.minutes, in: 1...120)
                        Spacer()
                        Button(role: .destructive) {
                            snoozeSlots.removeAll { $0.id == slot.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if snoozeSlots.count < Preferences.maxSnoozeButtons {
                    Button {
                        snoozeSlots.append(SnoozeSlot(minutes: defaultNewSnooze))
                    } label: {
                        Label("Add snooze button", systemImage: "plus.circle")
                    }
                }
                if snoozeSlots.isEmpty {
                    Text("No snooze buttons will be shown on alerts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Pause all alerts", isOn: $prefs.paused)
                Text("⌃⌥P pauses and resumes alerts from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show icon only in menu bar", isOn: $prefs.menuBarIconOnly)
                Text("Hides the next meeting's title and countdown; shows just the menu-bar icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                    .disabled(!runningFromBundle)
                if !runningFromBundle {
                    Text("Available when running from the built app bundle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text("Preview a full-screen alert")
                    Spacer()
                    Button("Test Alert…", action: onTestAlert)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .onAppear {
            snoozeSlots = prefs.snoozeMinutes.map { SnoozeSlot(minutes: $0) }
        }
        .onChange(of: snoozeSlots) {
            let minutes = snoozeSlots.map(\.minutes)
            if minutes != prefs.snoozeMinutes { prefs.snoozeMinutes = minutes }
        }
    }

    // MARK: General helpers

    private var defaultNewSnooze: Int {
        // Suggest a sensible next value beyond the current largest.
        (snoozeSlots.map(\.minutes).max() ?? 0) + 5
    }

    private var customImageRow: some View {
        HStack {
            if !prefs.customBackgroundPath.isEmpty,
               let image = NSImage(contentsOfFile: prefs.customBackgroundPath) {
                Image(nsImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 56, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(customImageLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Choose…", action: chooseCustomImage)
            if !prefs.customBackgroundPath.isEmpty {
                Button("Clear") { prefs.customBackgroundPath = "" }
            }
        }
    }

    private var customImageLabel: String {
        prefs.customBackgroundPath.isEmpty
            ? "No image chosen"
            : (prefs.customBackgroundPath as NSString).lastPathComponent
    }

    private func chooseCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Image"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.customBackgroundPath = url.path
        }
    }
}

// MARK: - Calendars

private struct CalendarsTab: View {
    @ObservedObject var prefs: Preferences
    let calendarService: CalendarService

    @State private var calendars: [CalendarInfo] = []
    @State private var hasAccess = false

    var body: some View {
        Group {
            if hasAccess {
                calendarList
            } else {
                permissionPrompt
            }
        }
        .onAppear(perform: reload)
    }

    private var permissionPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("\(AppInfo.name) needs full calendar access to alert you about meetings.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Grant Access") {
                Task {
                    _ = await calendarService.requestAccess()
                    reload()
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Open System Settings…") {
                let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calendarList: some View {
        Form {
            Section("Alert me about events in:") {
                ForEach(calendars) { calendar in
                    Toggle(isOn: binding(for: calendar.id)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: calendar.colorHex) ?? .secondary)
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                            if !calendar.sourceTitle.isEmpty {
                                Text(calendar.sourceTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Also include:") {
                Toggle("All-day events", isOn: $prefs.includeAllDay)
                Toggle("Events I've declined", isOn: $prefs.includeDeclined)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for calendarID: String) -> Binding<Bool> {
        Binding(
            get: { !prefs.disabledCalendarIDs.contains(calendarID) },
            set: { enabled in
                if enabled {
                    prefs.disabledCalendarIDs.remove(calendarID)
                } else {
                    prefs.disabledCalendarIDs.insert(calendarID)
                }
            })
    }

    private func reload() {
        hasAccess = calendarService.hasAccess
        calendars = calendarService.allCalendars()
    }
}
