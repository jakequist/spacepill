import Foundation
import Carbon
import AppKit

class GlobalHotKeyManager: ObservableObject {
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    
    var handlers: [UInt32: () -> Void] = [:]
    
    init() {
        setupGlobalHotkeyListener()
    }
    
    private func setupGlobalHotkeyListener() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerProcPtr = { (nextHandler, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if status == noErr {
                print("SpacePill: Hotkey pressed with ID: \(hotKeyID.id)")
                manager.handlers[hotKeyID.id]?()
            }
            
            return noErr
        }
        
        let status = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
        if status != noErr {
            print("Failed to install event handler: \(status)")
        }
    }
    
    /**
     * Registers a hotkey with a specific ID and handler.
     */
    func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregisterHotKey(id: id)
        
        handlers[id] = handler
        
        var hotKeyID = EventHotKeyID(signature: OSType(123456), id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[id] = ref
            print("SpacePill: Registered hotkey ID \(id) (keyCode: \(keyCode))")
        } else {
            print("SpacePill: Failed to register hotkey ID \(id): \(status)")
        }
    }
    
    func unregisterHotKey(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
            handlers.removeValue(forKey: id)
        }
    }
    
    func unregisterAll() {
        for id in hotKeyRefs.keys {
            unregisterHotKey(id: id)
        }
    }
    
    deinit {
        unregisterAll()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }
}
