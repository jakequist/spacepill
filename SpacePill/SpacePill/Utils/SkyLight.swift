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

// EXPERIMENTAL. Sets the active Space of a display directly, the way yabai does
// it internally. Unlike the keyboard-shortcut method this reaches *any* Space --
// including Desktop 11+, which macOS defines no shortcut for -- needs none of the
// "Switch to Desktop" shortcuts enabled, and does not require SIP to be disabled.
@_silgen_name("SLSManagedDisplaySetCurrentSpace")
func SLSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString, _ space: CGSSpaceID)

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
     * Whether `switchToSpace` can reach this index.
     *
     * With the direct SkyLight method (see `switchToSpaceDirect`), any Space that
     * exists is reachable -- there is no Desktop-10 ceiling and no dependency on
     * the "Switch to Desktop" shortcuts being enabled. So this is now simply
     * "does a Space with this index exist".
     */
    static func canSwitchToSpace(index: Int) -> Bool {
        guard index >= 1 else { return false }
        return getAllSpacesMetadata().contains { $0.index == index }
    }

    /**
     * Switch to a Space by index.
     *
     * Uses the direct SkyLight call, which reaches any Space (including Desktop
     * 11+) without the "Switch to Desktop" shortcuts and without disabling SIP.
     * Falls back to replaying the keyboard shortcut only if the direct call is
     * somehow unavailable.
     *
     * - Returns: `false` if no Space with this index exists.
     */
    @discardableResult
    static func switchToSpace(index: Int) -> Bool {
        let metadata = getAllSpacesMetadata()
        guard let target = metadata.first(where: { $0.index == index }) else {
            Log.spaces.error("Space index \(index, privacy: .public) not found")
            return false
        }

        if switchToSpaceDirect(target: target) {
            return true
        }
        Log.spaces.notice("Direct switch unavailable; falling back to keyboard shortcut")
        return switchToSpaceViaShortcut(index: index)
    }

    /**
     * EXPERIMENTAL: switch directly via `SLSManagedDisplaySetCurrentSpace`.
     *
     * This is the mechanism that lifts the Desktop-10 ceiling and removes the
     * need for the user to enable any macOS shortcut. It sets the display's
     * current Space at the window-server level.
     */
    @discardableResult
    static func switchToSpaceDirect(target: SpaceMetadata) -> Bool {
        let cid = SLSMainConnectionID()
        SLSManagedDisplaySetCurrentSpace(cid, target.displayUUID as CFString, target.id)
        Log.spaces.info("Direct switch to space \(target.index, privacy: .public) id64=\(target.id, privacy: .public)")
        return true
    }

    /**
     * The original keyboard-shortcut method: replay the user's "Switch to
     * Desktop N" shortcut. Kept as a fallback; only reaches Desktops 1-10 and
     * only when the shortcut is enabled.
     */
    @discardableResult
    static func switchToSpaceViaShortcut(index: Int) -> Bool {
        guard index <= maxSwitchableSpaceIndex,
              let shortcut = SpaceShortcuts.shortcut(forDesktop: index) else {
            Log.spaces.notice("No usable 'Switch to Desktop \(index, privacy: .public)' shortcut; not switching")
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        keyDown?.flags = shortcut.modifiers
        keyUp?.flags = shortcut.modifiers
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        Log.spaces.info("Triggered switch to space \(index, privacy: .public) via keyCode=\(shortcut.keyCode, privacy: .public)")
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
