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
    
    init() {
        print("SpacePill: SpaceManager initializing")
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
            print("SpacePill: Failed to create space switch event tap")
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
            guard self.visualSpaceIndex != target.index || self.visualSpaceUUID != target.uuid else { return }
            
            print("SpacePill: Optimistic visual space update - Index: \(target.index), UUID: \(target.uuid)")
            self.visualSpaceIndex = target.index
            self.visualSpaceUUID = target.uuid
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.updateSpaces()
        }
    }
    
    func updateSpaces() {
        if let metadata = SkyLight.getActiveSpaceMetadata() {
            if metadata.uuid != currentSpaceUUID ||
                metadata.index != currentSpaceIndex ||
                metadata.uuid != visualSpaceUUID ||
                metadata.index != visualSpaceIndex {
                print("SpacePill: Space updated - Index: \(metadata.index), UUID: \(metadata.uuid)")
                DispatchQueue.main.async {
                    self.currentSpaceIndex = metadata.index
                    self.currentSpaceUUID = metadata.uuid
                    self.visualSpaceIndex = metadata.index
                    self.visualSpaceUUID = metadata.uuid
                }
            }
        }
    }
    
    deinit {
        timer?.invalidate()
        if let tap = keyboardEventTap {
            CFMachPortInvalidate(tap)
        }
    }
}
