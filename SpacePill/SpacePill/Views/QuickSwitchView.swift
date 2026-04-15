import SwiftUI

struct QuickSwitchView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var spaceManager: SpaceManager
    var onDismiss: (() -> Void)?
    
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    
    @State private var eventMonitor: Any?
    
    struct MatchItem: Identifiable {
        let id: String // UUID
        let index: Int
        let label: String?
        let color: Color?
    }
    
    private var filteredMatches: [MatchItem] {
        let allSpaces = SkyLight.getAllSpacesMetadata()
        let items = allSpaces.map { metadata in
            let config = settingsManager.spaceConfigs[metadata.uuid]
            return MatchItem(id: metadata.uuid, index: metadata.index, label: config?.label, color: config?.color)
        }
        
        if searchText.isEmpty {
            return items
        }
        
        return items.filter { item in
            let labelMatch = item.label?.localizedCaseInsensitiveContains(searchText) ?? false
            let indexMatch = String(item.index) == searchText
            return labelMatch || indexMatch
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Switch to space...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($isFocused)
                    .onChange(of: searchText) { _ in
                        selectedIndex = 0 // Reset selection on search change
                    }
                    .onSubmit {
                        executeSwitch()
                    }
            }
            .padding()
            
            Divider()
            
            // Results List
            if !filteredMatches.isEmpty {
                ScrollViewReader { proxy in
                    List(Array(filteredMatches.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            // Number Circle
                            Text("\(item.index)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(item.color ?? Color.gray)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                            
                            Text(item.label ?? "Space \(item.index)")
                                .font(.system(size: 14, weight: index == selectedIndex ? .bold : .regular))
                            
                            Spacer()
                            
                            if index == selectedIndex {
                                Text("⏎")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: index == selectedIndex ? 1 : 0)
                        )
                        .id(index)
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 350)
                    .onChange(of: selectedIndex) { newValue in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            } else {
                Text("No matching spaces")
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            Divider()
            
            // Helper Hint
            HStack {
                Text("↑↓ to navigate • ⏎ to switch • ESC to close")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 400)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .onAppear {
            selectedIndex = 0
            isFocused = true
            setupEventMonitor()
        }
        .onDisappear {
            print("SpacePill: QuickSwitchView disappearing, removing monitor")
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }
    
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // CRITICAL: Only handle events if this view is actually focused and in the key window.
            // AND ensure the event is targeted at the window containing this view.
            guard isFocused, 
                  let keyWindow = NSApp.keyWindow,
                  event.window == keyWindow else { 
                return event 
            }
            
            // Key codes: 125=down, 126=up, 36=enter, 53=esc
            switch event.keyCode {
            case 125: // Down
                selectedIndex = min(selectedIndex + 1, filteredMatches.count - 1)
                return nil
            case 126: // Up
                selectedIndex = max(selectedIndex - 1, 0)
                return nil
            case 36: // Enter
                executeSwitch()
                return nil
            case 53: // ESC
                onDismiss?()
                return nil
            default:
                return event
            }
        }
    }
    
    private func executeSwitch() {
        guard !filteredMatches.isEmpty else { return }
        let item = filteredMatches[selectedIndex]
        print("SpacePill: QuickSwitch triggering switch to space \(item.index)")
        SkyLight.switchToSpace(uuid: item.id)
        onDismiss?()
    }
}
