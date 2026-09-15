import AppKit
import SwiftUI
import FramepadCore

struct TimelineView: View {
    @ObservedObject var model: AppModel
    @State private var bottomTargeted = false
    @State private var showScrollToBottom = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Collection").font(.system(size: 14, weight: .semibold))
                Text("\(model.boxCount)").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary).padding(.horizontal, 6).padding(.vertical, 3).background(Palette.raised, in: Capsule())
                Spacer()
                Button { model.createGroup() } label: { Label("Group", systemImage: "plus").font(.system(size: 11, weight: .medium)) }.buttonStyle(PointerButtonStyle()).foregroundStyle(Palette.secondary).help("Create a group (⌘G)").accessibilityIdentifier("create-group")
            }.padding(.horizontal, 20).frame(height: 52)
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack {
                            SectionLabel(title: "Moments & ideas")
                            Spacer()
                            if model.selectedBoxID != nil || model.selectedGroupID != nil {
                                Button { model.returnToDraft(clearGroup: true) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }.buttonStyle(PointerButtonStyle()).foregroundStyle(Palette.muted).help("Clear selection and return to draft")
                            }
                        }.padding(.vertical, 5).padding(.bottom, 12).contentShape(Rectangle()).onTapGesture { model.returnToDraft(clearGroup: true) }
                        if model.project?.items.isEmpty == true { emptyState }
                        ForEach(model.collectionRows) { row in
                            collectionRow(row)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: CollectionViewportKey.self, value: CollectionViewport(rows: [row.id: geometry.frame(in: .named("collectionViewport"))]))
                                })
                                .id(row.id)
                        }
                        VStack(spacing: 8) {
                            if !(model.project?.items.isEmpty ?? true) {
                                Image(systemName: "arrow.down.to.line").font(.system(size: 13))
                                Text(bottomTargeted ? "Release to move out of group" : "Drop a vbox here to ungroup").font(.system(size: 10))
                            }
                        }.foregroundStyle(bottomTargeted ? Palette.accent : Palette.muted.opacity(0.7))
                            .frame(maxWidth: .infinity).frame(minHeight: 85)
                            .background(bottomTargeted ? Palette.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle()).onTapGesture { model.returnToDraft(clearGroup: true) }
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, let id = UUID(uuidString: value), model.project?.box(id) != nil else { return false }
                                model.moveBox(id, to: nil); return true
                            } isTargeted: { bottomTargeted = $0 }
                    }.padding(15).id("bottom")
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: CollectionViewportKey.self, value: CollectionViewport(contentBottom: geometry.frame(in: .named("collectionViewport")).maxY))
                        })
                }.background(Palette.background.contentShape(Rectangle()).onTapGesture { model.returnToDraft(clearGroup: true) })
                    .coordinateSpace(name: "collectionViewport")
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: CollectionViewportKey.self, value: CollectionViewport(bounds: CGRect(origin: .zero, size: geometry.size)))
                    })
                    .onPreferenceChange(CollectionViewportKey.self) { viewport in
                        model.collectionViewport = viewport
                        let show = (viewport.contentBottom ?? 0) - viewport.bounds.maxY > max(140, viewport.bounds.height * 0.25)
                        if show != showScrollToBottom { withAnimation(.easeOut(duration: 0.18)) { showScrollToBottom = show } }
                    }
                    .defaultScrollAnchor(.bottom)
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .task(id: model.scrollRevision) {
                        guard let id = model.scrollTarget else { return }
                        let reveal = model.scrollStyle == .revealIfHidden
                        if reveal && model.collectionViewport.isVisible(id) { return }
                        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id.uuidString, anchor: reveal ? .center : .bottom) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showScrollToBottom {
                            Button { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } } label: {
                                Image(systemName: "arrow.down").font(.system(size: 15, weight: .semibold))
                            }.buttonStyle(ScrollToEndButtonStyle()).help("Scroll to the end")
                                .accessibilityLabel("Scroll to the end").accessibilityIdentifier("collection-scroll-to-bottom")
                                .padding(.trailing, 16).padding(.bottom, 14)
                                .transition(.opacity.combined(with: .offset(y: 8)))
                        }
                    }
            }
            HStack(spacing: 6) {
                Image(systemName: "hand.draw").font(.system(size: 10))
                Text("Drag to organize. Click to revisit.").font(.system(size: 10))
                Spacer()
            }.foregroundStyle(Palette.muted).padding(.horizontal, 20).frame(height: 34).overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
        }.background(Palette.background)
    }
    @ViewBuilder private func collectionRow(_ row: CollectionRow) -> some View {
        switch row {
        case .box(let box, let groupID):
            if let groupID {
                VBoxCard(model: model, box: box).padding(.horizontal, 11).padding(.bottom, 11)
                    .modifier(GroupSlice(model: model, groupID: groupID, part: .middle))
            } else { VBoxCard(model: model, box: box).padding(.bottom, 12) }
        case .groupHeader(let group):
            GroupHeader(model: model, group: group).padding(11)
                .modifier(GroupSlice(model: model, groupID: group.id, part: .top))
        case .groupFooter(let group):
            VStack(spacing: 9) {
                Color.clear.frame(height: 13).modifier(GroupSlice(model: model, groupID: group.id, part: .bottom))
                GroupDescription(model: model, groupID: group.id).padding(.horizontal, 9)
            }.padding(.bottom, 20)
        }
    }
    var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).stroke(Palette.border).frame(width: 50, height: 59).rotationEffect(.degrees(-10)).offset(x: -5)
                RoundedRectangle(cornerRadius: 11).fill(Palette.surface).frame(width: 50, height: 59).overlay { Image(systemName: "plus").font(.system(size: 19, weight: .light)).foregroundStyle(Palette.accent) }.offset(x: 5, y: 3)
            }.padding(.bottom, 8)
            Text("Keep a moment.").font(.system(size: 16, weight: .medium))
            Text("Pause on a frame, add a thought,\nand save your first vbox.").font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(4)
            KeyCap(text: "⌘ return").padding(.top, 2)
        }.frame(maxWidth: .infinity).padding(.vertical, 70).contentShape(Rectangle()).onTapGesture { model.returnToDraft(clearGroup: true) }
    }
}

struct VBoxCard: View {
    @ObservedObject var model: AppModel
    var box: VBox
    var selected: Bool { model.selectedBoxID == box.id }
    var body: some View {
        Button { model.selectBox(box) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    TimeLabel(seconds: box.time.seconds, size: 11, highlighted: selected)
                    Spacer(minLength: 3)
                    Text("#\(box.frameIndex)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                    Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
                if let file = box.imageFile, let url = model.projectURL {
                    CaptureThumbnail(url: ProjectStore.captureURL(file, in: url))
                        .frame(maxWidth: .infinity).frame(height: box.crop == nil ? 117 : 100)
                        .background(Color.black.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if !box.prompt.isEmpty {
                    Text(box.prompt).font(.system(size: 12)).foregroundStyle(Palette.text.opacity(0.88)).lineLimit(3).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 5) { Image(systemName: box.crop == nil ? "photo" : "crop"); Text(box.crop == nil ? "Full frame" : "Cropped frame") }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                if box.imageFile == nil { Label("NOTE ONLY", systemImage: "text.alignleft").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(Palette.muted) }
            }.padding(12).background(selected ? Palette.accent.opacity(0.055) : Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Palette.accent.opacity(0.75) : Palette.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(PointerButtonStyle(cornerRadius: 10, minimumSize: 0, horizontalPadding: 0)).animation(.easeOut(duration: 0.15), value: selected)
            .draggable(box.id.uuidString) {
                HStack { Image(systemName: "rectangle.on.rectangle"); TimeLabel(seconds: box.time.seconds) }.padding(12).background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
            }
            .contextMenu {
                Button("Go to this moment") { model.selectBox(box) }
                Menu("Move to group") {
                    ForEach(model.project?.items ?? []) { item in
                        if case .group(let g) = item { Button(g.title.isEmpty ? "Untitled group" : g.title) { model.moveBox(box.id, to: g.id) } }
                    }
                    Divider()
                    Button("New group") { model.createGroup(withBox: box.id) }
                }
                if model.project?.group(containing: box.id) != nil { Button("Move out of group") { model.moveBox(box.id, to: nil) } }
                if let file = box.imageFile, let url = model.projectURL {
                    Button("Show captured image in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ProjectStore.captureURL(file, in: url)]) }
                }
                Divider()
                Button("Delete vbox", role: .destructive) { model.deleteBox(box.id) }
            }
            .accessibilityLabel("Vbox, \(Timecode.string(box.time.seconds)), frame \(box.frameIndex), \(box.prompt)")
    }
}

struct CaptureThumbnail: View {
    var url: URL
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
            else { Image(systemName: "photo").foregroundStyle(Palette.muted) }
        }.task(id: url) {
            let result = await ThumbnailLoader.shared.image(at: url)
            guard !Task.isCancelled else { return }
            if let result { image = NSImage(cgImage: result, size: .zero) }
        }.onDisappear { image = nil }
    }
}

struct GroupHeader: View {
    @ObservedObject var model: AppModel
    var group: VBoxGroup
    @State private var renaming = false
    @FocusState private var nameFocused: Bool
    var selected: Bool { model.selectedGroupID == group.id }
    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 7) {
                Button { model.selectGroup(group.id) } label: { Image(systemName: selected ? "checkmark.circle.fill" : "square.stack").font(.system(size: 12)).foregroundStyle(selected ? Palette.accent : Palette.secondary) }.buttonStyle(PointerButtonStyle(horizontalPadding: 0)).help("Select group for new vboxes")
                if renaming {
                    TextField("Untitled group", text: model.groupBinding(group.id, title: true)).textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                        .padding(.horizontal, 6).frame(height: 30)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 5))
                        .textInputCursor()
                        .focused($nameFocused).onSubmit { finishRenaming() }
                        .accessibilityLabel("Group name").accessibilityIdentifier("group-name-\(group.id)")
                        .task { nameFocused = true }
                } else {
                    Button { model.selectGroup(group.id, toggle: false) } label: {
                        Text(group.title.isEmpty ? "Untitled group" : group.title).lineLimit(1)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(selected ? Palette.accent : Palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(PointerButtonStyle(highlight: false, horizontalPadding: 0)).help("Select group for new vboxes")
                }
                Text("\(group.boxes.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                ActionMenu(label: "Group actions", identifier: "group-actions-\(group.id)", items: [
                    ActionMenuItem(title: "Change group name", action: { renaming = true }),
                    ActionMenuItem(title: selected ? "Deselect group" : "Add new vboxes here", action: { model.selectGroup(group.id) }), .separator,
                    ActionMenuItem(title: "Remove group, keep vboxes", action: { model.ungroup(group.id) }),
                    ActionMenuItem(title: "Remove group with all vboxes", action: { model.deleteGroup(group.id) })
                ])
            }
            if selected { HStack { Text("ADDING NEW VBOXES HERE").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(Palette.accent.opacity(0.7)); Spacer() } }
            if group.boxes.isEmpty {
                VStack(spacing: 6) { Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 19, weight: .light)); Text("Drop a vbox, or save a new one").font(.system(size: 10)) }
                    .foregroundStyle(Palette.muted).frame(maxWidth: .infinity).frame(height: 82).allowsHitTesting(false)
            }
        }.onChange(of: nameFocused) { _, focused in if !focused && renaming { finishRenaming() } }
            .onDisappear { if renaming { model.submitGroupDescription() } }
    }
    private func finishRenaming() {
        guard renaming else { return }
        renaming = false; nameFocused = false
        model.submitGroupDescription()
    }
}

struct GroupDescription: View {
    @ObservedObject var model: AppModel
    var groupID: UUID
    @State private var editorHeight: CGFloat = 24
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "text.bubble").font(.system(size: 10)).padding(.top, 5).foregroundStyle(Palette.muted)
            NoteEditor(text: model.groupBinding(groupID, title: false), placeholder: "Add a group description…", fontSize: 11, role: "group-\(groupID)", isEditable: !model.isSaving, compact: true,
                       onSubmit: { model.submitGroupDescription() }, onEndEditing: { model.finishTextEditing() }, onHeightChange: { editorHeight = $0 })
                .frame(height: editorHeight)
        }.help("Return to save · Shift-Return for a new line")
    }
}

enum GroupPart { case top, middle, bottom }
struct GroupSlice: ViewModifier {
    @ObservedObject var model: AppModel
    var groupID: UUID
    var part: GroupPart
    @State private var targeted = false
    var active: Bool { targeted || model.selectedGroupID == groupID }
    func body(content: Content) -> some View {
        content
            .background {
                Button { model.selectGroup(groupID, toggle: false) } label: {
                    Rectangle().fill(active ? Palette.accent.opacity(0.025) : Palette.surface.opacity(0.35)).contentShape(Rectangle())
                }.buttonStyle(PointerButtonStyle(highlight: false, minimumSize: 0, horizontalPadding: 0)).accessibilityLabel("Select group")
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: part == .top ? 13 : 0, bottomLeadingRadius: part == .bottom ? 13 : 0, bottomTrailingRadius: part == .bottom ? 13 : 0, topTrailingRadius: part == .top ? 13 : 0))
            .overlay {
                GroupOutline(part: part).stroke(active ? Palette.accent.opacity(targeted ? 0.95 : 0.45) : Color.white.opacity(0.14), lineWidth: targeted ? 2 : 1).allowsHitTesting(false)
            }
            .dropDestination(for: String.self) { values, _ in
                guard let value = values.first, let id = UUID(uuidString: value), model.project?.box(id) != nil else { return false }
                model.moveBox(id, to: groupID); return true
            } isTargeted: { targeted = $0 }
            .animation(.easeOut(duration: 0.16), value: targeted)
    }
}
struct GroupOutline: Shape {
    var part: GroupPart
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let l: CGFloat = 0.5, r = rect.width - 0.5, h = rect.height, radius: CGFloat = 12.5
        switch part {
        case .top:
            path.move(to: CGPoint(x: l, y: h)); path.addLine(to: CGPoint(x: l, y: radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: l), control: CGPoint(x: l, y: l))
            path.addLine(to: CGPoint(x: r - radius, y: l))
            path.addQuadCurve(to: CGPoint(x: r, y: radius), control: CGPoint(x: r, y: l)); path.addLine(to: CGPoint(x: r, y: h))
        case .middle:
            path.move(to: CGPoint(x: l, y: 0)); path.addLine(to: CGPoint(x: l, y: h))
            path.move(to: CGPoint(x: r, y: 0)); path.addLine(to: CGPoint(x: r, y: h))
        case .bottom:
            path.move(to: CGPoint(x: l, y: 0))
            path.addQuadCurve(to: CGPoint(x: radius, y: h - l), control: CGPoint(x: l, y: h - l))
            path.addLine(to: CGPoint(x: r - radius, y: h - l))
            path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: r, y: h - l))
        }
        return path
    }
}
