import Foundation

struct FrameRateMeter {
    struct Size: Equatable, Codable {
        let width: Int
        let height: Int

        var text: String { "\(width) \u{D7} \(height)" }
        var isUHD: Bool { width >= 3840 && height >= 2160 }
    }

    static let environmentKey = "APS5_PROFILE_DRAW"
    static let minimumWindow: TimeInterval = 1

    private(set) var size: Size?
    private(set) var rates: [Double] = []
    private var last: (presents: UInt64, time: Date)?

    var current: Double? { rates.last }
    var average: Double? { rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count) }
    var lowest: Double? { rates.min() }

    static func presents(in line: String) -> UInt64? {
        guard line.contains("[flip]") else { return nil }
        let numbers = ["(\\d+) presents from the resident image", "(\\d+) not pending", "(\\d+) unsuitable"].map { capture($0, in: line) }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        return numbers.compactMap { $0 }.reduce(0, +)
    }

    static func size(in line: String) -> Size? {
        guard line.contains("Swapchain created"), let match = line.range(of: #"extent=(\d+)x(\d+)"#, options: .regularExpression) else { return nil }
        let parts = line[match].dropFirst("extent=".count).split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return Size(width: parts[0], height: parts[1])
    }

    @discardableResult
    mutating func ingest(_ line: String, at time: Date) -> Double? {
        if let size = Self.size(in: line) {
            self.size = size
            return nil
        }
        guard let presents = Self.presents(in: line) else { return nil }
        defer { last = (presents, time) }
        guard let last, presents > last.presents else { return nil }
        let window = time.timeIntervalSince(last.time)
        guard window >= Self.minimumWindow else { return nil }
        let rate = Double(presents - last.presents) / window
        rates.append(rate)
        return rate
    }

    var summary: String? {
        guard let average, let lowest else { return nil }
        return Self.summary(average: average, lowest: lowest, size: size)
    }

    static let targetRate = 120.0
    static let targetTolerance = 0.97

    static func summary(average: Double, lowest: Double, size: Size?) -> String {
        let base = "\(Int(average.rounded())) fps average, \(Int(lowest.rounded())) lowest"
        return size.map { base + " at \($0.text)" } ?? base
    }

    static func chipText(average: Double, size: Size?) -> String {
        let rate = "\(Int(average.rounded())) fps"
        guard let size else { return rate }
        return rate + (size.isUHD ? " \u{B7} 4K" : " \u{B7} \(min(size.width, size.height))p")
    }

    static func meetsTarget(average: Double, size: Size?) -> Bool {
        (size?.isUHD ?? false) && average >= targetRate * targetTolerance
    }

    static let refreshTolerance = 0.04

    static func refreshCap(average: Double, displays: [DisplayTarget]) -> DisplayTarget? {
        guard average < targetRate * targetTolerance else { return nil }
        return displays.first { display in
            let rate = Double(display.maximumRefreshRate)
            return rate > 0 && abs(average - rate) <= rate * refreshTolerance
        }
    }

    static func refreshAdvice(average: Double, displays: [DisplayTarget]) -> String? {
        guard let display = refreshCap(average: average, displays: displays) else { return nil }
        let rate = display.maximumRefreshRate
        let base = "The average matches the \(rate) Hz refresh rate of \(display.name). Frames are presented with vsync, so this display caps the frame rate at \(rate) FPS; the title may also pace itself at that rate."
        guard display.availableRefreshRate > rate else {
            return base + " A higher frame rate needs a display that refreshes at \(Int(targetRate)) Hz."
        }
        return base + " Choose \(display.availableRefreshRate) Hz under Refresh rate in System Settings \u{203A} Displays and measure again."
    }

    private static func capture(_ pattern: String, in line: String) -> UInt64? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return UInt64(line[range])
    }
}

extension LibraryEntry {
    var lastMeasuredSession: PlaySession? {
        sessions?.last { $0.averageFPS != nil }
    }
}
