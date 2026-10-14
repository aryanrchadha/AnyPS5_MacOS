import Foundation

enum PadButton: String, CaseIterable, Identifiable {
    case up, down, left, right
    case cross, circle, square, triangle
    case l1, r1, l3, r3
    case create, options, ps, touchpad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .cross: "✕"
        case .circle: "○"
        case .square: "□"
        case .triangle: "△"
        case .l1: "L1"
        case .r1: "R1"
        case .l3: "L3"
        case .r3: "R3"
        case .create: "Create"
        case .options: "Options"
        case .ps: "PS"
        case .touchpad: "Touchpad"
        }
    }

    static let groups: [[PadButton]] = [
        [.up, .down, .left, .right],
        [.cross, .circle, .square, .triangle],
        [.l1, .r1, .l3, .r3],
        [.create, .options, .ps, .touchpad],
    ]
}

struct PadSnapshot: Equatable {
    struct Stick: Equatable {
        var x: Float = 0
        var y: Float = 0

        var magnitude: Float { min(1, (x * x + y * y).squareRoot()) }
    }

    static let restThreshold: Float = 0.1

    var pressed: Set<PadButton> = []
    var leftStick = Stick()
    var rightStick = Stick()
    var l2: Float = 0
    var r2: Float = 0

    var isIdle: Bool { pressed.isEmpty && l2 == 0 && r2 == 0 }

    func restNote(for stick: Stick) -> String? {
        guard isIdle, stick.magnitude >= Self.restThreshold else { return nil }
        return String(format: "%.2f off centre at rest", stick.magnitude)
    }
}
