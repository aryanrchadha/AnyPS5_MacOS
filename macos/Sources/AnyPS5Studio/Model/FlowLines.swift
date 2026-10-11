import Foundation

enum FlowLines {
    static func lines(widths: [CGFloat], available: CGFloat, spacing: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if let last = lines.indices.last, used + spacing + width <= available {
                lines[last].append(index)
                used += spacing + width
            } else {
                lines.append([index])
                used = width
            }
        }
        return lines
    }
}
