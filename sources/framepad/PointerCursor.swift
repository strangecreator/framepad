import AppKit
import SwiftUI

// SwiftUI may restore its hosting view's cursor after a child tracking event.
// Resolve native cursor updates at the host as well so the last cursor wins.
final class PointerHostingView<Content: View>: NSHostingView<Content> {
    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        updatePointer(with: event)
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updatePointer(with: event)
    }
    private func updatePointer(with event: NSEvent) {
        if let window { PointerTrackingView.refresh(in: window, at: event.locationInWindow) }
    }
}

extension View {
    func pointerCursor(enabled: Bool = true, onMove: ((CGPoint?) -> Void)? = nil) -> some View {
        modifier(PointerCursorModifier(enabled: enabled, textInput: false, onMove: onMove))
    }
    func textInputCursor() -> some View {
        modifier(PointerCursorModifier(enabled: true, textInput: true, onMove: nil))
    }
}

private struct PointerCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    var enabled: Bool
    var textInput: Bool
    var onMove: ((CGPoint?) -> Void)?
    func body(content: Content) -> some View {
        content.background(PointerRegion(enabled: enabled && isEnabled, textInput: textInput, onMove: onMove))
    }
}

struct PointerButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 7
    var circular = false
    var highlight = true
    var minimumSize: CGFloat = 30
    var horizontalPadding: CGFloat = 8
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, circular ? 0 : horizontalPadding)
            .frame(minWidth: minimumSize, minHeight: minimumSize)
            .contentShape(RoundedRectangle(cornerRadius: circular ? 1000 : cornerRadius))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .buttonHover(cornerRadius: cornerRadius, circular: circular, highlight: highlight)
    }
}

extension View {
    func buttonHover(cornerRadius: CGFloat = 7, circular: Bool = false, highlight: Bool = true) -> some View {
        modifier(ButtonHoverFeedback(cornerRadius: cornerRadius, circular: circular, highlight: highlight))
    }
}

private struct ButtonHoverFeedback: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    var cornerRadius: CGFloat
    var circular: Bool
    var highlight: Bool
    func body(content: Content) -> some View {
        content
            .overlay {
                if highlight {
                    RoundedRectangle(cornerRadius: circular ? 1000 : cornerRadius)
                        .fill(Color.white.opacity(hovering && isEnabled ? 0.11 : 0))
                        .overlay(RoundedRectangle(cornerRadius: circular ? 1000 : cornerRadius).stroke(Color.white.opacity(hovering && isEnabled ? 0.22 : 0)))
                        .allowsHitTesting(false)
                }
            }
            .pointerCursor(enabled: isEnabled) { point in
                let active = point != nil && isEnabled
                if hovering != active { hovering = active }
            }
            .onChange(of: isEnabled) { _, enabled in if !enabled && hovering { hovering = false; NSCursor.arrow.set() } }
            .onDisappear { hovering = false }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct ScrollToEndButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration) }
    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label.foregroundStyle(hovering ? Color.black : Color.white)
                .frame(width: 38, height: 38)
                .background(hovering ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(hovering ? 1 : 0.4)))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .pointerCursor(enabled: isEnabled) { point in
                    let active = point != nil && isEnabled
                    if hovering != active { hovering = active }
                }
                .onDisappear { hovering = false }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

private struct PointerRegion: NSViewRepresentable {
    var enabled: Bool
    var textInput: Bool
    var onMove: ((CGPoint?) -> Void)?
    func makeNSView(context: Context) -> PointerTrackingView { PointerTrackingView() }
    func updateNSView(_ view: PointerTrackingView, context: Context) {
        view.onMove = onMove
        view.textInput = textInput
        if view.enabled != enabled {
            view.enabled = enabled
            view.window?.invalidateCursorRects(for: view)
            if !enabled {
                DispatchQueue.main.async { [weak view] in
                    guard let view, !view.enabled else { return }; view.onMove?(nil)
                }
            }
        }
        view.scheduleRefresh()
    }
}

// Cursor rectangles are clipped by AppKit and automatically restored when the
// pointer leaves. The transparent view never intercepts clicks or drags.
final class PointerTrackingView: NSView {
    var enabled = true
    var textInput = false
    var onMove: ((CGPoint?) -> Void)?
    private(set) var hoverPoint: CGPoint?
    private var tracking: NSTrackingArea?
    private static let regions = NSHashTable<PointerTrackingView>.weakObjects()
    private static var refreshPending = false
    private static var observers: [NSObjectProtocol] = []
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Self.regions.add(self)
        if Self.observers.isEmpty {
            for name in [NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification, NSApplication.didResignActiveNotification] {
                Self.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { Self.scheduleAll() }
                })
            }
        }
        scheduleRefresh()
    }
    override func resetCursorRects() {
        let rect = bounds.intersection(visibleRect)
        if enabled, !rect.isEmpty { addCursorRect(rect, cursor: textInput ? .iBeam : .pointingHand) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }; tracking = nil
        // SwiftUI's un-clipped hosting views can report a visibleRect larger
        // than this control. Never let one button track the entire window.
        let rect = bounds.intersection(visibleRect)
        scheduleRefresh()
        guard !rect.isEmpty else { return }
        let area = NSTrackingArea(rect: rect, options: [.activeInKeyWindow, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func cursorUpdate(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) {
        if let window { Self.refresh(in: window, at: event.locationInWindow) }
    }
    override func mouseExited(with event: NSEvent) {
        if let window { Self.refresh(in: window) }
    }
    private func setHover(_ point: CGPoint?) {
        guard hoverPoint != point else { return }
        hoverPoint = point; onMove?(point)
    }
    func scheduleRefresh() { Self.scheduleAll() }
    private static func scheduleAll() {
        guard !refreshPending else { return }; refreshPending = true
        DispatchQueue.main.async {
            refreshPending = false
            var windows: [NSWindow] = []
            for region in regions.allObjects {
                guard let window = region.window else { region.setHover(nil); continue }
                if !windows.contains(where: { $0 === window }) { windows.append(window) }
            }
            for window in windows { refresh(in: window) }
        }
    }
    // A window has one hovered control. Recompute ownership after geometry
    // changes too: lazy rows can move or disappear without a mouse-exit event.
    static func refresh(in window: NSWindow, at location: CGPoint? = nil) {
        let point = location ?? window.mouseLocationOutsideOfEventStream
        let views = regions.allObjects.filter { $0.window === window }
        let root = window.contentView
        let hit = root.flatMap { $0.hitTest($0.convert(point, from: nil)) }
        let nativeText = hit is NSTextView || hit is NSTextField
        let active = NSApp.isActive && window.isKeyWindow
        let candidates = active ? views.filter {
            $0.enabled && !$0.isHiddenOrHasHiddenAncestor && $0.bounds.intersection($0.visibleRect).contains($0.convert(point, from: nil))
        } : []
        let owner = candidates.min {
            if $0.textInput != $1.textInput { return $0.textInput }
            return $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }
        for view in views {
            view.setHover(view === owner && !nativeText && !view.textInput ? view.convert(point, from: nil) : nil)
        }
        guard active else { return }
        if nativeText || owner?.textInput == true { NSCursor.iBeam.set() }
        else if owner != nil { NSCursor.pointingHand.set() }
        else if NSCursor.current == .pointingHand { NSCursor.arrow.set() }
    }
}
