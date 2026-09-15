import Foundation
import FramepadCore

enum CollectionRow: Identifiable {
    case box(VBox, groupID: UUID?)
    case groupHeader(VBoxGroup)
    case groupFooter(VBoxGroup)
    var id: String {
        switch self {
        case .box(let box, _): return box.id.uuidString
        case .groupHeader(let group): return group.id.uuidString
        case .groupFooter(let group): return group.id.uuidString + "-footer"
        }
    }
    static func build(_ items: [TimelineItem]) -> [CollectionRow] {
        items.flatMap { item -> [CollectionRow] in
            switch item {
            case .box(let box): return [.box(box, groupID: nil)]
            case .group(let group):
                return [.groupHeader(group)] + group.boxes.map { CollectionRow.box($0, groupID: group.id) } + [.groupFooter(group)]
            }
        }
    }
}
