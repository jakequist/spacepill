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
     * Switches the system to the specified space index using simulated keypresses.
     * This triggers the native macOS transition and avoids visual glitches.
     * Note: Requires "Switch to Desktop N" and "Move left/right a space" shortcuts to be enabled in System Settings.
     * macOS only exposes number-key shortcuts for Desktop 1 through Desktop 10.
     * For higher-numbered spaces, step with Ctrl+Left/Right.
     */
    static func switchToSpace(index: Int) {
        let metadata = getAllSpacesMetadata()
        guard metadata.contains(where: { $0.index == index }) else {
            print("SpacePill: Space index \(index) not found")
            return
        }
        
        if index > 10 {
            switchToSpaceByStepping(to: index)
            return
        }
        
        let keyCodes: [Int: UInt16] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
            6: 22, 7: 26, 8: 28, 9: 25, 10: 29
        ]
        
        guard let keyCode = keyCodes[index] else {
            print("SpacePill: Space index \(index) out of range for shortcut switching")
            return
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
        
        print("SpacePill: Triggered switch to space \(index) via Ctrl+\(index)")
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
     * Reaches spaces beyond Desktop 10 using the native left/right shortcuts.
     */
    private static func switchToSpaceByStepping(to targetIndex: Int) {
        guard let currentIndex = getActiveSpaceMetadata()?.index else {
            print("SpacePill: Could not determine current space for stepped switch")
            return
        }
        
        let delta = targetIndex - currentIndex
        guard delta != 0 else { return }
        
        let keyCode: UInt16 = delta > 0 ? 124 : 123 // right : left
        let steps = abs(delta)
        
        for step in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.22 * Double(step))) {
                postControlKey(keyCode)
            }
        }
        
        print("SpacePill: Triggered switch from space \(currentIndex) to \(targetIndex) via Ctrl+\(delta > 0 ? "Right" : "Left") x\(steps)")
    }
    
    private static func postControlKey(_ keyCode: UInt16) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        
        keyDown?.flags = .maskControl
        keyUp?.flags = .maskControl
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    /**
     * Switches the system to the specified space UUID by finding its current index.
     */
    static func switchToSpace(uuid: String) {
        let metadata = getAllSpacesMetadata()
        if let target = metadata.first(where: { $0.uuid == uuid }) {
            switchToSpace(index: target.index)
        }
    }
}
