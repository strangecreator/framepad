import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FramepadCore

extension UTType { static let framepadProject = UTType(exportedAs: "app.framepad.project", conformingTo: .package) }

struct RecentProject: Codable, Identifiable {
    var path: String
    var title: String
    var videoName: String
    var modified: Date
    var count: Int
    var bookmark: Data?
    var id: String { path }
}

struct DraftState {
    var position: Double
    var prompt: String
    var crop: CropRect?
    var playing: Bool
}

struct EditorState {
    var prompt: String
    var crop: CropRect?
    var cropMode: Bool
    var boxID: UUID?
    var groupID: UUID?
    var draft: DraftState?
    var position: Double
}
struct UndoEntry {
    var project: Project
    var editor: EditorState
}

@MainActor final class AppModel: ObservableObject {
    @Published var project: Project? {
        didSet {
            if oldValue?.items != project?.items {
                collectionRows = CollectionRow.build(project?.items ?? [])
                let boxes = project?.boxes ?? []
                markerTimes = boxes.map { $0.time.seconds }
                boxCount = boxes.count
            }
        }
    }
    private(set) var collectionRows: [CollectionRow] = []
    private(set) var markerTimes: [Double] = []
    private(set) var boxCount = 0
    @Published var projectURL: URL?
    @Published var recents: [RecentProject] = []
    @Published var prompt = "" {
        didSet {
            guard prompt != oldValue, !suppressAutosave else { return }
            if let id = selectedBoxID { beginTextChange(key: id.uuidString, previousPrompt: oldValue) }
            scheduleAutosave()
        }
    }
    @Published var crop: CropRect? { didSet { scheduleAutosave() } }
    @Published var cropMode = false
    @Published var selectedBoxID: UUID?
    @Published var selectedGroupID: UUID?
    @Published var isSaving = false
    @Published var saveStatus = "All changes saved"
    @Published var toast: String?
    @Published var errorMessage: String?
    @Published var missingVideo = false
    @Published var scrollTarget: UUID?
    @Published var scrollRevision = 0
    private(set) var scrollStyle = CollectionScrollStyle.bottom
    var collectionViewport = CollectionViewport()
    @Published var showShortcuts = false
    let video = VideoEngine()
    var draftBeforeEditing: DraftState?
    var undoHistory: [UndoEntry] = []
    var redoHistory: [UndoEntry] = []
    private var pendingTextChange: (key: String, entry: UndoEntry)?
    private let writer = ProjectWriter()
    private var saveRevision = 0
    private var autosaveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var videoAccess: URL?
    private var projectAccess: URL?
    private var suppressAutosave = false
    var hasProject: Bool { project != nil }
    var canSave: Bool { project != nil && video.ready && !isSaving && !missingVideo }

    init() {
        if let data = UserDefaults.standard.data(forKey: "recentProjects"), let values = try? JSONDecoder().decode([RecentProject].self, from: data) { recents = values }
        video.errorHandler = { [weak self] message in self?.errorMessage = message }
        video.indexReadyHandler = { [weak self] index in
            guard let self, var document = self.project, document.reconcileFrameIndices(using: index) else { return }
            self.project = document; _ = self.persist()
        }
    }

    func newProject() {
        guard !isSaving, flush() else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a video"; panel.message = "One video, a whole new perspective. Your video stays in its original location."
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let videoURL = panel.url else { return }
        let save = NSSavePanel()
        save.title = "Save your project"; save.message = "The project contains your annotations and captured frames. It references the original video."
        save.allowedContentTypes = [.framepadProject]; save.nameFieldStringValue = videoURL.deletingPathExtension().lastPathComponent + ".framepad"
        save.canCreateDirectories = true
        guard save.runModal() == .OK, let url = save.url else { return }
        do {
            let title = url.deletingPathExtension().lastPathComponent
            let document = Project(title: title, videoPath: videoURL.path, videoBookmark: try? videoURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
            try ProjectStore.create(document, at: url)
            load(document, from: url)
        } catch { errorMessage = error.localizedDescription }
    }
    func openProject() {
        guard !isSaving, flush() else { return }
        let panel = NSOpenPanel(); panel.title = "Open a Framepad project"
        panel.allowedContentTypes = [.framepadProject]; panel.canChooseDirectories = false; panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }
    func openRecent(_ recent: RecentProject) {
        var stale = false
        let resolved = recent.bookmark.flatMap { try? URL(resolvingBookmarkData: $0, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) }
        open(resolved ?? URL(fileURLWithPath: recent.path))
    }
    func open(_ url: URL) {
        guard !isSaving, flush() else { return }
        do { load(try ProjectStore.load(at: url), from: url) }
        catch {
            if let recovered = try? ProjectStore.recover(at: url) {
                let alert = NSAlert(); alert.messageText = "Recover this project?"
                alert.informativeText = "The current project file could not be opened. A previous saved version is available. Recovering it preserves the unreadable file for inspection."
                alert.addButton(withTitle: "Recover"); alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    do {
                        let broken = url.appendingPathComponent("project.json")
                        if FileManager.default.fileExists(atPath: broken.path) {
                            try FileManager.default.copyItem(at: broken, to: url.appendingPathComponent("project.unreadable-\(UUID().uuidString).json"))
                        }
                        try ProjectStore.save(recovered, at: url); load(recovered, from: url)
                        notify("Recovered the previous saved version")
                    } catch { errorMessage = error.localizedDescription }
                }
            } else { errorMessage = "Could not open the project. \(error.localizedDescription)" }
        }
    }
    func load(_ document: Project, from url: URL) {
        autosaveTask?.cancel(); suppressAutosave = true
        video.close(); videoAccess?.stopAccessingSecurityScopedResource(); projectAccess?.stopAccessingSecurityScopedResource()
        projectAccess = url; _ = url.startAccessingSecurityScopedResource()
        project = document; projectURL = url; prompt = document.draft; crop = document.draftCrop
        selectedBoxID = nil; selectedGroupID = nil; draftBeforeEditing = nil; cropMode = false; undoHistory = []; redoHistory = []; pendingTextChange = nil
        scrollTarget = nil; scrollRevision += 1; collectionViewport = CollectionViewport()
        saveRevision += 1
        saveStatus = "All changes saved"; suppressAutosave = false
        var stale = false
        let resolved = document.videoBookmark.flatMap { try? URL(resolvingBookmarkData: $0, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) }
        let media = resolved ?? URL(fileURLWithPath: document.videoPath)
        missingVideo = !FileManager.default.fileExists(atPath: media.path)
        if !missingVideo {
            videoAccess = media; _ = media.startAccessingSecurityScopedResource()
            if media.path != document.videoPath { project?.videoPath = media.path; project?.videoBookmark = try? media.bookmarkData() }
            video.open(media, projectURL: url, at: document.lastPosition)
        }
        recordRecent()
    }
    func relinkVideo() {
        guard !isSaving, let project, let projectURL else { return }
        let panel = NSOpenPanel(); panel.title = "Locate \(URL(fileURLWithPath: project.videoPath).lastPathComponent)"
        panel.message = "Choose the same source video so existing frame numbers and timestamps stay aligned."
        panel.allowedContentTypes = [.movie, .video]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        videoAccess?.stopAccessingSecurityScopedResource(); videoAccess = url; _ = url.startAccessingSecurityScopedResource()
        self.project?.videoPath = url.path; self.project?.videoBookmark = try? url.bookmarkData()
        missingVideo = false; video.open(url, projectURL: projectURL, at: project.lastPosition)
        _ = persist()
    }
    func goHome() {
        guard !isSaving, flush() else { return }
        autosaveTask?.cancel(); suppressAutosave = true
        video.close(); project = nil; projectURL = nil; selectedBoxID = nil; selectedGroupID = nil; draftBeforeEditing = nil
        toastTask?.cancel(); toast = nil
        prompt = ""; crop = nil; suppressAutosave = false
        videoAccess?.stopAccessingSecurityScopedResource(); projectAccess?.stopAccessingSecurityScopedResource()
        videoAccess = nil; projectAccess = nil
    }
    func selectBox(_ box: VBox) {
        guard !isSaving, selectedBoxID != box.id else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        finishTextEditing()
        if selectedBoxID == nil { draftBeforeEditing = DraftState(position: video.position, prompt: prompt, crop: crop, playing: video.playing) }
        suppressAutosave = true
        selectedBoxID = box.id; prompt = box.prompt; crop = box.crop; cropMode = false
        suppressAutosave = false; video.pause(); video.seek(box.time.seconds)
    }
    func returnToDraft(clearGroup: Bool = false) {
        guard !isSaving else { return }
        finishTextEditing()
        suppressAutosave = true
        selectedBoxID = nil
        if let draft = draftBeforeEditing {
            prompt = draft.prompt; crop = draft.crop; video.seek(draft.position)
            if draft.playing && !video.playing { video.toggle() }
        }
        draftBeforeEditing = nil; cropMode = false
        if clearGroup { selectedGroupID = nil }
        suppressAutosave = false; _ = persist()
    }
    func selectGroup(_ id: UUID, toggle: Bool = true) {
        guard !isSaving else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        returnToDraft(); selectedGroupID = toggle && selectedGroupID == id ? nil : id
    }
    func createGroup(withBox boxID: UUID? = nil) {
        guard !isSaving, project != nil else { return }
        returnToDraft(); rememberUndo()
        let group = VBoxGroup(title: "Group \((project?.groupCount ?? 0) + 1)")
        withAnimation(.snappy(duration: 0.25)) {
            project?.items.append(.group(group))
            if let boxID { project?.moveBox(boxID, to: group.id) }
            selectedGroupID = group.id
        }
        requestCollectionScroll(to: boxID ?? group.id)
        _ = persist(); notify("Group created · new vboxes will land here")
    }
    func groupBinding(_ id: UUID, title: Bool) -> Binding<String> {
        Binding(get: { [weak self] in
            guard let item = self?.project?.items.first(where: { $0.id == id }), case .group(let group) = item else { return "" }
            return title ? group.title : group.prompt
        }, set: { [weak self] value in
            guard let self, !self.isSaving else { return }
            self.beginTextChange(key: id.uuidString + (title ? "-title" : "-prompt"))
            self.project?.updateGroup(id, title: title ? value : nil, prompt: title ? nil : value)
            self.scheduleAutosave()
        })
    }
    func moveBox(_ id: UUID, to groupID: UUID?) {
        guard !isSaving, project?.box(id) != nil, project?.group(containing: id) != groupID else { return }
        if let groupID, !(project?.items.contains { if case .group(let group) = $0 { return group.id == groupID }; return false } ?? false) { return }
        rememberUndo()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { project?.moveBox(id, to: groupID) }
        requestCollectionScroll(to: id)
        _ = persist(); notify(groupID == nil ? "Moved out of group" : "Moved into group")
    }
    func ungroup(_ id: UUID) {
        guard !isSaving else { return }
        rememberUndo(); withAnimation { project?.ungroup(id) }
        if selectedGroupID == id { selectedGroupID = nil }
        _ = persist(); notify("Group removed · vboxes kept")
    }
    func deleteBox(_ id: UUID) {
        guard !isSaving, project?.box(id) != nil else { return }
        rememberUndo()
        if selectedBoxID == id { returnToDraft() }
        withAnimation { _ = project?.removeBox(id) }; _ = persist(); notify("Vbox deleted · ⌘Z to undo")
    }
    func deleteGroup(_ id: UUID) {
        guard !isSaving, let item = project?.items.first(where: { $0.id == id }), case .group(let group) = item else { return }
        rememberUndo()
        if let selectedBoxID, group.boxes.contains(where: { $0.id == selectedBoxID }) { returnToDraft() }
        if selectedGroupID == id { selectedGroupID = nil }
        withAnimation { project?.items.removeAll { $0.id == id } }
        _ = persist(); notify("Group and \(group.boxes.count) vboxes removed · ⌘Z to undo")
    }
    func saveBox(promptOnly: Bool = false) {
        guard canSave, let url = projectURL else { return }
        if promptOnly && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notify("Write a note before saving a prompt-only vbox"); return }
        guard let frame = video.freezeFrameForCapture() else { return }
        let index = frame.index
        let existingID = selectedBoxID
        let original = existingID.flatMap { project?.box($0) }
        let capturedPrompt = prompt, capturedCrop = crop, groupID = selectedGroupID
        let time = frame.time
        let projectID = project?.id
        isSaving = true; saveStatus = "Saving…"
        Task {
            do {
                var box = original ?? VBox(time: time, frameIndex: index)
                box.prompt = capturedPrompt; box.time = time; box.frameIndex = index
                if promptOnly { box.imageFile = nil; box.crop = nil }
                else {
                    let (data, actualTime, actualIndex) = try await video.capture(at: time, crop: capturedCrop)
                    let filename = UUID().uuidString + ".png"
                    try await Task.detached(priority: .userInitiated) {
                        try data.write(to: ProjectStore.captureURL(filename, in: url), options: .atomic)
                    }.value
                    box.imageFile = filename; box.crop = capturedCrop; box.time = actualTime; box.frameIndex = actualIndex
                }
                guard project?.id == projectID else { isSaving = false; return }
                rememberUndo()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    if existingID != nil { project?.update(box) } else { project?.insert(box, into: groupID) }
                }
                requestCollectionScroll(to: box.id, style: existingID == nil ? .bottom : .revealIfHidden)
                suppressAutosave = true
                if existingID == nil { prompt = ""; crop = nil; cropMode = false }
                suppressAutosave = false
                isSaving = false
                if persist() { notify(existingID == nil ? (promptOnly ? "Note saved" : "Frame & note saved") : "Vbox updated") }
            } catch { isSaving = false; saveStatus = "Save failed"; errorMessage = error.localizedDescription }
        }
    }
    func toggleCrop() {
        guard !isSaving, video.ready else { return }
        video.pause(); cropMode.toggle()
    }
    func clearCrop() {
        guard !isSaving else { return }
        crop = nil; cropMode = false; NSCursor.arrow.set()
    }
    func requestCollectionScroll(to id: UUID, style: CollectionScrollStyle = .bottom) {
        scrollStyle = style; scrollTarget = id; scrollRevision += 1
    }
    func submitGroupDescription() {
        finishTextEditing(); _ = flush()
    }
    func scheduleAutosave() {
        guard !suppressAutosave, project != nil else { return }
        saveStatus = "Saving…"; autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.commitEditedPrompt(); _ = self?.persist()
        }
    }
    private func commitEditedPrompt() {
        guard let id = selectedBoxID, var box = project?.box(id), box.prompt != prompt else { return }
        box.prompt = prompt; project?.update(box)
    }
    @discardableResult func flush() -> Bool {
        guard project != nil else { return true }
        guard !isSaving else { return false }
        autosaveTask?.cancel(); finishTextEditing(); return persist(synchronously: true)
    }
    @discardableResult private func persist(synchronously: Bool = false) -> Bool {
        guard var document = project, let url = projectURL else { return true }
        if let draft = draftBeforeEditing { document.draft = draft.prompt; document.draftCrop = draft.crop; document.lastPosition = draft.position }
        else { document.draft = prompt; document.draftCrop = crop; document.lastPosition = video.position }
        document.modifiedAt = Date(); project = document
        saveRevision += 1; let revision = saveRevision, projectID = document.id
        saveStatus = "Saving…"
        if synchronously {
            do { try writer.flush(document, at: url); saveStatus = "All changes saved"; recordRecent(); return true }
            catch { reportSaveError(error); return false }
        }
        writer.save(document, at: url) { [weak self] error in
            guard let self, self.project?.id == projectID, self.saveRevision == revision else { return }
            if let error { self.reportSaveError(error) }
            else { self.saveStatus = "All changes saved"; self.recordRecent() }
        }
        return true
    }
    private func reportSaveError(_ error: Error) {
        saveStatus = "Changes not saved"; errorMessage = "Could not save the project. \(error.localizedDescription)"
    }
    private func editorState() -> EditorState {
        EditorState(prompt: prompt, crop: crop, cropMode: cropMode, boxID: selectedBoxID, groupID: selectedGroupID, draft: draftBeforeEditing, position: video.position)
    }
    private func entry() -> UndoEntry? { project.map { UndoEntry(project: $0, editor: editorState()) } }
    private func pushUndo(_ entry: UndoEntry) {
        undoHistory.append(entry); redoHistory.removeAll()
        if undoHistory.count > 100 { undoHistory.removeFirst() }
    }
    private func beginTextChange(key: String, previousPrompt: String? = nil) {
        guard !suppressAutosave else { return }
        if let pending = pendingTextChange, pending.key != key { finishTextEditing() }
        if pendingTextChange == nil, var value = entry() {
            if let previousPrompt { value.editor.prompt = previousPrompt }
            pendingTextChange = (key, value)
        }
    }
    func finishTextEditing() {
        guard !suppressAutosave else { return }
        commitEditedPrompt()
        if let pending = pendingTextChange {
            pendingTextChange = nil
            if pending.entry.project.items != project?.items { pushUndo(pending.entry) }
        }
    }
    private func rememberUndo() { finishTextEditing(); if let value = entry() { pushUndo(value) } }
    var canUndo: Bool { pendingTextChange != nil || !undoHistory.isEmpty }
    func undo() {
        guard !isSaving else { return }
        finishTextEditing()
        guard let previous = undoHistory.popLast(), let current = entry() else { return }
        redoHistory.append(current); restore(previous); notify("Change undone")
    }
    func redo() {
        guard !isSaving else { return }
        finishTextEditing()
        guard let next = redoHistory.popLast(), let current = entry() else { return }
        undoHistory.append(current); restore(next); notify("Change redone")
    }
    private func restore(_ value: UndoEntry) {
        autosaveTask?.cancel(); pendingTextChange = nil; suppressAutosave = true; video.pause()
        project = value.project
        prompt = value.editor.prompt; crop = value.editor.crop; cropMode = value.editor.cropMode
        selectedBoxID = value.editor.boxID; selectedGroupID = value.editor.groupID; draftBeforeEditing = value.editor.draft
        if let id = selectedBoxID, let box = project?.box(id) {
            prompt = box.prompt; crop = box.crop; video.seek(box.time.seconds)
        } else { video.seek(value.editor.position) }
        suppressAutosave = false
        _ = persist()
    }
    func notify(_ message: String) {
        toastTask?.cancel(); withAnimation(.easeOut(duration: 0.2)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3)); guard !Task.isCancelled else { return }
            withAnimation { self?.toast = nil }
        }
    }
    func recordRecent() {
        guard let project, let url = projectURL else { return }
        recents.removeAll { $0.path == url.path }
        recents.insert(RecentProject(path: url.path, title: project.title, videoName: URL(fileURLWithPath: project.videoPath).lastPathComponent, modified: project.modifiedAt, count: project.boxes.count, bookmark: try? url.bookmarkData()), at: 0)
        recents = Array(recents.prefix(30)); saveRecents()
    }
    func removeRecent(_ recent: RecentProject) { recents.removeAll { $0.id == recent.id }; saveRecents() }
    private func saveRecents() {
        guard !CommandLine.arguments.contains("--smoke-test") else { return }
        if let data = try? JSONEncoder().encode(recents) { UserDefaults.standard.set(data, forKey: "recentProjects") }
    }
    func revealProject() { if let projectURL { NSWorkspace.shared.activateFileViewerSelecting([projectURL]) } }
}
