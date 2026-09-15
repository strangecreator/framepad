import SwiftUI

enum CollectionScrollStyle { case bottom, revealIfHidden }

// Geometry comes only from instantiated lazy rows. A row can be instantiated
// outside the viewport, so appearance alone is not evidence that it is visible.
struct CollectionViewport: Equatable {
    var bounds = CGRect.zero
    var rows: [String: CGRect] = [:]
    var contentBottom: CGFloat?

    func isVisible(_ id: UUID) -> Bool {
        guard !bounds.isEmpty, let frame = rows[id.uuidString] else { return false }
        let visible = bounds.intersection(frame)
        return !visible.isNull && visible.width > 0 && visible.height > 0
    }
}

struct CollectionViewportKey: PreferenceKey {
    static let defaultValue = CollectionViewport()
    static func reduce(value: inout CollectionViewport, nextValue: () -> CollectionViewport) {
        let next = nextValue()
        if !next.bounds.isEmpty { value.bounds = next.bounds }
        if let bottom = next.contentBottom { value.contentBottom = bottom }
        value.rows.merge(next.rows) { _, new in new }
    }
}
