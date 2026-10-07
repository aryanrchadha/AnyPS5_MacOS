import Foundation

struct ConversionReport: Codable, Equatable {
    var target: String?
    var guestModules = 0
    var externalReferences: Int?
    var nidBefore: Int?
    var nidAfter: Int?
    var intelInPlace: Int?
    var intelStubs: Int?
    var intelKept: Int?
    var warnings = 0
    var failure: String?

    var intelTotal: Int? {
        guard let intelInPlace, let intelStubs, let intelKept else { return nil }
        return intelInPlace + intelStubs + intelKept
    }

    var isEmpty: Bool {
        target == nil && guestModules == 0 && externalReferences == nil && nidAfter == nil
            && intelTotal == nil && warnings == 0 && failure == nil
    }

    init() {}

    init(lines: [String]) {
        for line in lines {
            if line.hasPrefix("FAIL: ") {
                failure = String(line.dropFirst("FAIL: ".count))
            } else if line.hasPrefix("WARNING") {
                warnings += 1
            } else if line.hasPrefix("Guest module: ") {
                guestModules += 1
            } else if line.hasPrefix("System: ") {
                target = line.dropFirst("System: ".count).split(separator: ";").first.map(String.init)
            } else if line.hasPrefix("External prx references: ") {
                externalReferences = Int(line.dropFirst("External prx references: ".count).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("NID total: ") {
                let numbers = Self.integers(in: line)
                if numbers.count >= 2 {
                    nidBefore = numbers[0]
                    nidAfter = numbers[1]
                }
            } else if line.hasPrefix("Intel conversion: ") {
                let numbers = Self.integers(in: line)
                if numbers.count >= 3 {
                    intelInPlace = numbers[0]
                    intelStubs = numbers[1]
                    intelKept = numbers[2]
                }
            }
        }
    }

    private static func integers(in line: String) -> [Int] {
        line.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
}
