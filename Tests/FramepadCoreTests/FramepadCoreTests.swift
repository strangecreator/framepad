import Foundation
import Testing
@testable import FramepadCore

@Suite struct FramepadCoreTests {
    func box(_ ms: Int64, prompt: String = "") -> VBox { VBox(time: FrameTime(value: ms, timescale: 1000), frameIndex: Int(ms / 40), prompt: prompt) }

    @Test func variableFrameRateUsesPresentationTimes() {
        let index = FrameIndex(frames: [0, 40, 80, 160, 200, 320].map { FrameTime(value: $0, timescale: 1000) })
        #expect(index.index(at: 0.159) == 2)
        #expect(index.index(at: 0.160) == 3)
        #expect(index.index(at: 0.299) == 4)
        #expect(index.index(at: 99) == 5)
        #expect(index.index(at: -1) == 0)
        #expect(FrameIndex(frames: []).index(at: 0) == nil)
    }
    @Test func compressedDecodeOrderIsSortedIntoDisplayOrder() {
        let index = FrameIndex(frames: [0, 120, 40, 80].map { FrameTime(value: $0, timescale: 1000) })
        #expect(index.frames.map(\.value) == [0, 40, 80, 120])
    }
    @Test func reindexingPreservesExistingAnnotationsAndImages() {
        let index = FrameIndex(frames: [FrameTime(value: 0, timescale: 90000), FrameTime(value: 5871600, timescale: 90000), FrameTime(value: 5871601, timescale: 90000)])
        var near = VBox(time: FrameTime(value: 5871600, timescale: 90000), frameIndex: 1901, prompt: "near", imageFile: "existing.png", crop: CropRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5))
        var note = VBox(time: FrameTime(value: 5871601, timescale: 90000), frameIndex: 1902, prompt: "gone")
        let group = VBoxGroup(title: "An encounter", prompt: "Existing group notes", boxes: [near])
        var project = Project(title: "Existing work", videoPath: "/original/video.mp4")
        project.items = [.group(group), .box(note)]; project.draft = "In progress"; project.lastPosition = 289.44
        var expected = project
        near.frameIndex = 1; note.frameIndex = 2
        var expectedGroup = group; expectedGroup.boxes = [near]
        expected.items = [.group(expectedGroup), .box(note)]
        let changed = project.reconcileFrameIndices(using: index)
        #expect(changed)
        #expect(project == expected)
        let changedAgain = project.reconcileFrameIndices(using: index)
        let changedWithoutFrames = project.reconcileFrameIndices(using: FrameIndex(frames: []))
        #expect(!changedAgain && !changedWithoutFrames)
    }
    @Test func timestampsRoundAcrossSecondAndHourBoundaries() {
        #expect(Timecode.string(59.9996) == "00:01:00.000")
        #expect(Timecode.string(3600.001) == "01:00:00.001")
        #expect(Timecode.string(.nan) == "00:00:00.000")
        #expect(Timecode.string(-12) == "00:00:00.000")
    }
    @Test func ungroupedBoxesKeepCreationOrder() {
        var project = Project(title: "Test", videoPath: "/video.mov")
        let later = box(5000), earlier = box(1000)
        project.insert(later, into: nil); project.insert(earlier, into: nil)
        #expect(project.boxes.map(\.id) == [later.id, earlier.id])
    }
    @Test func groupInsertionAndMovementSortWithoutDuplicating() {
        var project = Project(title: "Test", videoPath: "/video.mov")
        let first = VBoxGroup(title: "First"), second = VBoxGroup(title: "Second")
        let late = box(9000), early = box(1000)
        project.items = [.group(first), .group(second)]
        project.insert(late, into: first.id); project.insert(early, into: first.id)
        #expect(project.boxes.map(\.id) == [early.id, late.id])
        project.moveBox(early.id, to: second.id)
        #expect(project.group(containing: early.id) == second.id)
        #expect(project.boxes.count == 2)
        project.moveBox(early.id, to: nil)
        #expect(project.group(containing: early.id) == nil)
        #expect(project.items.last == .box(early))
    }
    @Test func invalidDropDestinationDoesNotLoseABox() {
        var project = Project(title: "Test", videoPath: "/video.mov")
        let value = box(400)
        project.insert(value, into: nil)
        project.moveBox(value.id, to: UUID())
        #expect(project.box(value.id) == value)
    }
    @Test func editedTimestampResortsGroup() {
        var project = Project(title: "Test", videoPath: "/video.mov")
        var early = box(1000); let late = box(2000), group = VBoxGroup(title: "A")
        project.items = [.group(group)]; project.insert(early, into: group.id); project.insert(late, into: group.id)
        early.time = FrameTime(value: 3000, timescale: 1000); project.update(early)
        #expect(project.boxes.map(\.id) == [late.id, early.id])
    }
    @Test func removingGroupPreservesMembersAndPosition() {
        var project = Project(title: "Test", videoPath: "/video.mov")
        let a = box(0), b = box(40), c = box(80), group = VBoxGroup(title: "A", boxes: [b])
        project.items = [.box(a), .group(group), .box(c)]; project.ungroup(group.id)
        #expect(project.items == [.box(a), .box(b), .box(c)])
    }
    @Test func cropClampsToImageBounds() {
        let crop = CropRect(x: -0.1, y: 0.8, width: 1.2, height: 0.9)
        #expect(crop.x == 0); #expect(crop.width == 1)
        #expect(abs(crop.height - 0.2) < 0.00001)
    }
    @Test func cropEdgesKeepOppositeEdgeFixed() {
        let crop = CropRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4)
        let left = CropGeometry.drag(crop, handle: .left, dx: 0.1, dy: 0.2, minimumWidth: 0.01, minimumHeight: 0.01)
        #expect(abs(left.x - 0.3) < 0.000001)
        #expect(abs(left.x + left.width - 0.6) < 0.000001)
        #expect(left.y == crop.y && abs(left.height - crop.height) < 0.000001)
        let bottomRight = CropGeometry.drag(crop, handle: .bottomRight, dx: 0.9, dy: 0.9, minimumWidth: 0.01, minimumHeight: 0.01)
        #expect(bottomRight.x == crop.x && bottomRight.y == crop.y)
        #expect(bottomRight.x + bottomRight.width == 1)
        #expect(bottomRight.y + bottomRight.height == 1)
    }
    @Test func cropCannotFlipOrLeaveVideoWhenMoved() {
        let crop = CropRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4)
        let resized = CropGeometry.drag(crop, handle: .topLeft, dx: 1, dy: 1, minimumWidth: 0.01, minimumHeight: 0.01)
        #expect(abs(resized.width - 0.01) < 0.000001 && abs(resized.height - 0.01) < 0.000001)
        let moved = CropGeometry.drag(crop, handle: .move, dx: -1, dy: 1, minimumWidth: 0.01, minimumHeight: 0.01)
        #expect(moved.x == 0 && moved.y == 0.6)
        #expect(moved.width == crop.width && moved.height == crop.height)
    }
    @Test func packageRoundTripPreservesFramesGroupsDraftAndReference() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".framepad")
        defer { try? FileManager.default.removeItem(at: url) }
        var project = Project(title: "A film", videoPath: "/outside/original.mov")
        let frame = VBox(time: FrameTime(value: 1001, timescale: 30000), frameIndex: 1, prompt: "Привет 🎬", imageFile: "frame.png", crop: CropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        project.items = [.group(VBoxGroup(title: "Scene", prompt: "Group note", boxes: [frame]))]
        project.draft = "A work in progress"; project.lastPosition = 1.234
        try ProjectStore.create(project, at: url)
        let loaded = try ProjectStore.load(at: url)
        #expect(loaded.items == project.items)
        #expect(loaded.videoPath == "/outside/original.mov")
        #expect(loaded.draft == project.draft)
        #expect(loaded.lastPosition == 1.234)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("original.mov").path))
    }
    @Test func atomicSaveKeepsRecoverablePreviousVersion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".framepad")
        defer { try? FileManager.default.removeItem(at: url) }
        var project = Project(title: "Before", videoPath: "/video.mov")
        try ProjectStore.create(project, at: url)
        project.title = "After"; try ProjectStore.save(project, at: url)
        try Data("broken".utf8).write(to: url.appendingPathComponent("project.json"))
        #expect(throws: (any Error).self) { try ProjectStore.load(at: url) }
        #expect(try ProjectStore.recover(at: url).title == "Before")
    }
    @Test func malformedCapturePathsAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".framepad")
        defer { try? FileManager.default.removeItem(at: url) }
        var project = Project(title: "Test", videoPath: "/video.mov")
        var value = box(0); value.imageFile = "../../private.png"; project.insert(value, into: nil)
        try ProjectStore.create(project, at: url)
        #expect(throws: (any Error).self) { try ProjectStore.load(at: url) }
    }
    @Test func duplicateIDsAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".framepad")
        defer { try? FileManager.default.removeItem(at: url) }
        var project = Project(title: "Test", videoPath: "/video.mov")
        let value = box(0); project.items = [.box(value), .box(value)]
        try ProjectStore.create(project, at: url)
        #expect(throws: (any Error).self) { try ProjectStore.load(at: url) }
    }
    @Test func existingProjectCannotBeOverwrittenOnCreate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".framepad")
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectStore.create(Project(title: "Original", videoPath: "/a.mov"), at: url)
        #expect(throws: (any Error).self) { try ProjectStore.create(Project(title: "Overwrite", videoPath: "/b.mov"), at: url) }
        #expect(try ProjectStore.load(at: url).title == "Original")
    }
}
