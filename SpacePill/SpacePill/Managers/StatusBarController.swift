import SwiftUI
import AppKit
import Combine

/**
 * Manages the SpacePill menu bar item and its associated views.
 */
class StatusBarController: NSObject {
    var statusBarItem: NSStatusItem
    private var popover: NSPopover?
    private var notesWindow: NSWindow?
    private var settingsManager: SettingsManager
    private var spaceManager: SpaceManager
    private var notesManager: NotesManager
    private weak var appDelegate: AppDelegate?
    private var cancellables = Set<AnyCancellable>()
    
    init(_ settingsManager: SettingsManager, _ spaceManager: SpaceManager, _ notesManager: NotesManager, _ appDelegate: AppDelegate) {
        // Use a fixed length for a clear rectangular look. 150px provides ample room.
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: 150)
        self.settingsManager = settingsManager
        self.spaceManager = spaceManager
        self.notesManager = notesManager
        self.appDelegate = appDelegate
        super.init()
        
        setupStatusBarItem()
        setupSpaceObserver()
        setupResizeObserver()
    }
    
    private func setupResizeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResize),
            name: Notification.Name("NotesWindowShouldResize"),
            object: nil
        )
    }
    
    @objc private func handleResize() {
        positionNotesWindow()
    }
    
    private func setupSpaceObserver() {
        spaceManager.$currentSpaceIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSpaceChange()
            }
            .store(in: &cancellables)
    }
    
    private func handleSpaceChange() {
        guard settingsManager.isNotesEnabled else {
            notesWindow?.orderOut(nil)
            return
        }
        
        guard let uuid = spaceManager.currentSpaceUUID else { return }
        let shouldBeOpen = settingsManager.spaceConfigs[uuid]?.isNotesOpen ?? false
        
        if shouldBeOpen {
            ensureNotesWindowExists()
            positionNotesWindow()
            notesWindow?.makeKeyAndOrderFront(nil)
        } else {
            notesWindow?.orderOut(nil)
        }
    }
    
    private func setupStatusBarItem() {
        guard let button = statusBarItem.button else { return }
        
        let indicatorView = MenuBarIndicatorView(settingsManager: settingsManager, spaceManager: spaceManager)
        let hostingView = NSHostingView(rootView: indicatorView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 150, height: 22)
        button.addSubview(hostingView)
        
        button.target = self
        button.action = #selector(handleAction(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        
        print("SpacePill: Status bar button setup complete")
    }
    
    @objc func handleAction(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseDown {
            showContextMenu(on: sender)
        } else {
            showQuickEditDialog()
        }
    }
    
    private func showContextMenu(on sender: NSStatusBarButton) {
        let menu = NSMenu()
        
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(AppDelegate.showPreferencesWindow), keyEquivalent: ",")
        prefsItem.target = appDelegate
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit SpacePill", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        // Show menu manually to avoid conflicts with mouseDown processing
        statusBarItem.popUpMenu(menu)
    }
    
    @objc func showNotesWindow() {
        guard settingsManager.isNotesEnabled else { return }
        
        // Ensure Quick Switch or Quick Edit is closed
        if popover?.isShown == true {
            popover?.performClose(nil)
        }
        
        if let window = notesWindow, window.isVisible {
            if window.isKeyWindow {
                // If already focused, hide it
                window.orderOut(nil)
                if let uuid = spaceManager.currentSpaceUUID {
                    settingsManager.setNotesOpen(for: uuid, isOpen: false)
                }
            } else {
                // If visible but not focused, focus it
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }
        
        ensureNotesWindowExists()
        
        positionNotesWindow()
        notesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if let uuid = spaceManager.currentSpaceUUID {
            settingsManager.setNotesOpen(for: uuid, isOpen: true)
        }
    }
    
    private func ensureNotesWindowExists() {
        guard settingsManager.isNotesEnabled else { return }
        
        if notesWindow == nil {
            let view = NotesView(notesManager: notesManager, settingsManager: settingsManager, spaceManager: spaceManager)
            let hostingController = NSHostingController(rootView: view)
            
            let window = NotesPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isFloatingPanel = true
            window.becomesKeyOnlyIfNeeded = false
            window.hidesOnDeactivate = false
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = .clear
            window.hasShadow = true
            window.contentViewController = hostingController
            
            notesWindow = window
        }
    }
    
    private func positionNotesWindow() {
        guard let button = statusBarItem.button,
              let window = notesWindow,
              let screen = NSScreen.main else { return }
        
        let buttonFrame = button.window?.frame ?? .zero
        let screenFrame = screen.visibleFrame
        
        // Use the size from the hosting controller's view
        let contentSize = window.contentViewController?.view.fittingSize ?? CGSize(width: 400, height: 100)
        let windowHeight = contentSize.height
        
        // "starts at our menubar pill UI, and then runs all the way to the right of the screen"
        let windowX = buttonFrame.origin.x
        let windowY = buttonFrame.origin.y - windowHeight - 5 // Dynamic height + small gap
        let windowWidth = screenFrame.maxX - windowX - 10 // 10px padding from right
        
        window.setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true, animate: false)
    }
    
    func showQuickEditDialog() {
        // Close notes window temporarily
        if notesWindow?.isVisible == true {
            notesWindow?.orderOut(nil)
        }
        
        if popover == nil {
            popover = NSPopover()
            popover?.behavior = .transient
        }
        
        popover?.contentViewController = NSHostingController(rootView: QuickEditView(
            settingsManager: settingsManager, 
            spaceManager: spaceManager,
            onDismiss: { [weak self] in
                self?.popover?.performClose(nil)
            }
        ))
        
        if let button = statusBarItem.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    /**
     * Displays the quick-switch bar (SwiftUI popover) for fuzzy searching and switching spaces.
     */
    func showQuickSwitchBar() {
        // Close notes window or ensure it loses focus
        if notesWindow?.isVisible == true {
            notesWindow?.orderOut(nil)
        }
        
        if popover == nil {
            popover = NSPopover()
            popover?.behavior = .transient
        }
        
        popover?.contentViewController = NSHostingController(rootView: QuickSwitchView(
            settingsManager: settingsManager, 
            spaceManager: spaceManager,
            onDismiss: { [weak self] in
                self?.popover?.performClose(nil)
            }
        ))
        
        if let button = statusBarItem.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

struct MenuBarIndicatorView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var spaceManager: SpaceManager

    var body: some View {
        ZStack {
            if let index = spaceManager.currentSpaceIndex,
               let uuid = spaceManager.currentSpaceUUID {
                let config = settingsManager.spaceConfigs[uuid]
                let labelText = config?.label
                let isConfigured = config != nil
                let mainColor = config?.color ?? Color.primary.opacity(0.1)

                // Substantially darker hue for the circle
                let circleColor = isConfigured ? mainColor.darkened(by: 0.45) : .black.opacity(0.5)

                // Background Capsule
                Capsule()
                    .fill(mainColor)
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(isConfigured ? 0.5 : 0.1), lineWidth: 3)
                    )

                // Content
                ZStack {
                    // Center-aligned label text
                    if let label = labelText, !label.isEmpty {
                        Text(label.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isConfigured ? .white : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    // Left-aligned circle badge
                    HStack {
                        Text("\(index)")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(circleColor)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black, lineWidth: 1))
                            .padding(.leading, 2)

                        Spacer()
                    }
                }
            } else {
                Text("?")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 2)
    }
}

extension Color {
    func darkened(by percentage: CGFloat = 0.15) -> Color {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(NSColor(calibratedHue: hue, saturation: saturation, brightness: max(brightness - percentage, 0.0), alpha: alpha))
    }
}

/**
 * A specialized NSPanel that allows becoming the key window to accept keyboard input.
 */
class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}
