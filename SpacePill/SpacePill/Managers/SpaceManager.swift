import Foundation
import AppKit

class SpaceManager: ObservableObject {
    @Published var currentSpaceIndex: Int?
    @Published var currentSpaceUUID: String?
    @Published var totalSpaces: Int = 1
    
    private var timer: Timer?
    
    init() {
        print("SpacePill: SpaceManager initializing")
        updateSpaces()
        setupNotificationObserver()
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
    
    func updateSpaces() {
        if let metadata = SkyLight.getActiveSpaceMetadata() {
            if metadata.uuid != currentSpaceUUID || metadata.index != currentSpaceIndex {
                print("SpacePill: Space updated - Index: \(metadata.index), UUID: \(metadata.uuid)")
                DispatchQueue.main.async {
                    self.currentSpaceIndex = metadata.index
                    self.currentSpaceUUID = metadata.uuid
                }
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
