import Foundation
import CoreGraphics

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
                    if let id64 = space["id64"] as? UInt64,
                       let uuid = space["uuid"] as? String {
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
     * The highest space index SpacePill can jump to directly.
     *
     * There is no API to activate a space, so switching means simulating the
     * user's own "Switch to Desktop N" shortcut. macOS only defines ten of
     * those -- Ctrl+1..Ctrl+9 and Ctrl+0 for Desktop 10 (symbolic hotkey IDs
     * 118...127). Nothing above Desktop 10 is addressable.
     *
     * Stepping there with Ctrl+Left/Right is technically possible but was
     * removed: each transition takes roughly half a second and swallows any
     * arrow key posted while it is in flight, so a multi-step hop lands
     * somewhere arbitrary. Refusing is more useful than guessing.
     */
    static let maxSwitchableSpaceIndex = 10

    /// Ctrl+<number> virtual key codes for Desktop 1...10 (Desktop 10 is Ctrl+0).
    private static let switchKeyCodes: [Int: UInt16] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
        6: 22, 7: 26, 8: 28, 9: 25, 10: 29
    ]

    /**
     * Whether `switchToSpace` can actually reach this index.
     * Callers should check this before offering a space as a jump target.
     */
    static func canSwitchToSpace(index: Int) -> Bool {
        index >= 1 && index <= maxSwitchableSpaceIndex
    }

    /**
     * Switches the system to the specified space index using simulated keypresses.
     * This triggers the native macOS transition and avoids visual glitches.
     *
     * Also requires the matching "Switch to Desktop N" shortcut to be enabled in
     * System Settings -> Keyboard -> Keyboard Shortcuts -> Mission Control. That
     * cannot be detected reliably, so a switch that silently does nothing is
     * usually a disabled shortcut rather than a failure here.
     *
     * - Returns: `false` if the space does not exist or is out of reach, in
     *   which case no events are posted.
     */
    @discardableResult
    static func switchToSpace(index: Int) -> Bool {
        let metadata = getAllSpacesMetadata()
        guard metadata.contains(where: { $0.index == index }) else {
            Log.spaces.error("Space index \(index, privacy: .public) not found")
            return false
        }

        guard let keyCode = switchKeyCodes[index] else {
            Log.spaces.notice("Space \(index, privacy: .public) is beyond Desktop \(maxSwitchableSpaceIndex, privacy: .public); macOS defines no shortcut for it, not switching")
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)

        // Create Control + [Number] events
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = .maskControl
        keyUp?.flags = .maskControl

        // Post events to the system
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        Log.spaces.info("Triggered switch to space \(index, privacy: .public) via Ctrl+\(index % 10, privacy: .public)")
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
