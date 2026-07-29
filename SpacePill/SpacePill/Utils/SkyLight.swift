import Foundation
import CoreGraphics
import SpacePillCore

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> CGSConnectionID

@_silgen_name("SLSGetActiveSpace")
func SLSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("SLSCopyManagedDisplaySpaces")
func SLSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?


struct SpaceMetadata {
    let index: Int
    let id: CGSSpaceID
    let uuid: String
    let displayUUID: String
}

class SkyLight {
    static func getActiveSpaceID() -> CGSSpaceID {
        let connection = SLSMainConnectionID()
        return SLSGetActiveSpace(connection)
    }

    /**
     * Returns metadata for all spaces across all displays.
     */
    static func getAllSpacesMetadata() -> [SpaceMetadata] {
        let connection = SLSMainConnectionID()
        
        guard let displaysArray = SLSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return []
        }
        
        var allMetadata: [SpaceMetadata] = []
        var globalIndex = 1
        
        for display in displaysArray {
            guard let displayUUID = display["Display Identifier"] as? String else { continue }
            
            if let spaces = display["Spaces"] as? [[String: Any]] {
                for space in spaces {
                    // id64 is the gate, not uuid: SkyLight reports an empty uuid
                    // for Desktop 1 on some Macs, and dropping such a space would
                    // both hide it and shift every later index. Instead we derive
                    // a stable, non-empty key from id64 (see SpaceIdentity), so no
                    // config is ever stored under the "" key.
                    if let id64 = space["id64"] as? UInt64 {
                        let uuid = SpaceIdentity.key(rawUUID: space["uuid"] as? String, id64: id64)
                        allMetadata.append(SpaceMetadata(index: globalIndex, id: id64, uuid: uuid, displayUUID: displayUUID))
                        globalIndex += 1
                    }
                }
            }
        }
        
        return allMetadata
    }
    
    /**
     * Returns the metadata for the currently active space.
     */
    static func getActiveSpaceMetadata() -> SpaceMetadata? {
        let allSpaces = getAllSpacesMetadata()
        
        if let currentSpaceID = getCurrentManagedSpaceID() {
            return allSpaces.first { $0.id == currentSpaceID }
        }
        
        let activeID = getActiveSpaceID()
        return allSpaces.first { $0.id == activeID }
    }

    /**
     * The highest desktop macOS defines a "Switch to Desktop N" shortcut for.
     * Only relevant to the keyboard fallback below; the direct method has no
     * such ceiling.
     */
    static let maxSwitchableSpaceIndex = SpaceShortcuts.maxDesktop

    /**
     * Whether `switchToSpace` can reach this index: within Desktop 1-10 and with
     * that Desktop's shortcut enabled. (The >10 experiment did not yield a
     * reliable switch -- see EXPERIMENT.md.)
     */
    static func canSwitchToSpace(index: Int) -> Bool {
        guard index >= 1 && index <= maxSwitchableSpaceIndex else { return false }
        return SpaceShortcuts.shortcut(forDesktop: index) != nil
    }

    /**
     * Switch to a Space by index by replaying its "Switch to Desktop N"
     * shortcut. Reliable and produces a real, clean transition, but only reaches
     * Desktops 1-10 and only when the shortcut is enabled.
     *
     * NOTE: the >10 experiment (SLSManagedDisplaySetCurrentSpace, and Ctrl+Arrow
     * stepping via CGEvent) is documented in EXPERIMENT.md. The direct call only
     * moves the window server's *record*, not the display; CGEvent-posted arrow
     * keys do not trigger the space-move shortcut the way System Events does.
     * So we stay on the reliable keyboard path here.
     *
     * - Returns: `false` if the Space does not exist or has no usable shortcut.
     */
    @discardableResult
    static func switchToSpace(index target: Int) -> Bool {
        let metadata = getAllSpacesMetadata()
        guard metadata.contains(where: { $0.index == target }) else {
            Log.spaces.error("Space index \(target, privacy: .public) not found")
            return false
        }
        guard target <= maxSwitchableSpaceIndex,
              let shortcut = SpaceShortcuts.shortcut(forDesktop: target) else {
            Log.spaces.notice("No usable 'Switch to Desktop \(target, privacy: .public)' shortcut; not switching")
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        keyDown?.flags = shortcut.modifiers
        keyUp?.flags = shortcut.modifiers
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        Log.spaces.info("Switch to space \(target, privacy: .public) via shortcut")
        return true
    }
    
    /**
     * Returns the current space ID from the managed display metadata.
     * This is more reliable after native Mission Control transitions than SLSGetActiveSpace alone.
     */
    private static func getCurrentManagedSpaceID() -> CGSSpaceID? {
        let connection = SLSMainConnectionID()
        
        guard let displaysArray = SLSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return nil
        }
        
        for display in displaysArray {
            if let currentSpace = display["Current Space"] as? [String: Any],
               let id64 = currentSpace["id64"] as? UInt64 {
                return id64
            }
        }
        
        return nil
    }
    
    /**
     * Switches the system to the specified space UUID by finding its current index.
     *
     * - Returns: `false` if the space is unknown or out of reach.
     */
    @discardableResult
    static func switchToSpace(uuid: String) -> Bool {
        let metadata = getAllSpacesMetadata()
        guard let target = metadata.first(where: { $0.uuid == uuid }) else {
            Log.spaces.error("Space uuid \(uuid, privacy: .public) not found")
            return false
        }
        return switchToSpace(index: target.index)
    }
}
