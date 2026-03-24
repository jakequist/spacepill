import Foundation
import Combine

class NotesManager: ObservableObject {
    @Published var currentNotes: String = ""
    private var currentSpaceIndex: Int?
    private var cancellables = Set<AnyCancellable>()
    
    private let baseDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".spacepill", isDirectory: true)
    }()
    
    init(spaceManager: SpaceManager) {
        // Observe space changes to load corresponding notes
        spaceManager.$currentSpaceIndex
            .sink { [weak self] index in
                if let index = index {
                    self?.loadNotes(for: index)
                }
            }
            .store(in: &cancellables)
    }
    
    private func getNotesURL(for index: Int) -> URL {
        let spaceDir = baseDirectory.appendingPathComponent("space_\(index)", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: spaceDir, withIntermediateDirectories: true)
        
        return spaceDir.appendingPathComponent("notes.md")
    }
    
    func loadNotes(for index: Int) {
        // Save current notes before switching if necessary (optional since we auto-persist)
        if let oldIndex = currentSpaceIndex, oldIndex != index {
            saveNotes(currentNotes, for: oldIndex)
        }
        
        currentSpaceIndex = index
        let url = getNotesURL(for: index)
        
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            currentNotes = content
        } else {
            currentNotes = ""
        }
    }
    
    func saveNotes(_ content: String, for index: Int? = nil) {
        guard let index = index ?? currentSpaceIndex else { return }
        let url = getNotesURL(for: index)
        
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func saveCurrentNotes() {
        saveNotes(currentNotes)
    }
}
