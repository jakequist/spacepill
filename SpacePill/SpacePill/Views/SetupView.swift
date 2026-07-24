import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid

/**
 * A snapshot of everything the Setup window reports.
 *
 * Read once into `@State` and re-read on demand. `SpaceShortcuts` is a plain
 * static cache with no `objectWillChange`, so querying it from inside a SwiftUI
 * `body` would render whatever was cached at first draw and never update --
 * exactly the bug this struct exists to avoid. Same reasoning for the SkyLight
 * space list, which is also main-queue-only.
 *
 * These are the same checks `spacepill doctor` performs, deliberately: two
 * places that disagree about whether SpacePill is set up correctly are worse
 * than one.
 */
struct SetupChecks {
    var isAccessibilityGranted = false
    var isInputMonitoringGranted = false
    var enabledDesktops: [Int] = []
    var spaceCount = 0
    var reachableSpaceCount = 0

    /// Desktops macOS defines a "Switch to Desktop N" shortcut for at all.
    let maxDesktop = SpaceShortcuts.maxDesktop

    var missingDesktops: [Int] {
        (1...maxDesktop).filter { !enabledDesktops.contains($0) }
    }

    /**
     * Runs every check. Main queue only: SkyLight and the TCC lookups both
     * expect it.
     */
    static func current() -> SetupChecks {
        // Cached until asked; without this the window would show the state as
        // of launch and never notice a shortcut enabled a moment ago.
        SpaceShortcuts.refresh()

        let reachable = SpaceShortcuts.reachableDesktops()
        let spaces = SkyLight.getAllSpacesMetadata()

        return SetupChecks(
            isAccessibilityGranted: AXIsProcessTrusted(),
            isInputMonitoringGranted: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
            enabledDesktops: reachable.sorted(),
            spaceCount: spaces.count,
            reachableSpaceCount: spaces.filter { reachable.contains($0.index) }.count
        )
    }
}

/**
 * First-run guidance, and the place to come back to when something stops
 * working.
 *
 * Two silent failures account for almost every "SpacePill does nothing" report,
 * and neither is visible from the menu bar:
 *
 *  1. macOS ships the "Switch to Desktop N" shortcuts **disabled**, and there is
 *     no API for activating a Space, so with none enabled nothing can be
 *     switched to.
 *  2. Quick Switch and Space Notes both default to off, so their hotkeys do
 *     nothing on a fresh install.
 *
 * Shown once automatically on a genuinely fresh install (see
 * `SettingsManager.isFirstLaunch`) and afterwards only when asked for, from the
 * status bar menu. The tone is deliberately factual: none of this is broken,
 * some of it is just not switched on yet.
 */
struct SetupView: View {
    @ObservedObject var settingsManager: SettingsManager

    /// Seeded so the first render is already correct, then refreshed whenever
    /// the window comes back to the front.
    @State private var checks = SetupChecks.current()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    section("Permissions") {
                        accessibilityRow
                        Divider()
                        inputMonitoringRow
                    }

                    section("Switching Spaces") {
                        shortcutsRow
                    }

                    section("Features") {
                        quickSwitchRow
                        Divider()
                        notesRow
                    }
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 12) {
                // In the footer rather than the scroll area: it is the one-line
                // answer to "is this working", and it should never be scrolled
                // out of sight.
                summary
                Spacer()
                Button("Re-check") { refresh() }
                    .buttonStyle(.bordered)
                Button("Done") {
                    if let window = NSApp.keyWindow {
                        window.close()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
            .background(VisualEffectView(material: .contentBackground, blendingMode: .withinWindow))
        }
        .frame(width: 550, height: 700)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            // The whole point: fix something in System Settings, come back, and
            // watch it turn green without restarting SpacePill.
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification
        )) { _ in
            refresh()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setting up SpacePill")
                .font(.title2.weight(.semibold))
            Text("Everything SpacePill needs, re-checked each time you come back to this window.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityRow: some View {
        SetupRow(
            status: checks.isAccessibilityGranted ? .ok : .attention,
            title: "Accessibility permission",
            detail: checks.isAccessibilityGranted
                ? "Granted. SpacePill can post the keystrokes that switch Spaces."
                : "Switching a Space means posting a keystroke, and macOS requires this permission to allow it. Without it, Quick Switch and `spacepill switch` do nothing."
        ) {
            if !checks.isAccessibilityGranted {
                Button("Open Accessibility Settings…") {
                    // Prompting registers SpacePill in the list; a user who has
                    // never been asked will not find it there otherwise.
                    _ = AXIsProcessTrustedWithOptions(
                        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    )
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var inputMonitoringRow: some View {
        SetupRow(
            status: checks.isInputMonitoringGranted ? .ok : .optional,
            title: "Input Monitoring permission (optional)",
            detail: checks.isInputMonitoringGranted
                ? "Granted. The menu bar pill updates the instant you change Space."
                : "Not granted, and nothing depends on it. It only affects responsiveness: without it the pill lags about half a second behind Ctrl+Arrow switches. Everything else works the same."
        ) {
            if !checks.isInputMonitoringGranted {
                Button("Open Input Monitoring Settings…") {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var shortcutsRow: some View {
        SetupRow(
            status: checks.enabledDesktops.isEmpty ? .attention : .ok,
            title: shortcutsTitle,
            detail: shortcutsDetail
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Open Keyboard Shortcuts…") {
                    open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
                }
                .buttonStyle(.bordered)

                Text("Keyboard Shortcuts… → Mission Control, then tick “Switch to Desktop 1”, “Switch to Desktop 2”, and so on. macOS defines only Desktops 1–\(checks.maxDesktop); anything past that is unreachable by design.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shortcutsTitle: String {
        if checks.enabledDesktops.isEmpty {
            return "“Switch to Desktop N” shortcuts: none enabled"
        }
        let list = checks.enabledDesktops.map(String.init).joined(separator: ", ")
        return "“Switch to Desktop N” shortcuts enabled for Desktop \(list)"
    }

    private var shortcutsDetail: String {
        guard !checks.enabledDesktops.isEmpty else {
            return "macOS ships these turned off, which is the single most common reason SpacePill appears to do nothing. There is no API for activating a Space — SpacePill replays the shortcut you have bound, so with none bound there is nothing to replay."
        }
        let missing = checks.missingDesktops
        guard !missing.isEmpty else {
            return "Every desktop macOS can address is reachable."
        }
        return "Not enabled: \(missing.map(String.init).joined(separator: ", ")). Those Spaces show greyed out in Quick Switch until you tick them."
    }

    private var quickSwitchRow: some View {
        SetupRow(
            status: settingsManager.isQuickSwitchEnabled ? .ok : .attention,
            title: "Quick Switch bar",
            detail: settingsManager.isQuickSwitchEnabled
                ? "On. Press \(settingsManager.quickSwitchHotKey.displayString) to search your Spaces by name or number."
                : "Off, so \(settingsManager.quickSwitchHotKey.displayString) does nothing. Turn it on to search your Spaces by name or number.",
            placement: .trailing
        ) {
            Toggle("Enable Quick Switch", isOn: $settingsManager.isQuickSwitchEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var notesRow: some View {
        SetupRow(
            status: settingsManager.isNotesEnabled ? .ok : .attention,
            title: "Space Notes",
            detail: settingsManager.isNotesEnabled
                ? "On. Press \(settingsManager.notesHotKey.displayString) for a notes panel that follows the Space you are on."
                : "Off, so \(settingsManager.notesHotKey.displayString) does nothing. Turn it on for a notes panel that follows the Space you are on.",
            placement: .trailing
        ) {
            Toggle("Enable Space Notes", isOn: $settingsManager.isNotesEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Image(systemName: checks.reachableSpaceCount > 0 ? "rectangle.3.group" : "exclamationmark.triangle.fill")
                .foregroundColor(checks.reachableSpaceCount > 0 ? .secondary : .orange)
            Text("\(checks.spaceCount) Space\(checks.spaceCount == 1 ? "" : "s"), \(checks.reachableSpaceCount) reachable")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        checks = SetupChecks.current()
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            Log.ui.error("Setup could not build a System Settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/**
 * One check: an icon, what it is, what it means, and whatever fixes it.
 *
 * `optional` is its own state on purpose -- an ungranted Input Monitoring is not
 * a failure, and painting it orange would push people into granting a permission
 * they do not need.
 */
private struct SetupRow<Accessory: View>: View {
    enum Status {
        case ok
        case attention
        case optional

        var symbol: String {
            switch self {
            case .ok:        return "checkmark.circle.fill"
            case .attention: return "exclamationmark.triangle.fill"
            case .optional:  return "minus.circle"
            }
        }

        var tint: Color {
            switch self {
            case .ok:        return .green
            case .attention: return .orange
            case .optional:  return .secondary
            }
        }
    }

    /// Buttons and their explanations read better under the text they act on;
    /// a lone toggle reads better beside it.
    enum Placement {
        case below
        case trailing
    }

    let status: Status
    let title: String
    let detail: String
    var placement: Placement = .below
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.symbol)
                .foregroundColor(status.tint)
                .font(.system(size: 14))
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if placement == .below {
                    accessory()
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            if placement == .trailing {
                accessory()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
