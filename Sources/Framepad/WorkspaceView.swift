import SwiftUI
import FramepadCore

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var sidebarWidth: CGFloat = 345
    @State private var videoFraction: CGFloat = 0.71
    @State private var dragSidebarStart: CGFloat?
    @State private var dragVideoStart: CGFloat?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: model.goHome) { HStack(spacing: 9) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)); BrandMark(size: 25) } }.buttonStyle(PointerButtonStyle()).help("Back to projects").accessibilityLabel("Back to projects").accessibilityIdentifier("back-to-projects")
                Rectangle().fill(Palette.border).frame(width: 1, height: 23).padding(.horizontal, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.project?.title ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) { Circle().fill(model.saveStatus == "All changes saved" ? Palette.accent : Palette.muted).frame(width: 4, height: 4); Text(model.saveStatus).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                }
                Spacer()
                IconButton(symbol: "keyboard", help: "Keyboard shortcuts") { model.showShortcuts = true }
                ActionMenu(label: "Project actions", identifier: "project-actions", items: [
                    ActionMenuItem(title: "Show project in Finder", action: model.revealProject),
                    ActionMenuItem(title: "Relink source video…", action: model.relinkVideo), .separator,
                    ActionMenuItem(title: "Open project…", action: model.openProject),
                    ActionMenuItem(title: "Back to projects", action: model.goHome)
                ])
            }.padding(.horizontal, 22).frame(height: 63).background(Palette.background)
            Rectangle().fill(Palette.border).frame(height: 1)
            GeometryReader { geometry in
                let side = min(max(305, sidebarWidth), geometry.size.width - 620)
                let top = min(max(310, geometry.size.height * videoFraction), geometry.size.height - 195)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        VideoPane(model: model, video: model.video).frame(height: top)
                        Rectangle().fill(Palette.border).frame(height: 4).contentShape(Rectangle())
                            .onHover { NSCursor.resizeUpDown.set(); if !$0 { NSCursor.arrow.set() } }
                            .gesture(DragGesture().onChanged { value in
                                if dragVideoStart == nil { dragVideoStart = top }
                                videoFraction = min(max(310, (dragVideoStart ?? top) + value.translation.height), geometry.size.height - 195) / geometry.size.height
                            }.onEnded { _ in dragVideoStart = nil })
                        ComposerView(model: model).frame(maxHeight: .infinity)
                    }.frame(width: geometry.size.width - side - 4)
                    Rectangle().fill(Palette.border).frame(width: 4).contentShape(Rectangle())
                        .onHover { NSCursor.resizeLeftRight.set(); if !$0 { NSCursor.arrow.set() } }
                        .gesture(DragGesture().onChanged { value in
                            if dragSidebarStart == nil { dragSidebarStart = side }
                            sidebarWidth = min(max(305, (dragSidebarStart ?? side) - value.translation.width), min(510, geometry.size.width - 620))
                        }.onEnded { _ in dragSidebarStart = nil })
                    TimelineView(model: model).id(model.project?.id).frame(width: side)
                }
            }
        }.background(Palette.background)
    }
}

struct ComposerView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel(title: model.selectedBoxID == nil ? "Your note" : "Editing vbox")
                if model.selectedBoxID != nil {
                    Circle().fill(Palette.accent).frame(width: 5, height: 5)
                    Spacer()
                    Button { NSApp.keyWindow?.makeFirstResponder(nil); model.returnToDraft() } label: { Label("Back to draft", systemImage: "arrow.uturn.backward") }.buttonStyle(PointerButtonStyle()).font(.system(size: 11)).foregroundStyle(Palette.accent)
                } else {
                    Spacer()
                    if let id = model.selectedGroupID, let item = model.project?.items.first(where: { $0.id == id }), case .group(let group) = item {
                        Label(group.title.isEmpty ? "Untitled group" : group.title, systemImage: "square.stack").font(.system(size: 10)).foregroundStyle(Palette.accent).lineLimit(1)
                    } else { Text("Make the moment mean something.").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                }
            }.padding(.horizontal, 22).padding(.top, 19).padding(.bottom, 12)
            NoteEditor(text: $model.prompt, placeholder: model.selectedBoxID == nil ? "What do you notice?" : "Add a description to this moment…", isEditable: !model.isSaving, onEndEditing: { model.finishTextEditing() })
                .padding(.horizontal, 18).frame(maxHeight: .infinity)
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: model.crop == nil ? "photo" : "crop").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text(model.crop == nil ? "Full frame" : "Selected region").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text("+").foregroundStyle(Palette.muted).font(.system(size: 10))
                Text("note").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Button { model.saveBox(promptOnly: true) } label: {
                    HStack(spacing: 5) { Text("Note only").font(.system(size: 10)); KeyCap(text: "⌘/") }
                }.buttonStyle(PointerButtonStyle()).foregroundStyle(Palette.muted).disabled(!model.canSave || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Save only the note (⌘/)")
                Rectangle().fill(Palette.border).frame(width: 1, height: 19).padding(.horizontal, 5)
                KeyCap(text: "⌘↵")
                Button { model.saveBox() } label: {
                    ZStack {
                        Circle().fill(model.canSave ? Palette.accent : Palette.raised)
                        if model.isSaving { ProgressView().controlSize(.small).tint(Palette.background) }
                        else { Image(systemName: model.selectedBoxID == nil ? "arrow.up" : "checkmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(model.canSave ? Palette.background : Palette.muted) }
                    }.frame(width: 38, height: 38)
                }.buttonStyle(PointerButtonStyle(circular: true)).disabled(!model.canSave).help(model.selectedBoxID == nil ? "Save frame & note (⌘Enter)" : "Update this vbox (⌘Enter)")
                    .accessibilityLabel(model.selectedBoxID == nil ? "Save frame and note" : "Update vbox")
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 18)
        }.background(Palette.surface)
    }
}
