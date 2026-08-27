import SwiftUI
import AppKit
import Combine
import SpacePillCore

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

        migrateLegacyEmptyUUIDConfig()

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

        // Listen for setting changes. The async hop matters: objectWillChange
        // fires *before* the value lands, so setupHotKeys must not read the
        // settings until the next runloop turn.
        settingsManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.setupHotKeys()
            }
        }.store(in: &cancellables)
    }

    /**
     * The hotkey-relevant slice of settings, so `setupHotKeys` can tell a real
     * hotkey change apart from unrelated settings traffic.
     *
     * This gate is load-bearing: every settings write fires `objectWillChange`,
     * and scrolling the notes panel writes `scrollPosition` continuously -- so
     * without it, all three hotkeys are torn down and re-registered many times
     * a second during a scroll. Every cycle is a window where a keypress is
     * silently dropped, and a transient Carbon failure mid-churn leaves a
     * hotkey dead until the *next* settings write. Presented as "SpacePill
     * stopped responding to hotkeys".
     */
    private struct HotKeySettings: Equatable {
        let quickEdit: HotKeyConfig
        let quickSwitch: HotKeyConfig
        let notes: HotKeyConfig
        let quickSwitchEnabled: Bool
        let notesEnabled: Bool
    }
    private var appliedHotKeySettings: HotKeySettings?
    
    /**
     * One-time migration of the legacy `""` config bucket.
     *
     * Older builds keyed a Space whose SkyLight UUID was empty under the `""`
     * key. `SkyLight` now derives a stable, non-empty key from `id64` for such
     * Spaces (see `SpaceIdentity`), so an existing `""` entry -- e.g. the
     * "Inbox" label on Desktop 1 on this machine -- would otherwise be orphaned.
     *
     * Re-key it onto the current empty-UUID Space's synthesised key. If there is
     * no empty-UUID Space right now, or the target already has a config, the
     * legacy entry is left untouched so a later launch can still claim it and no
     * existing config is ever lost.
     */
    private func migrateLegacyEmptyUUIDConfig() {
        guard let legacy = settingsManager.spaceConfigs[""] else { return }

        let synthetic = SkyLight.getAllSpacesMetadata()
            .first { SpaceIdentity.isSynthetic($0.uuid) }
        guard let target = synthetic else {
            Log.settings.notice("Legacy empty-UUID config present but no empty-UUID space found; leaving it in place")
            return
        }

        var configs = settingsManager.spaceConfigs
        if configs[target.uuid] == nil {
            configs[target.uuid] = legacy
        }
        configs.removeValue(forKey: "")
        settingsManager.spaceConfigs = configs
        Log.settings.info("Migrated legacy empty-UUID space config to \(target.uuid, privacy: .public)")
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
        let wanted = HotKeySettings(
            quickEdit: settingsManager.quickEditHotKey,
            quickSwitch: settingsManager.quickSwitchHotKey,
            notes: settingsManager.notesHotKey,
            quickSwitchEnabled: settingsManager.isQuickSwitchEnabled,
            notesEnabled: settingsManager.isNotesEnabled
        )
        guard wanted != appliedHotKeySettings else { return }
        appliedHotKeySettings = wanted

        Log.hotkeys.info("Registering hotkeys (config changed)")
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
