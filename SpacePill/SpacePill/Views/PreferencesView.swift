import SwiftUI
import Carbon

struct PreferencesView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var hotKeyManager: GlobalHotKeyManager
    
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
    }
}
