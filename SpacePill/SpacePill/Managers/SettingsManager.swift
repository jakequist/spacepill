import SwiftUI
import Carbon
import ServiceManagement

struct SpaceConfig: Codable {
    var label: String?
    var hexColor: String? 
    
    var color: Color? {
        guard let hex = hexColor else { return nil }
        return Color(hex: hex)
    }
}

struct HotKeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    
    var displayString: String {
        var str = ""
        if modifiers & UInt32(cmdKey) != 0 { str += "⌘" }
        if modifiers & UInt32(shiftKey) != 0 { str += "⇧" }
        if modifiers & UInt32(optionKey) != 0 { str += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { str += "⌃" }
        
        str += keyCodeString(keyCode)
        return str
    }
    
    private func keyCodeString(_ keyCode: UInt32) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key \(keyCode)"
        }
    }
}

/**
 * Handles persistence of space configurations (labels and colors) and app settings.
 */
class SettingsManager: ObservableObject {
    @Published var spaceConfigs: [String: SpaceConfig] = [:]
    @Published var isQuickSwitchEnabled: Bool = false {
        didSet {
            userDefaults.set(isQuickSwitchEnabled, forKey: "isQuickSwitchEnabled")
        }
    }
    
    @Published var launchAtLogin: Bool = false {
        didSet {
            updateLoginItem()
        }
    }
    
    // Default hotkeys: 
    // Quick Edit: Cmd+Shift+S (keyCode 1, mods 0x0100 | 0x0200)
    // Quick Switch: Cmd+Shift+J (keyCode 38, mods 0x0100 | 0x0200)
    @Published var quickEditHotKey: HotKeyConfig {
        didSet {
            saveSettings()
        }
    }
    @Published var quickSwitchHotKey: HotKeyConfig {
        didSet {
            saveSettings()
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let configsKey = "spacepill_configs_v2"
    private let editHotKeyKey = "spacepill_edit_hotkey"
    private let switchHotKeyKey = "spacepill_switch_hotkey"
    
    init() {
        // Load hotkeys with defaults
        if let data = userDefaults.data(forKey: editHotKeyKey),
           let decoded = try? JSONDecoder().decode(HotKeyConfig.self, from: data) {
            self.quickEditHotKey = decoded
        } else {
            self.quickEditHotKey = HotKeyConfig(keyCode: 1, modifiers: 0x0100 | 0x0200)
        }
        
        if let data = userDefaults.data(forKey: switchHotKeyKey),
           let decoded = try? JSONDecoder().decode(HotKeyConfig.self, from: data) {
            self.quickSwitchHotKey = decoded
        } else {
            self.quickSwitchHotKey = HotKeyConfig(keyCode: 38, modifiers: 0x0100 | 0x0200)
        }

        loadConfigs()
        self.isQuickSwitchEnabled = userDefaults.bool(forKey: "isQuickSwitchEnabled")
        
        // Sync launchAtLogin with system state
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func updateLoginItem() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            print("SpacePill: Failed to update login item status: \(error)")
        }
    }
    
    func loadConfigs() {
        if let data = userDefaults.data(forKey: configsKey),
           let decoded = try? JSONDecoder().decode([String: SpaceConfig].self, from: data) {
            spaceConfigs = decoded
        }
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(quickEditHotKey) {
            userDefaults.set(encoded, forKey: editHotKeyKey)
        }
        if let encoded = try? JSONEncoder().encode(quickSwitchHotKey) {
            userDefaults.set(encoded, forKey: switchHotKeyKey)
        }
        objectWillChange.send()
    }
    
    func saveConfigs() {
        if let encoded = try? JSONEncoder().encode(spaceConfigs) {
            userDefaults.set(encoded, forKey: configsKey)
        }
    }
    
    func setConfig(for uuid: String, label: String?, hexColor: String?) {
        spaceConfigs[uuid] = SpaceConfig(label: label, hexColor: hexColor)
        saveConfigs()
        objectWillChange.send()
    }
    
    func clearConfig(for uuid: String) {
        spaceConfigs.removeValue(forKey: uuid)
        saveConfigs()
        objectWillChange.send()
    }
    
    func resetAll() {
        spaceConfigs = [:]
        saveConfigs()
        objectWillChange.send()
    }
}

// ... Color extensions remain the same ...
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String? {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)
        
        if components.count >= 4 {
            a = Float(components[3])
        }
        
        return String(format: "%02lX%02lX%02lX%02lX", lroundf(a * 255), lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}
