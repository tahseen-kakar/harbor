import AppKit
import Foundation

enum FolderSelectionService {
    @MainActor
    static func chooseFolder(startingAt url: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = url
        panel.prompt = "Choose"

        return panel.runModal() == .OK ? panel.url : nil
    }
}
