import SwiftUI

struct QuickEditView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var label: String = ""
    @State private var selectedColor: Color = Color(hex: "007AFF")
    
    var onDismiss: (() -> Void)?
    
    private let presetColors: [Color] = [
        Color(hex: "007AFF"), // Blue
        Color(hex: "FF3B30"), // Red
        Color(hex: "34C759"), // Green
        Color(hex: "FF9500"), // Orange
        Color(hex: "AF52DE"), // Purple
        Color(hex: "FF2D55"), // Pink
        Color(hex: "8E8E93")  // Gray
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            if let index = spaceManager.currentSpaceIndex {
                Text("Edit Space \(index)")
                    .font(.headline)
                    .padding(.bottom, 4)
            } else {
                Text("Loading Space...")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            
            TextField("Label (e.g. Work, Personal)", text: $label)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 250)
            
            HStack(spacing: 10) {
                ForEach(presetColors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: selectedColor.toHex() == color.toHex() ? 2 : 0)
                        )
                        .onTapGesture {
                            selectedColor = color
                        }
                }
                
                ColorPicker("", selection: $selectedColor)
                    .labelsHidden()
            }
            .padding(.vertical, 4)
            
            HStack {
                Button("Clear") {
                    if let uuid = spaceManager.currentSpaceUUID {
                        print("SpacePill: Clear button clicked for space \(uuid)")
                        settingsManager.clearConfig(for: uuid)
                        onDismiss?()
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                
                Spacer()
                
                Button("Save") {
                    if let uuid = spaceManager.currentSpaceUUID {
                        print("SpacePill: Save button clicked for space \(uuid)")
                        settingsManager.setConfig(for: uuid, label: label, hexColor: selectedColor.toHex())
                        onDismiss?()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .onAppear(perform: loadCurrentConfig)
        .onChange(of: spaceManager.currentSpaceUUID) { _ in
            loadCurrentConfig()
        }
        .frame(width: 300)
    }
    
    private func loadCurrentConfig() {
        if let uuid = spaceManager.currentSpaceUUID,
           let config = settingsManager.spaceConfigs[uuid] {
            label = config.label ?? ""
            selectedColor = config.color ?? Color(hex: "007AFF")
        } else {
            label = ""
            selectedColor = findNextUnusedColor()
        }
    }
    
    /**
     * Finds the first color in the preset list that isn't already assigned to a space.
     * Uses hex comparison for reliability.
     */
    private func findNextUnusedColor() -> Color {
        let usedHexColors = Set(settingsManager.spaceConfigs.values.compactMap { $0.hexColor?.uppercased() })
        
        for preset in presetColors {
            if let hex = preset.toHex()?.uppercased(), !usedHexColors.contains(hex) {
                return preset
            }
        }
        
        return presetColors.first ?? Color(hex: "007AFF")
    }
}
