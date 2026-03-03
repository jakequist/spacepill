import SwiftUI
import Carbon

struct PreferencesView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var hotKeyManager: GlobalHotKeyManager
    
    var body: some View {
        VStack(spacing: 20) {
            Text("SpacePill Preferences")
                .font(.largeTitle)
                .padding(.top)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Hotkeys")
                    .font(.headline)
                
                HStack {
                    Text("Quick Edit Space:")
                        .frame(width: 150, alignment: .trailing)
                    HotKeyRecorderView(hotkey: $settingsManager.quickEditHotKey)
                }
                
                if settingsManager.isQuickSwitchEnabled {
                    HStack {
                        Text("Quick Switch Bar:")
                            .frame(width: 150, alignment: .trailing)
                        HotKeyRecorderView(hotkey: $settingsManager.quickSwitchHotKey)
                    }
                }
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 15) {
                Text("General")
                    .font(.headline)
                
                Toggle("Launch at Login", isOn: $settingsManager.launchAtLogin)
                    .toggleStyle(.checkbox)
                
                Toggle("Enable Quick Switch Bar", isOn: $settingsManager.isQuickSwitchEnabled)
                    .toggleStyle(.checkbox)
                
                Text("Note: Switching spaces requires Accessibility permissions to simulate keyboard shortcuts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
                
                Button("Reset All Space Labels & Colors") {
                    settingsManager.resetAll()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            HStack {
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
        }
        .padding()
        .frame(width: 480)
    }
}
