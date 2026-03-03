import SwiftUI
import AppKit

/**
 * Manages the SpacePill menu bar item and its associated views.
 * Handles left-click (quick-edit popover) and right-click (context menu).
 */
class StatusBarController: NSObject {
    var statusBarItem: NSStatusItem
    private var popover: NSPopover?
    private var settingsManager: SettingsManager
    private var spaceManager: SpaceManager
    private weak var appDelegate: AppDelegate?
    
    init(_ settingsManager: SettingsManager, _ spaceManager: SpaceManager, _ appDelegate: AppDelegate) {
        // Use a fixed length for a clear rectangular look. 150px provides ample room.
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: 150)
        self.settingsManager = settingsManager
        self.spaceManager = spaceManager
        self.appDelegate = appDelegate
        super.init()
        
        setupStatusBarItem()
    }
    
    private func setupStatusBarItem() {
        guard let button = statusBarItem.button else { return }
        
        setupHostingView(on: button)
        setupButtonAction(on: button)
        
        print("SpacePill: Status bar button setup complete")
    }
    
    private func setupHostingView(on button: NSStatusBarButton) {
        let indicatorView = MenuBarIndicatorView(settingsManager: settingsManager, spaceManager: spaceManager)
        let hostingView = NSHostingView(rootView: indicatorView)
        
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
    }
    
    private func setupButtonAction(on button: NSStatusBarButton) {
        button.action = #selector(handleAction(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.target = self
    }
    
    @objc func handleAction(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseDown {
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
        
        statusBarItem.menu = menu
        statusBarItem.button?.performClick(nil)
        statusBarItem.menu = nil
    }
    
    func showQuickEditDialog() {
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
