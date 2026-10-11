import Foundation

enum WindowFit {
    static func frame(_ frame: CGRect, in visible: CGRect) -> CGRect? {
        guard !visible.isEmpty, !visible.contains(frame) else { return nil }
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        let x = min(max(frame.minX, visible.minX), visible.maxX - width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
