import SwiftUI
import Carbon
import ServiceManagement

struct SpaceConfig: Codable {
    var label: String?
    var hexColor: String? 
    var isNotesOpen: Bool?
    var scrollPosition: Double?
    
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
 * Data structure for all app settings.
 */
struct SettingsData: Codable {
    var isQuickSwitchEnabled: Bool = false
    var isNotesEnabled: Bool = false
    var matchSpaceColorForNotesBorder: Bool = true
    var maxNotesHeight: Double = 300.0
    var quickEditHotKey: HotKeyConfig = HotKeyConfig(keyCode: 1, modifiers: 0x0100 | 0x0200)
    var quickSwitchHotKey: HotKeyConfig = HotKeyConfig(keyCode: 38, modifiers: 0x0100 | 0x0200)
    var notesHotKey: HotKeyConfig = HotKeyConfig(keyCode: 45, modifiers: 0x0100 | 0x0200)
    var spaceConfigs: [String: SpaceConfig] = [:]
}

/**
 * Handles persistence of space configurations (labels and colors) and app settings.
 * Now stores everything in ~/.spacepill/settings.json.
 */
class SettingsManager: ObservableObject {
    @Published var isQuickSwitchEnabled: Bool = false { didSet { save() } }
    @Published var isNotesEnabled: Bool = false { didSet { save() } }
    @Published var matchSpaceColorForNotesBorder: Bool = true { didSet { save() } }
    @Published var maxNotesHeight: Double = 300.0 { didSet { save() } }
    @Published var quickEditHotKey: HotKeyConfig = HotKeyConfig(keyCode: 1, modifiers: 0x0100 | 0x0200) { didSet { save() } }
    @Published var quickSwitchHotKey: HotKeyConfig = HotKeyConfig(keyCode: 38, modifiers: 0x0100 | 0x0200) { didSet { save() } }
    @Published var notesHotKey: HotKeyConfig = HotKeyConfig(keyCode: 45, modifiers: 0x0100 | 0x0200) { didSet { save() } }
    @Published var spaceConfigs: [String: SpaceConfig] = [:] { didSet { save() } }
    
    @Published var launchAtLogin: Bool = false {
        didSet {
            updateLoginItem()
        }
    }
    
    private let settingsURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseDir = home.appendingPathComponent(".spacepill", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        return baseDir.appendingPathComponent("settings.json")
    }()
    
    private var isUpdating = false
    
    init() {
        print("SpacePill: SettingsManager initializing")
        load()
        syncLaunchAtLogin()
    }

    private func syncLaunchAtLogin() {
        // SMAppService requires a proper app bundle and CFBundleIdentifier.
        // It will trap (crash) if run directly from a binary.
        guard Bundle.main.bundleIdentifier != nil else {
            print("SpacePill: Skipping SMAppService sync - not a proper app bundle")
            return
        }
        
        self.isUpdating = true
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.isUpdating = false
    }

    private func updateLoginItem() {
        guard !isUpdating else { return }
        guard Bundle.main.bundleIdentifier != nil else { return }
        
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
    
    func load() {
        isUpdating = true
        defer { isUpdating = false }
        
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) {
            applySettings(decoded)
        } else {
            migrateFromUserDefaults()
        }
    }
    
    private func applySettings(_ data: SettingsData) {
        self.isQuickSwitchEnabled = data.isQuickSwitchEnabled
        self.isNotesEnabled = data.isNotesEnabled
        self.matchSpaceColorForNotesBorder = data.matchSpaceColorForNotesBorder
        self.maxNotesHeight = data.maxNotesHeight
        self.quickEditHotKey = data.quickEditHotKey
        self.quickSwitchHotKey = data.quickSwitchHotKey
        self.notesHotKey = data.notesHotKey
        self.spaceConfigs = data.spaceConfigs
    }
    
    private func migrateFromUserDefaults() {
        let ud = UserDefaults.standard
        let newData = SettingsData(
            isQuickSwitchEnabled: ud.bool(forKey: "isQuickSwitchEnabled"),
            isNotesEnabled: false,
            matchSpaceColorForNotesBorder: true,
            maxNotesHeight: 300.0,
            quickEditHotKey: ud.data(forKey: "spacepill_edit_hotkey").flatMap { try? JSONDecoder().decode(HotKeyConfig.self, from: $0) } ?? HotKeyConfig(keyCode: 1, modifiers: 0x0100 | 0x0200),
            quickSwitchHotKey: ud.data(forKey: "spacepill_switch_hotkey").flatMap { try? JSONDecoder().decode(HotKeyConfig.self, from: $0) } ?? HotKeyConfig(keyCode: 38, modifiers: 0x0100 | 0x0200),
            notesHotKey: ud.data(forKey: "spacepill_notes_hotkey").flatMap { try? JSONDecoder().decode(HotKeyConfig.self, from: $0) } ?? HotKeyConfig(keyCode: 45, modifiers: 0x0100 | 0x0200),
            spaceConfigs: ud.data(forKey: "spacepill_configs_v2").flatMap { try? JSONDecoder().decode([String: SpaceConfig].self, from: $0) } ?? [:]
        )
        
        applySettings(newData)
        save()
    }
    
    func save() {
        guard !isUpdating else { return }
        
        let currentData = SettingsData(
            isQuickSwitchEnabled: isQuickSwitchEnabled,
            isNotesEnabled: isNotesEnabled,
            matchSpaceColorForNotesBorder: matchSpaceColorForNotesBorder,
            maxNotesHeight: maxNotesHeight,
            quickEditHotKey: quickEditHotKey,
            quickSwitchHotKey: quickSwitchHotKey,
            notesHotKey: notesHotKey,
            spaceConfigs: spaceConfigs
        )
        
        if let encoded = try? JSONEncoder().encode(currentData) {
            try? encoded.write(to: settingsURL)
        }
    }
    
    func setConfig(for uuid: String, label: String?, hexColor: String?) {
        var config = spaceConfigs[uuid] ?? SpaceConfig()
        config.label = label
        config.hexColor = hexColor
        spaceConfigs[uuid] = config
    }
    
    func setNotesOpen(for uuid: String, isOpen: Bool) {
        var config = spaceConfigs[uuid] ?? SpaceConfig()
        config.isNotesOpen = isOpen
        spaceConfigs[uuid] = config
    }
    
    func setScrollPosition(for uuid: String, position: Double) {
        var config = spaceConfigs[uuid] ?? SpaceConfig()
        config.scrollPosition = position
        spaceConfigs[uuid] = config
    }
    
    func clearConfig(for uuid: String) {
        spaceConfigs.removeValue(forKey: uuid)
    }
    
    func resetAll() {
        spaceConfigs = [:]
    }
}

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
