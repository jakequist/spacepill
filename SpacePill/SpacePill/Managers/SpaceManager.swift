import Foundation
import AppKit

private let spaceSwitchEventCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard type == .keyDown, let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    
    let manager = Unmanaged<SpaceManager>.fromOpaque(refcon).takeUnretainedValue()
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    manager.handleSpaceArrowKeyDown(keyCode: keyCode, flags: event.flags)
    
    return Unmanaged.passUnretained(event)
}

class SpaceManager: ObservableObject {
    @Published var currentSpaceIndex: Int?
    @Published var currentSpaceUUID: String?
    @Published var visualSpaceIndex: Int?
    @Published var visualSpaceUUID: String?
    @Published var totalSpaces: Int = 1
    
    private var timer: Timer?
    private var keyboardEventTap: CFMachPort?
    private var keyboardEventTapSource: CFRunLoopSource?

    /// The space an optimistic update is betting on, until SkyLight agrees.
    private var pendingVisualUUID: String?
    /// Give up on that bet after this instant and trust SkyLight again.
    private var pendingVisualExpiry: Date?

    /// How long to keep showing a predicted space before assuming the guess was
    /// wrong. Native transitions take roughly half a second; this leaves room
    /// for a slow one without stranding the pill on a space we never reached.
    private static let optimisticHoldDuration: TimeInterval = 2.0
    
    init() {
        Log.spaces.debug("SpaceManager initializing")
        updateSpaces()
        setupNotificationObserver()
        setupSpaceSwitchEventTap()
        startPolling()
    }
    
    private func setupNotificationObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateSpaces()
        }
    }
    
    @objc private func spaceChanged() {
        updateSpaces()
    }
    
    private func setupSpaceSwitchEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: spaceSwitchEventCallback,
            userInfo: refcon
        ) else {
            // Almost always means Input Monitoring has not been granted.
            Log.spaces.error("Failed to create space switch event tap (check Input Monitoring permission)")
            return
        }
        
        keyboardEventTap = tap
        keyboardEventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = keyboardEventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    fileprivate func handleSpaceArrowKeyDown(keyCode: UInt16, flags: CGEventFlags) {
        guard keyCode == 123 || keyCode == 124 else { return }
        guard flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate) else {
            return
        }
        
        let direction = keyCode == 124 ? 1 : -1
        applyOptimisticSpaceChange(direction: direction)
    }
    
    private func applyOptimisticSpaceChange(direction: Int) {
        let spaces = SkyLight.getAllSpacesMetadata()
        guard !spaces.isEmpty else { return }
        
        let sourceIndex = visualSpaceIndex ?? currentSpaceIndex ?? SkyLight.getActiveSpaceMetadata()?.index
        guard let currentIndex = sourceIndex else { return }
        
        let targetIndex = currentIndex + direction
        guard let target = spaces.first(where: { $0.index == targetIndex }) else { return }
        
        DispatchQueue.main.async {
            // Claim the bet even if the pill already shows this space, so a
            // stale reading can't drag it backwards mid-transition.
            self.pendingVisualUUID = target.uuid
            self.pendingVisualExpiry = Date().addingTimeInterval(Self.optimisticHoldDuration)

            guard self.visualSpaceIndex != target.index || self.visualSpaceUUID != target.uuid else { return }

            Log.spaces.debug("Optimistic visual space update index=\(target.index, privacy: .public) uuid=\(target.uuid, privacy: .public)")
            self.visualSpaceIndex = target.index
            self.visualSpaceUUID = target.uuid
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.updateSpaces()
        }
    }

    func updateSpaces() {
        guard let metadata = SkyLight.getActiveSpaceMetadata() else { return }

        DispatchQueue.main.async {
            // A native space transition takes most of a second, and SkyLight
            // keeps reporting the *old* space for its duration. Without this
            // guard the poll timer overwrites an optimistic update with that
            // stale value and the pill visibly flickers back to the previous
            // label before settling on the new one.
            if let pending = self.pendingVisualUUID {
                if metadata.uuid == pending {
                    // The transition landed where we predicted.
                    self.pendingVisualUUID = nil
                    self.pendingVisualExpiry = nil
                } else if let expiry = self.pendingVisualExpiry, Date() < expiry {
                    // Still in flight. Track the confirmed space but leave the
                    // prediction on screen.
                    self.currentSpaceIndex = metadata.index
                    self.currentSpaceUUID = metadata.uuid
                    return
                } else {
                    // The prediction never came true -- the switch was refused
                    // or the user went somewhere else. Fall through and correct.
                    Log.spaces.debug("Optimistic space prediction expired; correcting to index=\(metadata.index, privacy: .public)")
                    self.pendingVisualUUID = nil
                    self.pendingVisualExpiry = nil
                }
            }

            guard metadata.uuid != self.currentSpaceUUID ||
                    metadata.index != self.currentSpaceIndex ||
                    metadata.uuid != self.visualSpaceUUID ||
                    metadata.index != self.visualSpaceIndex else { return }

            Log.spaces.debug("Space updated index=\(metadata.index, privacy: .public) uuid=\(metadata.uuid, privacy: .public)")
            self.currentSpaceIndex = metadata.index
            self.currentSpaceUUID = metadata.uuid
            self.visualSpaceIndex = metadata.index
            self.visualSpaceUUID = metadata.uuid
        }
    }
    
    deinit {
        timer?.invalidate()
        if let tap = keyboardEventTap {
            CFMachPortInvalidate(tap)
        }
    }
}
