import SwiftUI
import SpacePillCore

struct QuickSwitchView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var spaceManager: SpaceManager
    var onDismiss: (() -> Void)?
    
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    
    @State private var eventMonitor: Any?

    /// Seeded at construction so the first render is already correct, then
    /// refreshed on appear to catch changes made while SpacePill was running.
    @State private var reachableDesktops: Set<Int> = SpaceShortcuts.reachableDesktops()
    
    struct MatchItem: Identifiable {
        let id: String // UUID
        let index: Int
        let label: String?
        let color: Color?

        /// Resolved when the list is built, from view state -- not queried live,
        /// so that re-reading System Settings actually re-renders the rows.
        let isReachable: Bool

        /// What the row shows, and therefore what the search matches against:
        /// an unlabelled space is only findable as "Space N" if we search the
        /// same string the user is reading.
        var displayName: String {
            SpaceSearch.displayName(index: index, label: label)
        }

        /// Why this space can't be jumped to, for the footer hint.
        var unreachableReason: String? {
            guard !isReachable else { return nil }
            if index > SkyLight.maxSwitchableSpaceIndex {
                return "Can't jump here — macOS has no shortcut past Desktop \(SkyLight.maxSwitchableSpaceIndex)"
            }
            return "Enable “Switch to Desktop \(index)” in Keyboard Shortcuts to jump here"
        }
    }

    private var filteredMatches: [MatchItem] {
        let allSpaces = SkyLight.getAllSpacesMetadata()
        let items = allSpaces.map { metadata in
            let config = settingsManager.spaceConfigs[metadata.uuid]
            return MatchItem(
                id: metadata.uuid,
                index: metadata.index,
                label: config?.label,
                color: config?.color,
                isReachable: reachableDesktops.contains(metadata.index)
            )
        }
        
        // Fuzzy, ranked, and deterministic -- see SpacePillCore.SpaceSearch.
        // Best match first, so resetting selectedIndex to 0 on every keystroke
        // lands on the row the user most likely meant.
        return SpaceSearch.rank(items,
                                query: searchText,
                                index: { $0.index },
                                displayName: { $0.displayName })
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

                            Text(item.displayName)
                                .font(.system(size: 14, weight: index == selectedIndex ? .bold : .regular))

                            Spacer()

                            if !item.isReachable {
                                Image(systemName: "nosign")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            } else if index == selectedIndex {
                                Text("⏎")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                            }
                        }
                        .opacity(item.isReachable ? 1.0 : 0.4)
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
                if let reason = selectedItem?.unreachableReason {
                    // Keep this to one line: the popover height is fixed, and a
                    // wrapped hint crowds the last row of the list.
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else {
                    Text("↑↓ to navigate • ⏎ to switch • ESC to close")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 400)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .onAppear {
            // Re-read System Settings so shortcuts enabled since launch are
            // reflected without restarting SpacePill.
            SpaceShortcuts.refresh()
            reachableDesktops = SpaceShortcuts.reachableDesktops()
            selectedIndex = 0
            isFocused = true
            setupEventMonitor()
        }
        .onDisappear {
            Log.ui.debug("QuickSwitchView disappearing, removing key monitor")
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
    
    private var selectedItem: MatchItem? {
        let matches = filteredMatches
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex]
    }

    private func executeSwitch() {
        guard let item = selectedItem else { return }

        // Don't post keystrokes we know macOS will ignore -- landing on an
        // arbitrary space is worse than staying put. The footer already
        // explains why this row is disabled.
        guard item.isReachable else {
            Log.ui.notice("QuickSwitch ignoring unreachable space \(item.index, privacy: .public)")
            return
        }

        Log.ui.info("QuickSwitch requesting switch to space \(item.index, privacy: .public)")
        SkyLight.switchToSpace(uuid: item.id)
        onDismiss?()
    }
}
