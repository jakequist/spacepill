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
        // Follow the visual space so notes update as soon as a native transition starts.
        spaceManager.$visualSpaceIndex
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

    /**
     * Where a space's notes live on disk, without creating anything.
     *
     * Reporting a path should not have the side effect of making directories,
     * so this deliberately does not call `getNotesURL`.
     */
    func notesURL(forSpace index: Int) -> URL {
        baseDirectory
            .appendingPathComponent("space_\(index)", isDirectory: true)
            .appendingPathComponent("notes.md")
    }

    /**
     * Notes for an arbitrary space, for callers outside the notes panel.
     *
     * The current space is answered from memory: the panel may hold edits that
     * have not been flushed yet, and reading the file would return stale text.
     */
    func notes(forSpace index: Int) -> String {
        if index == currentSpaceIndex { return currentNotes }
        return (try? String(contentsOf: notesURL(forSpace: index), encoding: .utf8)) ?? ""
    }

    /**
     * Replaces a space's notes. Writing the current space also updates the
     * published copy so an open notes panel redraws instead of overwriting the
     * new text on its next save.
     */
    func setNotes(_ text: String, forSpace index: Int) {
        if index == currentSpaceIndex {
            currentNotes = text
        }
        saveNotes(text, for: index)
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
