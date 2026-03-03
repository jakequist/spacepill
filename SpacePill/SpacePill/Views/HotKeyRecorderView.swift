import SwiftUI
import AppKit
import Carbon

struct HotKeyRecorderView: View {
    @Binding var hotkey: HotKeyConfig
    @State private var isRecording = false
    @State private var monitor: Any?
    
    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            Text(isRecording ? "Type Hotkey..." : hotkey.displayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(minWidth: 120)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isRecording ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                return event
            }
            
            if event.type == .keyDown {
                // Escape to cancel
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                
                // Require at least one modifier
                if !modifiers.isEmpty {
                    var carbonModifiers: UInt32 = 0
                    if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
                    if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
                    if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
                    if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
                    
                    self.hotkey = HotKeyConfig(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
                    stopRecording()
                    return nil
                }
                
                // If no modifiers, only allow escape or don't record
                return nil
            }
            
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
