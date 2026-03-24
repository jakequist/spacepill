import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var settingsManager = SettingsManager()
    var spaceManager = SpaceManager()
    lazy var notesManager = NotesManager(spaceManager: spaceManager)
    var hotKeyManager = GlobalHotKeyManager()
    var statusBarController: StatusBarController?
    
    private var preferencesWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances
        let currentApp = NSRunningApplication.current
        let runningApps = NSWorkspace.shared.runningApplications
        let isAlreadyRunning = runningApps.contains { 
            $0.executableURL?.lastPathComponent == "SpacePill" && $0 != currentApp 
        }
        
        if isAlreadyRunning {
            print("SpacePill: Another instance is already running. Exiting.")
            NSApp.terminate(nil)
            return
        }

        print("SpacePill: AppDelegate applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        
        statusBarController = StatusBarController(settingsManager, spaceManager, notesManager, self)
        
        setupHotKeys()
        setupSignalHandlers()
        
        // Listen for setting changes
        settingsManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.setupHotKeys()
            }
        }.store(in: &cancellables)
    }
    
    private func setupSignalHandlers() {
        let signals = [SIGINT, SIGTERM]
        for sig in signals {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                print("\nSpacePill: Received signal \(sig), exiting gracefully...")
                self?.saveAll()
                NSApp.terminate(nil)
            }
            source.resume()
            // We need to ignore the default signal handling or it will kill us immediately
            signal(sig, SIG_IGN)
        }
    }
    
    func saveAll() {
        print("SpacePill: Saving all state before exit...")
        settingsManager.save()
        notesManager.saveCurrentNotes()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        saveAll()
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !accessEnabled {
            print("SpacePill: Accessibility permissions NOT granted. Space switching may fail.")
        }
    }
    
    private func setupHotKeys() {
        print("SpacePill: setupHotKeys started")
        // 1. Quick Edit Hotkey (Always enabled)
        hotKeyManager.registerHotKey(
            id: 1, 
            keyCode: settingsManager.quickEditHotKey.keyCode, 
            modifiers: settingsManager.quickEditHotKey.modifiers
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.statusBarController?.showQuickEditDialog()
            }
        }
        
        // 2. Quick Switch Hotkey (Conditional)
        if settingsManager.isQuickSwitchEnabled {
            checkAccessibilityPermissions()
            
            hotKeyManager.registerHotKey(
                id: 2, 
                keyCode: settingsManager.quickSwitchHotKey.keyCode, 
                modifiers: settingsManager.quickSwitchHotKey.modifiers
            ) { [weak self] in
                DispatchQueue.main.async {
                    self?.statusBarController?.showQuickSwitchBar()
                }
            }
        } else {
            hotKeyManager.unregisterHotKey(id: 2)
        }

        // 3. Notes Hotkey (Conditional)
        if settingsManager.isNotesEnabled {
            hotKeyManager.registerHotKey(
                id: 3, 
                keyCode: settingsManager.notesHotKey.keyCode, 
                modifiers: settingsManager.notesHotKey.modifiers
            ) { [weak self] in
                DispatchQueue.main.async {
                    self?.statusBarController?.showNotesWindow()
                }
            }
        } else {
            hotKeyManager.unregisterHotKey(id: 3)
        }
        print("SpacePill: setupHotKeys complete")
    }
    
    /**
     * Manually creates and shows a window for Preferences.
     */
    @objc func showPreferencesWindow() {
        if preferencesWindow == nil {
            let view = PreferencesView(settingsManager: settingsManager, hotKeyManager: hotKeyManager)
            let hostingController = NSHostingController(rootView: view)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 650),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SpacePill Preferences"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}

@main
struct SpacePillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            PreferencesView(settingsManager: appDelegate.settingsManager, hotKeyManager: appDelegate.hotKeyManager)
        }
    }
}
