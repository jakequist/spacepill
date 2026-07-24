import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var settingsManager = SettingsManager()
    var spaceManager = SpaceManager()
    lazy var notesManager = NotesManager(spaceManager: spaceManager)
    var hotKeyManager = GlobalHotKeyManager()
    var statusBarController: StatusBarController?
    private var cliServer: CLIServer?

    private var preferencesWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var signalSources: [DispatchSourceSignal] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances
        let currentApp = NSRunningApplication.current
        let runningApps = NSWorkspace.shared.runningApplications
        let isAlreadyRunning = runningApps.contains { 
            $0.executableURL?.lastPathComponent == "SpacePill" && $0 != currentApp 
        }
        
        if isAlreadyRunning {
            Log.app.notice("Another instance is already running; exiting.")
            NSApp.terminate(nil)
            return
        }

        Log.app.info("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        
        statusBarController = StatusBarController(settingsManager, spaceManager, notesManager, self)
        
        setupHotKeys()
        setupSignalHandlers()

        // The `spacepill` CLI is a thin client over this socket; the app keeps
        // all the state and all the TCC grants. Started after the managers exist
        // because every handler reads them.
        let server = CLIServer(settingsManager: settingsManager,
                               spaceManager: spaceManager,
                               notesManager: notesManager)
        server.start()
        cliServer = server

        // A fresh install has both features switched off and, on stock macOS, no
        // "Switch to Desktop" shortcuts either -- so the hotkeys do nothing and
        // there is nothing on screen to say why. Show the guidance once; it is
        // reachable from the status bar menu ever after.
        if settingsManager.isFirstLaunch {
            Log.app.info("First launch: showing the Setup window")
            showSetupWindow()
        }

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
            signal(sig, SIG_IGN)
            
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                Log.app.notice("Received signal \(sig, privacy: .public); exiting gracefully.")
                self?.shutdown()
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }
    
    func saveAll() {
        Log.app.info("Saving all state before exit")
        settingsManager.save()
        notesManager.saveCurrentNotes()
    }
    
    /**
     * Save state and tear down the CLI socket. Called from both exit paths;
     * `CLIServer.stop()` is idempotent so the double call is harmless.
     */
    private func shutdown() {
        saveAll()
        cliServer?.stop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !accessEnabled {
            Log.app.error("Accessibility permission not granted; space switching will fail.")
        }
    }
    
    private func setupHotKeys() {
        Log.hotkeys.debug("setupHotKeys started")
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
        Log.hotkeys.debug("setupHotKeys complete")
    }
    
    /**
     * Shows the first-run guidance window. Kept alive between showings so the
     * checks it holds are not thrown away every time it is closed.
     */
    @objc func showSetupWindow() {
        if setupWindow == nil {
            let view = SetupView(settingsManager: settingsManager)
            let hostingController = NSHostingController(rootView: view)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 700),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SpacePill Setup"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false
            setupWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
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
