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

@_silgen_name("SLSCopySpacesForWindows")
func SLSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ windowIDs: CFArray) -> CFArray?

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
     * Whether a window configured with `.canJoinAllSpaces` has lost its
     * server-side "all Spaces" tag.
     *
     * After long uptime, macOS can silently strip the sticky tag and pin the
     * window to one arbitrary Space while AppKit still reports the old
     * `collectionBehavior` -- so ordering the window front "succeeds" but it only
     * materialises on that one Space. The visible symptom: the notes panel
     * flashes during a Space transition and vanishes when it settles.
     *
     * A healthy sticky window is a member of *no* specific Space (SkyLight
     * returns an empty list); any non-empty result means the tag is gone.
     * Re-setting the same `collectionBehavior` is a no-op in AppKit, so the only
     * reliable repair is to recreate the window.
     *
     * Returns false whenever SkyLight cannot answer, so a failed lookup never
     * triggers a needless recreate.
     */
    static func windowHasLostAllSpacesTag(windowNumber: Int) -> Bool {
        guard windowNumber > 0 else { return false }
        let connection = SLSMainConnectionID()
        guard let spaces = SLSCopySpacesForWindows(connection, 0x7, [windowNumber] as CFArray) as? [UInt64] else {
            return false
        }
        return !spaces.isEmpty
    }

    /**
     * The highest space index that could ever be jumped to.
     *
     * macOS only defines "Switch to Desktop N" shortcuts for the first ten
     * desktops (symbolic hotkey IDs 118...127), and there is no API to activate a
     * space directly, so nothing beyond Desktop 10 is addressable at all.
     *
     * Being within this range is necessary but *not* sufficient -- the shortcut
     * also has to be enabled. Use `canSwitchToSpace(index:)`.
     *
     * Stepping past Desktop 10 with Ctrl+Left/Right is technically possible but
     * was removed: each transition takes roughly half a second and swallows any
     * arrow key posted while it is in flight, so a multi-step hop lands
     * somewhere arbitrary. Refusing is more useful than guessing.
     */
    static let maxSwitchableSpaceIndex = SpaceShortcuts.maxDesktop

    /**
     * Whether `switchToSpace` can actually reach this index.
     *
     * False when the space is past Desktop 10, and also when the user has no
     * "Switch to Desktop N" shortcut bound for it -- which is the default on a
     * stock macOS install. Callers should check this before offering a space as
     * a jump target rather than posting keystrokes that go nowhere.
     */
    static func canSwitchToSpace(index: Int) -> Bool {
        guard index >= 1 && index <= maxSwitchableSpaceIndex else { return false }
        return SpaceShortcuts.shortcut(forDesktop: index) != nil
    }

    /**
     * Switches the system to the specified space index by replaying the user's
     * own "Switch to Desktop N" shortcut. This triggers the native macOS
     * transition and avoids visual glitches.
     *
     * - Returns: `false` if the space does not exist or has no usable shortcut,
     *   in which case no events are posted.
     */
    @discardableResult
    static func switchToSpace(index: Int) -> Bool {
        let metadata = getAllSpacesMetadata()
        guard metadata.contains(where: { $0.index == index }) else {
            Log.spaces.error("Space index \(index, privacy: .public) not found")
            return false
        }

        guard index <= maxSwitchableSpaceIndex else {
            Log.spaces.notice("Space \(index, privacy: .public) is beyond Desktop \(maxSwitchableSpaceIndex, privacy: .public); macOS defines no shortcut for it, not switching")
            return false
        }

        guard let shortcut = SpaceShortcuts.shortcut(forDesktop: index) else {
            Log.spaces.notice("No 'Switch to Desktop \(index, privacy: .public)' shortcut is enabled in System Settings; not switching")
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)

        keyDown?.flags = shortcut.modifiers
        keyUp?.flags = shortcut.modifiers

        // Post events to the system
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        Log.spaces.info("Triggered switch to space \(index, privacy: .public) via keyCode=\(shortcut.keyCode, privacy: .public) modifiers=\(shortcut.modifiers.rawValue, privacy: .public)")
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
