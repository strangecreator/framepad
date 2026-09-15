import Foundation

public enum CropHandle: CaseIterable, Sendable {
    case move, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
}

public enum CropGeometry {
    /// Resize from the original rectangle, keeping the opposite edges fixed.
    public static func drag(_ crop: CropRect, handle: CropHandle, dx: Double, dy: Double, minimumWidth: Double, minimumHeight: Double) -> CropRect {
        if handle == .move {
            return CropRect(x: min(max(crop.x + dx, 0), 1 - crop.width), y: min(max(crop.y + dy, 0), 1 - crop.height), width: crop.width, height: crop.height)
        }
        var left = crop.x, right = crop.x + crop.width, top = crop.y, bottom = crop.y + crop.height
        if [.left, .topLeft, .bottomLeft].contains(handle) { left = min(max(0, left + dx), right - minimumWidth) }
        if [.right, .topRight, .bottomRight].contains(handle) { right = max(min(1, right + dx), left + minimumWidth) }
        if [.top, .topLeft, .topRight].contains(handle) { top = min(max(0, top + dy), bottom - minimumHeight) }
        if [.bottom, .bottomLeft, .bottomRight].contains(handle) { bottom = max(min(1, bottom + dy), top + minimumHeight) }
        return CropRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
