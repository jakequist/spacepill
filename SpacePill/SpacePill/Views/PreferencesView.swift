import SwiftUI
import Carbon

struct PreferencesView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var hotKeyManager: GlobalHotKeyManager

    /// Re-read on appear so enabling a shortcut in System Settings clears the
    /// warning without restarting SpacePill.
    @State private var hasDesktopShortcuts = SpaceShortcuts.hasAnyShortcuts

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    // Hotkeys Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hotkeys")
                            .font(.headline)
                        
                        GroupBox {
                            VStack(spacing: 10) {
                                LabeledContent("Quick Edit Space:") {
                                    HotKeyRecorderView(hotkey: $settingsManager.quickEditHotKey)
                                }
                                
                                if settingsManager.isQuickSwitchEnabled {
                                    LabeledContent("Quick Switch Bar:") {
                                        HotKeyRecorderView(hotkey: $settingsManager.quickSwitchHotKey)
                                    }
                                }
                                
                                if settingsManager.isNotesEnabled {
                                    LabeledContent("Space Notes:") {
                                        HotKeyRecorderView(hotkey: $settingsManager.notesHotKey)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                    
                    // General Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("General")
                            .font(.headline)
                        
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Launch at Login", isOn: $settingsManager.launchAtLogin)
                                
                                Toggle("Enable Quick Switch Bar", isOn: $settingsManager.isQuickSwitchEnabled)
                                
                                Toggle("Enable Space Notes", isOn: $settingsManager.isNotesEnabled)
                                
                                if settingsManager.isNotesEnabled {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Toggle("Match Space Color for Notes Border", isOn: $settingsManager.matchSpaceColorForNotesBorder)
                                            .padding(.leading, 20)
                                        
                                        HStack {
                                            Text("Max Notes Height:")
                                                .padding(.leading, 20)
                                            Slider(value: $settingsManager.maxNotesHeight, in: 100...800, step: 50)
                                            Text("\(Int(settingsManager.maxNotesHeight))px")
                                                .font(.system(.body, design: .monospaced))
                                                .frame(width: 60, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // Permissions & Maintenance
                    VStack(alignment: .leading, spacing: 12) {
                        // Switching works by replaying the user's own "Switch to
                        // Desktop N" shortcuts, which macOS ships disabled. Without
                        // them the Quick Switch Bar silently does nothing, so say so
                        // rather than letting it look broken.
                        if settingsManager.isQuickSwitchEnabled && !hasDesktopShortcuts {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Quick Switch can't change Spaces yet", systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.orange)

                                    Text("macOS has no API for switching Spaces, so SpacePill replays your “Switch to Desktop” shortcuts — and those are turned off by default.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Button("Open Keyboard Shortcuts…") {
                                        NSWorkspace.shared.open(
                                            URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
                                        )
                                    }
                                    .buttonStyle(.bordered)

                                    Text("Enable Mission Control → “Switch to Desktop 1…N”, then reopen the Quick Switch Bar.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Text("Note: Switching spaces requires Accessibility permissions to simulate keyboard shortcuts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Reset All Space Labels & Colors") {
                            settingsManager.resetAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(30)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Close") {
                    if let window = NSApp.keyWindow {
                        window.close()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .padding()
            }
            .background(VisualEffectView(material: .contentBackground, blendingMode: .withinWindow))
        }
        .frame(width: 550, height: 600)
        .onAppear(perform: refreshDesktopShortcuts)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            // Catches the common flow: open Keyboard Shortcuts, enable one,
            // switch back here.
            refreshDesktopShortcuts()
        }
    }

    private func refreshDesktopShortcuts() {
        SpaceShortcuts.refresh()
        hasDesktopShortcuts = SpaceShortcuts.hasAnyShortcuts
    }
}
