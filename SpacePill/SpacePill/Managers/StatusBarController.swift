import SwiftUI
import AppKit
import Combine

/**
 * Manages the SpacePill menu bar item and its associated views.
 */
class StatusBarController: NSObject, NSPopoverDelegate {
    /// What the shared popover is currently presenting, if anything.
    private enum PopoverContent { case quickEdit, quickSwitch }

    var statusBarItem: NSStatusItem
    private var popover: NSPopover?

    /**
     * The single source of truth for "is a popover open, and which one".
     *
     * Deliberately *not* `NSPopover.isShown`. After an Esc-driven dismissal the
     * old code's `if popover?.isShown == true { performClose(); return }` guard
     * would see a stale `true` and read every subsequent open as a toggle-close
     * of an already-invisible popover, so the reopen path was silently skipped
     * and both the hotkey and the pill click "went dead". This flag is set only
     * where we open, and cleared only where the popover actually closes, so it
     * cannot get wedged.
     */
    private var popoverContent: PopoverContent?
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

    /**
     * The popover closed -- either because we closed it, or because the system
     * dismissed the transient popover (Esc, a click outside, or app
     * deactivation). Clearing `popoverContent` here is what guarantees the next
     * open is treated as an open and not as a stale toggle-close.
     *
     * Guard on identity: a replaced popover's close callback can arrive after we
     * have already opened its successor, and must not wipe the new one's state.
     */
    func popoverDidClose(_ notification: Notification) {
        let closed = notification.object as? NSPopover
        // Release the content view controller so its SwiftUI view tears down and
        // removes any local event monitor it installed.
        closed?.contentViewController = nil
        guard closed === popover else { return }
        Log.ui.debug("Popover closed, clearing popover state")
        popover = nil
        popoverContent = nil
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
        spaceManager.$visualSpaceUUID
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
        
        guard let uuid = spaceManager.visualSpaceUUID ?? spaceManager.currentSpaceUUID else { return }
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
        
        Log.ui.debug("Status bar button setup complete")
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
        
        // Above Preferences: this is where someone goes when nothing seems to
        // work, and the answer is usually a permission or a macOS shortcut
        // rather than anything in Preferences.
        let setupItem = NSMenuItem(title: "Setup…", action: #selector(AppDelegate.showSetupWindow), keyEquivalent: "")
        setupItem.target = appDelegate
        menu.addItem(setupItem)

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
        
        // Ensure any popover is closed first
        dismissPopover()

        if let window = notesWindow, window.isVisible {
            if window.isKeyWindow {
                window.orderOut(nil)
                if let uuid = spaceManager.visualSpaceUUID ?? spaceManager.currentSpaceUUID {
                    settingsManager.setNotesOpen(for: uuid, isOpen: false)
                }
            } else {
                NSApp.activate(ignoringOtherApps: true)
                positionNotesWindow()
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
        
        ensureNotesWindowExists()
        
        NSApp.activate(ignoringOtherApps: true)
        positionNotesWindow()
        notesWindow?.makeKeyAndOrderFront(nil)
        
        if let uuid = spaceManager.visualSpaceUUID ?? spaceManager.currentSpaceUUID {
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
              let buttonWindow = button.window,
              let window = notesWindow else { return }
        
        let contentSize = window.contentViewController?.view.fittingSize ?? CGSize(width: 400, height: 100)
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = buttonWindow.convertToScreen(buttonRectInWindow)
        let screen = buttonWindow.screen ?? NSScreen.screens.first { $0.frame.intersects(buttonFrame) }
        let screenFrame = screen?.visibleFrame ?? buttonFrame.insetBy(dx: -400, dy: -400)
        
        let maxWidth = max(320, screenFrame.width - 20)
        let preferredWidth = screenFrame.maxX - buttonFrame.minX - 10
        let windowWidth = min(max(preferredWidth, 320), maxWidth)
        let windowHeight = min(contentSize.height, screenFrame.height - 20)
        let windowX = min(max(buttonFrame.minX, screenFrame.minX + 10), screenFrame.maxX - windowWidth - 10)
        let windowY = max(screenFrame.minY + 10, buttonFrame.minY - windowHeight - 5)

        window.setFrame(
            NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            display: true,
            animate: false
        )
    }
    
    func showQuickEditDialog() {
        togglePopover(.quickEdit)
    }

    func showQuickSwitchBar() {
        togglePopover(.quickSwitch)
    }

    /**
     * Opens `content`, or -- if that same popover is already open -- closes it.
     * That is the deliberate hotkey/click toggle. Opening a *different* popover
     * while one is up replaces it.
     *
     * The toggle decision reads our own `popoverContent`, never
     * `NSPopover.isShown`, so it can never wedge on a stale shown state.
     */
    private func togglePopover(_ content: PopoverContent) {
        if notesWindow?.isVisible == true {
            notesWindow?.orderOut(nil)
        }

        if popoverContent == content {
            dismissPopover()
            return
        }

        presentPopover(content)
    }

    private func presentPopover(_ content: PopoverContent) {
        guard let button = statusBarItem.button else { return }

        // Tear down anything already up first, then build a brand-new NSPopover.
        // A fresh instance carries no shown-state from a previous cycle, which is
        // what makes reopen reliable no matter how the last one was dismissed.
        dismissPopover()

        let controller: NSViewController
        switch content {
        case .quickEdit:
            controller = NSHostingController(rootView: QuickEditView(
                settingsManager: settingsManager,
                spaceManager: spaceManager,
                onDismiss: { [weak self] in self?.dismissPopover() }
            ))
        case .quickSwitch:
            controller = NSHostingController(rootView: QuickSwitchView(
                settingsManager: settingsManager,
                spaceManager: spaceManager,
                onDismiss: { [weak self] in self?.dismissPopover() }
            ))
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = controller
        self.popover = popover
        self.popoverContent = content

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    /**
     * Closes the shared popover and clears our state immediately. Safe to call
     * when nothing is open. State is cleared up front so a reopen fired right
     * after can never be misread as a toggle-close; the animated close then runs
     * and its `popoverDidClose` is a no-op for state (identity guard).
     */
    private func dismissPopover() {
        guard let popover = popover else {
            popoverContent = nil
            return
        }
        self.popover = nil
        self.popoverContent = nil
        popover.performClose(nil)
    }
}

struct MenuBarIndicatorView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var spaceManager: SpaceManager

    var body: some View {
        ZStack {
            if let index = spaceManager.visualSpaceIndex,
               let uuid = spaceManager.visualSpaceUUID {
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
