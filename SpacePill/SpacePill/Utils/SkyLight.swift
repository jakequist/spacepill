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

@_silgen_name("SLSManagedDisplaySetCurrentSpace")
func SLSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ displayUUID: CFString, _ spaceID: UInt64)

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
        let activeID = getActiveSpaceID()
        let allSpaces = getAllSpacesMetadata()
        return allSpaces.first { $0.id == activeID }
    }

    /**
     * Switches the system to the specified space index using simulated keypresses (Ctrl + Number).
     * This triggers the native macOS transition and avoids visual glitches.
     * Note: Requires "Switch to Desktop N" shortcuts to be enabled in System Settings.
     */
    static func switchToSpace(index: Int) {
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
     * Switches the system to the specified space UUID by finding its current index.
     */
    static func switchToSpace(uuid: String) {
        let metadata = getAllSpacesMetadata()
        if let target = metadata.first(where: { $0.uuid == uuid }) {
            switchToSpace(index: target.index)
        }
    }
}
