import Foundation

public enum ProjectError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public enum ProjectStore {
    public static func create(_ project: Project, at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw ProjectError.invalid("A project already exists here. Choose a different name.") }
        try FileManager.default.createDirectory(at: url.appendingPathComponent("captures"), withIntermediateDirectories: true)
        try save(project, at: url)
    }
    public static func save(_ project: Project, at url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        let destination = url.appendingPathComponent("project.json")
        // Keep the previous valid document for recovery; replace the current document atomically.
        if let previous = try? Data(contentsOf: destination), (try? decode(previous)) != nil {
            try previous.write(to: url.appendingPathComponent("project.backup.json"), options: .atomic)
        }
        try data.write(to: destination, options: .atomic)
    }
    public static func load(at url: URL) throws -> Project {
        try decode(Data(contentsOf: url.appendingPathComponent("project.json")))
    }
    public static func recover(at url: URL) throws -> Project {
        try decode(Data(contentsOf: url.appendingPathComponent("project.backup.json")))
    }
    private static func decode(_ data: Data) throws -> Project {
        let decoder = JSONDecoder()
        let project: Project
        do { project = try decoder.decode(Project.self, from: data) }
        catch { decoder.dateDecodingStrategy = .iso8601; project = try decoder.decode(Project.self, from: data) }
        guard project.version == 1 else { throw ProjectError.invalid("This project was made with a newer version of Framepad.") }
        let ids = project.boxes.map(\.id) + project.items.compactMap { if case .group(let g) = $0 { return g.id }; return nil }
        guard Set(ids).count == ids.count else { throw ProjectError.invalid("This project contains duplicate annotation identifiers.") }
        guard project.lastPosition.isFinite, project.lastPosition >= 0 else { throw ProjectError.invalid("This project contains an invalid playhead position.") }
        let crops = project.boxes.compactMap(\.crop) + [project.draftCrop].compactMap { $0 }
        for crop in crops {
            guard [crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite), crop.x >= 0, crop.y >= 0, crop.width >= 0, crop.height >= 0,
                  crop.x + crop.width <= 1.000001, crop.y + crop.height <= 1.000001 else { throw ProjectError.invalid("This project contains an invalid crop rectangle.") }
        }
        for b in project.boxes {
            guard b.time.timescale > 0, b.time.value >= 0, b.frameIndex >= 0 else { throw ProjectError.invalid("This project contains an invalid frame timestamp.") }
            if let file = b.imageFile {
                guard file == URL(fileURLWithPath: file).lastPathComponent, !file.contains("..") else { throw ProjectError.invalid("This project contains an invalid capture filename.") }
            }
        }
        return project
    }
    public static func captureURL(_ filename: String, in projectURL: URL) -> URL {
        projectURL.appendingPathComponent("captures").appendingPathComponent(URL(fileURLWithPath: filename).lastPathComponent)
    }
}
