import SwiftUI
import AppKit
import Combine

/**
 * Manages the SpacePill menu bar item and its associated views.
 */
class StatusBarController: NSObject, NSPopoverDelegate {
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
        
        // Initialize popover once
        setupPopover()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.delegate = self
    }
    
    func popoverDidClose(_ notification: Notification) {
        // Critical: Clear content view controller to ensure cleanup and avoid leaked event monitors
        print("SpacePill: Popover closed, cleaning up content")
        popover?.contentViewController = nil
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
        
        statusBarItem.popUpMenu(menu)
    }
    
    @objc func showNotesWindow() {
        guard settingsManager.isNotesEnabled else { return }
        
        // Ensure popovers are closed first
        if popover?.isShown == true {
            popover?.performClose(nil)
        }
        
        if let window = notesWindow, window.isVisible {
            if window.isKeyWindow {
                window.orderOut(nil)
                if let uuid = spaceManager.currentSpaceUUID {
                    settingsManager.setNotesOpen(for: uuid, isOpen: false)
                }
            } else {
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
        
        let contentSize = window.contentViewController?.view.fittingSize ?? CGSize(width: 400, height: 100)
        let windowHeight = contentSize.height
        
        let windowX = buttonFrame.origin.x
        let windowY = buttonFrame.origin.y - windowHeight - 5
        let windowWidth = screenFrame.maxX - windowX - 10
        
        window.setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true, animate: false)
    }
    
    func showQuickEditDialog() {
        if notesWindow?.isVisible == true {
            notesWindow?.orderOut(nil)
        }
        
        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }
        
        popover?.contentViewController = NSHostingController(rootView: QuickEditView(
            settingsManager: settingsManager, 
            spaceManager: spaceManager,
            onDismiss: { [weak self] in
                self?.popover?.performClose(nil)
            }
        ))
        
        if let button = statusBarItem.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func showQuickSwitchBar() {
        if notesWindow?.isVisible == true {
            notesWindow?.orderOut(nil)
        }
        
        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }
        
        popover?.contentViewController = NSHostingController(rootView: QuickSwitchView(
            settingsManager: settingsManager, 
            spaceManager: spaceManager,
            onDismiss: { [weak self] in
                self?.popover?.performClose(nil)
            }
        ))
        
        if let button = statusBarItem.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
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

                let circleColor = isConfigured ? mainColor.darkened(by: 0.45) : .black.opacity(0.5)

                Capsule()
                    .fill(mainColor)
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(isConfigured ? 0.5 : 0.1), lineWidth: 3)
                    )

                ZStack {
                    if let label = labelText, !label.isEmpty {
                        Text(label.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isConfigured ? .white : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

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

class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}
