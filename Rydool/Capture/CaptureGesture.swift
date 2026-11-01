import AppKit

/// The drag currently owned by a capture canvas. Coordinates are in view points.
enum CaptureGesture {
    case idle
    case selection(anchor: CGPoint)
    case move(origin: CGRect, pointer: CGPoint)
    case resize(handle: SelectionHandle, origin: CGRect, pointer: CGPoint)
    case annotation

    var isSelecting: Bool {
        if case .selection = self { return true }
        return false
    }

    /// Produces new selection geometry for pointer drags, if this is a selection gesture.
    func selection(at point: CGPoint, in manager: SelectionManager) -> CGRect? {
        switch self {
        case .selection(let anchor):
            let limit = manager.bounds
            let clamped = CGPoint(x: min(max(point.x, limit.minX), limit.maxX),
                                  y: min(max(point.y, limit.minY), limit.maxY))
            return manager.rect(from: anchor, to: clamped)
        case .move(let origin, let pointer):
            return manager.moved(origin, by: CGSize(width: point.x - pointer.x, height: point.y - pointer.y))
        case .resize(let handle, let origin, let pointer):
            return manager.resized(origin, handle: handle,
                                   by: CGSize(width: point.x - pointer.x, height: point.y - pointer.y))
        case .idle, .annotation:
            return nil
        }
    }
}
