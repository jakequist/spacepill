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
                Log.hotkeys.debug("Hotkey fired, id=\(hotKeyID.id, privacy: .public)")
                manager.handlers[hotKeyID.id]?()
            }
            
            return noErr
        }
        
        let status = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
        if status != noErr {
            Log.hotkeys.error("InstallEventHandler failed, status=\(status, privacy: .public)")
        }
    }
    
    /**
     * Registers a hotkey with a specific ID and handler.
     */
    func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregisterHotKey(id: id)
        
        handlers[id] = handler
        
        let hotKeyID = EventHotKeyID(signature: OSType(123456), id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[id] = ref
            Log.hotkeys.info("Registered hotkey id=\(id, privacy: .public) keyCode=\(keyCode, privacy: .public) modifiers=\(modifiers, privacy: .public)")
        } else {
            // -9878 (eventHotKeyExistsErr) means this key combination is already
            // claimed — by another app, or by a stale registration of our own.
            Log.hotkeys.error("RegisterEventHotKey failed id=\(id, privacy: .public) keyCode=\(keyCode, privacy: .public) status=\(status, privacy: .public)")
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
