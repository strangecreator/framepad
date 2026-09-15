import AppKit
import SwiftUI

@main enum FramepadApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack(alignment: .bottom) {
            Group { if model.hasProject { WorkspaceView(model: model) } else { HomeView(model: model) } }
            if let toast = model.toast {
                HStack(spacing: 9) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent); Text(toast).font(.system(size: 12, weight: .medium)) }
                    .padding(.horizontal, 18).padding(.vertical, 12).background(Palette.raised, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12))).shadow(color: .black.opacity(0.35), radius: 18, y: 6)
                    .padding(.bottom, 24).transition(.move(edge: .bottom).combined(with: .opacity)).allowsHitTesting(false)
            }
        }.foregroundStyle(Palette.text).tint(Palette.accent).background(Palette.background)
            .sheet(isPresented: $model.showShortcuts) { ShortcutsView() }
            .alert("Something needs your attention", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
}

struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    let shortcuts = [("Play / pause from any pane", "⌥ Space"), ("Play / pause outside text", "Space"), ("Seek 3 seconds outside text", "← / →"), ("Seek 3 seconds from any pane", "⌘ ← / ⌘ →"), ("Focus the prompt editor", "⌘ I"), ("Create / edit a crop region", "⌘ ⇧ C"), ("Clear crop entirely", "⌘ W"), ("Save frame & note / update vbox", "⌘ Return"), ("Save note only", "⌘ /"), ("Create a group", "⌘ G"), ("Delete selected vbox outside text", "⌫"), ("Undo / redo document change", "⌘ Z / ⌘ ⇧ Z"), ("Save group description", "Return"), ("New / open project", "⌘ N / ⌘ O"), ("Back to projects", "⌘ L")]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { BrandMark(); Text("Stay in the flow.").font(.system(size: 23, weight: .medium)).tracking(-0.6); Spacer() }
            Text("A few keys. Every detail.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            VStack(spacing: 12) {
                ForEach(shortcuts, id: \.0) { label, key in HStack { Text(label).font(.system(size: 12)); Spacer(); KeyCap(text: key) } }
            }
            Text("While typing, arrows move the text cursor; ⌘← / ⌘→ seek the video. Hold a seek shortcut to keep moving. Space types normally; ⌥Space controls playback anywhere. Drag crop edges or corners to resize, or its interior to move. Shift-Return adds a line to a group description.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
            HStack { Spacer(); Button("Got it") { dismiss() }.buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 450).background(Palette.surface).foregroundStyle(Palette.text).preferredColorScheme(.dark)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var ownedModel: AppModel?
    private var mainWindow: NSWindow?
    private weak var model: AppModel?
    private var keyMonitor: Any?
    private var keyUpMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var repeatTimer: Timer?
    private var heldKey: UInt16?
    private var installed = false
    private var pendingURLs: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(); ownedModel = model
        let root = RootView(model: model).frame(minWidth: 1040, minHeight: 692).preferredColorScheme(.dark)
        let hosting = PointerHostingView(rootView: root)
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 872), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Framepad"; window.contentView = hosting; window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameAutosaveName("FramepadMainWindow"); window.center()
        mainWindow = window
        installMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        install(model)
    }
    func install(_ model: AppModel) {
        self.model = model
        guard !installed else { return }; installed = true
        for window in NSApp.windows where window.title == "Framepad" {
            window.delegate = self; window.backgroundColor = NSColor(Palette.background)
            window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.minSize = NSSize(width: 1040, height: 720)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if self?.heldKey == event.keyCode { self?.stopRepeating() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRepeating(); _ = self?.model?.flush() }
        }
        if let url = pendingURLs.last { model.open(url); pendingURLs = [] }
        if let i = CommandLine.arguments.firstIndex(of: "--open-project"), CommandLine.arguments.count > i + 1 { model.open(URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
        if CommandLine.arguments.contains("--smoke-test") { Task { await SmokeTest.run(model: model) } }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            Task { try? await Task.sleep(for: .seconds(3)); Self.snapshot(path: path) }
        }
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let model, NSApp.keyWindow?.sheetParent == nil, NSApp.modalWindow == nil, !model.showShortcuts,
              NSApp.keyWindow?.identifier?.rawValue != "com.apple.SwiftUI.Settings" else { return event }
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let typing = NSApp.keyWindow?.firstResponder is NSTextView
        if flags.contains(.command) {
            guard model.hasProject else { return event }
            if (event.keyCode == 36 || event.keyCode == 76), flags == .command { model.saveBox(); return nil }
            if event.keyCode == 44, flags == .command { model.saveBox(promptOnly: true); return nil }
            if event.keyCode == 8, flags == [.command, .shift] { if !event.isARepeat { model.toggleCrop() }; return nil }
            if event.keyCode == 13, flags == .command { model.clearCrop(); return nil }
            if event.keyCode == 34, flags == .command { focusPrompt(); return nil }
            if (event.keyCode == 123 || event.keyCode == 124), flags == .command {
                if !model.isSaving { seek(event, whileTyping: true) }; return nil
            }
            if event.keyCode == 6, flags == .command {
                if model.canUndo { model.undo(); return nil }
                return event
            }
            if event.keyCode == 6, flags == [.command, .shift], !model.redoHistory.isEmpty { model.redo(); return nil }
            return event
        }
        guard model.hasProject, !model.isSaving else { return event }
        if event.keyCode == 49, flags == .option { if !event.isARepeat { model.video.toggle() }; return nil }
        guard flags.isEmpty else { return event }
        switch event.keyCode {
        case 51:
            if typing { return event }
            if !event.isARepeat, let id = model.selectedBoxID { model.deleteBox(id) }
            return nil
        case 49: if typing { return event }; if !event.isARepeat { model.video.toggle() }; return nil
        case 123, 124:
            if typing { stopRepeating(); return event }
            seek(event, whileTyping: false); return nil
        default: return event
        }
    }
    private func seek(_ event: NSEvent, whileTyping: Bool) {
        guard !event.isARepeat, heldKey != event.keyCode else { return }
        stopRepeating(); heldKey = event.keyCode
        let delta = event.keyCode == 123 ? -3.0 : 3.0
        model?.video.skip(delta)
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.heldKey != nil else { return }
                guard self.model?.isSaving == false, self.model?.hasProject == true,
                      whileTyping || !(NSApp.keyWindow?.firstResponder is NSTextView) else { self.stopRepeating(); return }
                self.model?.video.skip(delta)
            }
        }
        timer.fireDate = Date().addingTimeInterval(0.25); RunLoop.main.add(timer, forMode: .common); repeatTimer = timer
    }
    private func focusPrompt() {
        guard model?.hasProject == true, model?.isSaving == false, let window = mainWindow else { return }
        func findEditor(in view: NSView) -> NoteTextView? {
            if let editor = view as? NoteTextView, editor.role == "vbox-prompt" { return editor }
            for child in view.subviews { if let editor = findEditor(in: child) { return editor } }
            return nil
        }
        if let content = window.contentView, let editor = findEditor(in: content) {
            stopRepeating(); window.makeFirstResponder(editor)
            editor.scrollRangeToVisible(editor.selectedRange())
        }
    }
    private func stopRepeating() { repeatTimer?.invalidate(); repeatTimer = nil; heldKey = nil }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model, let url = urls.last { model.open(url) } else { pendingURLs = urls }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model?.flush() ?? true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopRepeating()
        if model?.isSaving == true { model?.notify("Finishing your capture…"); return .terminateCancel }
        return (model?.flush() ?? true) ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.makeKeyAndOrderFront(nil); return true
    }

    private func installMenu() {
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title; let result = NSMenu(title: title); item.submenu = result; bar.addItem(item); return result
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ flags: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = flags; item.target = target; menu.addItem(item)
        }
        let app = menu("Framepad")
        add(app, "About Framepad", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator()); add(app, "Hide Framepad", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator()); add(app, "Quit Framepad", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("File")
        add(file, "New Project…", #selector(newProjectAction), "n", target: self)
        add(file, "Open Project…", #selector(openProjectAction), "o", target: self)
        add(file, "Save Project", #selector(saveProjectAction), "s", target: self)
        file.addItem(.separator()); add(file, "Back to Projects", #selector(homeAction), "l", target: self)
        add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift])
        let edit = menu("Edit")
        add(edit, "Undo", #selector(undoAction), "z", target: self)
        add(edit, "Redo", #selector(redoAction), "z", [.command, .shift], target: self)
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        let markup = menu("Markup")
        add(markup, "Save Frame & Note", #selector(saveBoxAction), "\r", target: self)
        add(markup, "Save Note Only", #selector(saveNoteAction), "/", target: self)
        markup.addItem(.separator())
        add(markup, "Create or Edit Crop", #selector(cropAction), "c", [.command, .shift], target: self)
        add(markup, "Clear Crop", #selector(clearCropAction), "w", target: self)
        add(markup, "Focus Prompt", #selector(focusPromptAction), "i", target: self)
        add(markup, "Seek Backward 3 Seconds", #selector(seekBackwardAction), String(UnicodeScalar(NSLeftArrowFunctionKey)!), target: self)
        add(markup, "Seek Forward 3 Seconds", #selector(seekForwardAction), String(UnicodeScalar(NSRightArrowFunctionKey)!), target: self)
        markup.addItem(.separator()); add(markup, "New Group", #selector(groupAction), "g", target: self)
        add(markup, "Return to Draft", #selector(draftAction), target: self)
        add(markup, "Undo Collection Change", #selector(undoAction), target: self)
        markup.addItem(.separator()); add(markup, "Show Project in Finder", #selector(revealAction), target: self)
        add(markup, "Relink Source Video…", #selector(relinkAction), target: self)
        let windows = menu("Window"); NSApp.windowsMenu = windows
        add(windows, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(windows, "Zoom", #selector(NSWindow.performZoom(_:)))
        let help = menu("Help"); NSApp.helpMenu = help
        add(help, "Framepad Keyboard Shortcuts", #selector(shortcutsAction), target: self)
        NSApp.mainMenu = bar
    }
    @objc private func newProjectAction() { model?.newProject() }
    @objc private func openProjectAction() { model?.openProject() }
    @objc private func saveProjectAction() { _ = model?.flush() }
    @objc private func homeAction() { model?.goHome() }
    @objc private func saveBoxAction() { model?.saveBox() }
    @objc private func saveNoteAction() { model?.saveBox(promptOnly: true) }
    @objc private func groupAction() { model?.createGroup() }
    @objc private func draftAction() { model?.returnToDraft(clearGroup: true) }
    @objc private func undoAction() {
        if model?.canUndo == true { model?.undo() } else { NSApp.keyWindow?.firstResponder?.undoManager?.undo() }
    }
    @objc private func redoAction() {
        if model?.redoHistory.isEmpty == false { model?.redo() } else { NSApp.keyWindow?.firstResponder?.undoManager?.redo() }
    }
    @objc private func cropAction() { model?.toggleCrop() }
    @objc private func clearCropAction() { model?.clearCrop() }
    @objc private func focusPromptAction() { focusPrompt() }
    @objc private func seekBackwardAction() { model?.video.skip(-3) }
    @objc private func seekForwardAction() { model?.video.skip(3) }
    @objc private func revealAction() { model?.revealProject() }
    @objc private func relinkAction() { model?.relinkVideo() }
    @objc private func shortcutsAction() { model?.showShortcuts = true }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let model else { return false }
        switch menuItem.action {
        case #selector(newProjectAction), #selector(openProjectAction): return !model.isSaving
        case #selector(saveBoxAction), #selector(saveNoteAction): return model.canSave
        case #selector(undoAction): return !model.isSaving && (model.canUndo || NSApp.keyWindow?.firstResponder?.undoManager?.canUndo == true)
        case #selector(redoAction): return !model.isSaving && (!model.redoHistory.isEmpty || NSApp.keyWindow?.firstResponder?.undoManager?.canRedo == true)
        case #selector(shortcutsAction): return true
        default: return model.hasProject && !model.isSaving
        }
    }
    static func snapshot(path: String) {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }), let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
    }
}
