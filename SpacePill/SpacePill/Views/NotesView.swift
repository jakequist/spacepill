import SwiftUI

struct NotesView: View {
    @ObservedObject var notesManager: NotesManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var contentHeight: CGFloat = 100
    
    var borderColor: Color {
        if settingsManager.matchSpaceColorForNotesBorder,
           let uuid = spaceManager.currentSpaceUUID,
           let config = settingsManager.spaceConfigs[uuid],
           let color = config.color {
            return color
        }
        return Color.primary.opacity(0.1)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            MarkdownEditor(
                text: Binding(
                    get: { notesManager.currentNotes },
                    set: { newValue in
                        notesManager.currentNotes = newValue
                        notesManager.saveNotes(newValue)
                    }
                ),
                height: $contentHeight,
                scrollPosition: Binding(
                    get: {
                        if let uuid = spaceManager.currentSpaceUUID {
                            return settingsManager.spaceConfigs[uuid]?.scrollPosition ?? 0.0
                        }
                        return 0.0
                    },
                    set: { newValue in
                        if let uuid = spaceManager.currentSpaceUUID {
                            settingsManager.setScrollPosition(for: uuid, position: newValue)
                        }
                    }
                ),
                spaceUUID: spaceManager.currentSpaceUUID ?? ""
            )
            .padding(8)
        }
        .frame(height: min(max(contentHeight, 100), CGFloat(settingsManager.maxNotesHeight)))
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: settingsManager.matchSpaceColorForNotesBorder ? 3 : 1)
        )
        .onChange(of: contentHeight) { _ in
            NotificationCenter.default.post(name: Notification.Name("NotesWindowShouldResize"), object: nil)
        }
    }
}
