import Foundation
import FramepadCore

/// Metadata and backup I/O never occupy the UI thread during normal autosaves.
final class ProjectWriter {
    private let queue = DispatchQueue(label: "app.framepad.project-writer", qos: .userInitiated)
    func save(_ project: Project, at url: URL, completion: @escaping (Error?) -> Void) {
        queue.async {
            let error: Error?
            do { try ProjectStore.save(project, at: url); error = nil } catch let failure { error = failure }
            DispatchQueue.main.async { completion(error) }
        }
    }
    func flush(_ project: Project, at url: URL) throws {
        try queue.sync { try ProjectStore.save(project, at: url) }
    }
}
