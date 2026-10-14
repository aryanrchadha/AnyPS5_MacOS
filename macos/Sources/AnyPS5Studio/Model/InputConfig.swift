import Foundation

enum InputSource: Hashable {
    case key(String)
    case mouse(String)
    case wheel(String)

    static let mouseButtons = ["Left", "Middle", "Right", "X1", "X2"]
    static let wheelDirections = ["Up", "Down"]

    var text: String {
        switch self {
        case .key(let name): "KEY:\(name)"
        case .mouse(let name): "MOUSE:\(name)"
        case .wheel(let name): "WHEEL:\(name)"
        }
    }

    var label: String {
        switch self {
        case .key(let name): name
        case .mouse(let name): "Mouse \(name)"
        case .wheel(let name): "Wheel \(name)"
        }
    }

    var symbol: String {
        switch self {
        case .key: "keyboard"
        case .mouse: "computermouse"
        case .wheel: "arrow.up.and.down"
        }
    }

    static func parse(_ text: String) throws -> InputSource {
        guard let separator = text.firstIndex(of: ":") else { throw InputConfigError.malformedSource(text) }
        let type = text[..<separator].trimmingCharacters(in: .whitespaces).uppercased()
        let value = text[text.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { throw InputConfigError.malformedSource(text) }
        switch type {
        case "KEY":
            guard InputConfig.sdlKeyNames.contains(value.lowercased()) else { throw InputConfigError.unknownKey(value) }
            return .key(value)
        case "MOUSE":
            guard let name = mouseButtons.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
                throw InputConfigError.unknownMouseButton(value)
            }
            return .mouse(name)
        case "WHEEL":
            guard let name = wheelDirections.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
                throw InputConfigError.unknownWheelDirection(value)
            }
            return .wheel(name)
        default:
            throw InputConfigError.malformedSource(text)
        }
    }
}

enum InputConfigError: Error, Equatable, CustomStringConvertible {
    case malformedSource(String)
    case unknownMouseButton(String)
    case unknownWheelDirection(String)
    case unknownAction(String)
    case notAllowed(action: String, source: String)
    case unwritableKey(String)
    case unknownKey(String)

    var description: String {
        switch self {
        case .malformedSource(let text): "Expected TYPE:VALUE, got '\(text)'."
        case .unknownMouseButton(let value): "Unknown mouse button '\(value)'."
        case .unknownWheelDirection(let value): "Wheel direction must be Up or Down, got '\(value)'."
        case .unknownAction(let name): "Unknown action '\(name)'."
        case .notAllowed(let action, let source): "\(action) cannot use \(source)."
        case .unwritableKey(let name): "The '\(name)' key starts a comment in anyps5-input.ini and cannot be bound."
        case .unknownKey(let name): "'\(name)' is not an SDL key name."
        }
    }
}

struct InputAction: Identifiable, Hashable {
    enum Kind { case button, stick, touch, toggleMouse, fullscreen }

    let name: String
    let group: String
    let kind: Kind

    var id: String { name }

    func allows(_ source: InputSource) -> Bool {
        switch source {
        case .key(let name): !InputConfig.unwritableKeys.contains(name)
        case .mouse: kind != .fullscreen
        case .wheel: kind == .button
        }
    }
}

struct InputConfig: Equatable {
    static let fileName = "anyps5-input.ini"
    static let unwritableKeys: Set<String> = ["#", ";"]

    static let actions: [InputAction] = [
        InputAction(name: "Cross", group: "Face buttons", kind: .button),
        InputAction(name: "Circle", group: "Face buttons", kind: .button),
        InputAction(name: "Square", group: "Face buttons", kind: .button),
        InputAction(name: "Triangle", group: "Face buttons", kind: .button),
        InputAction(name: "L1", group: "Shoulders and sticks", kind: .button),
        InputAction(name: "R1", group: "Shoulders and sticks", kind: .button),
        InputAction(name: "L2", group: "Shoulders and sticks", kind: .button),
        InputAction(name: "R2", group: "Shoulders and sticks", kind: .button),
        InputAction(name: "L3", group: "Shoulders and sticks", kind: .button),
        InputAction(name: "R3", group: "Shoulders and sticks", kind: .button),
        InputAction(name: "Up", group: "D-pad and options", kind: .button),
        InputAction(name: "Down", group: "D-pad and options", kind: .button),
        InputAction(name: "Left", group: "D-pad and options", kind: .button),
        InputAction(name: "Right", group: "D-pad and options", kind: .button),
        InputAction(name: "Options", group: "D-pad and options", kind: .button),
        InputAction(name: "LeftStickUp", group: "Left stick", kind: .stick),
        InputAction(name: "LeftStickDown", group: "Left stick", kind: .stick),
        InputAction(name: "LeftStickLeft", group: "Left stick", kind: .stick),
        InputAction(name: "LeftStickRight", group: "Left stick", kind: .stick),
        InputAction(name: "RightStickUp", group: "Right stick", kind: .stick),
        InputAction(name: "RightStickDown", group: "Right stick", kind: .stick),
        InputAction(name: "RightStickLeft", group: "Right stick", kind: .stick),
        InputAction(name: "RightStickRight", group: "Right stick", kind: .stick),
        InputAction(name: "TouchLeft", group: "Touchpad and window", kind: .touch),
        InputAction(name: "TouchRight", group: "Touchpad and window", kind: .touch),
        InputAction(name: "ToggleMouse", group: "Touchpad and window", kind: .toggleMouse),
        InputAction(name: "ToggleFullscreen", group: "Touchpad and window", kind: .fullscreen),
    ]

    static let groups: [String] = actions.reduce(into: []) { result, action in
        if !result.contains(action.group) { result.append(action.group) }
    }

    static let defaults: [String: [InputSource]] = [
        "ToggleFullscreen": [.key("F11")],
        "Cross": [.key("Return"), .key("Space")],
        "Options": [.key("Escape")],
        "Triangle": [.key("I")],
        "Circle": [.key("C")],
        "L1": [.key("Q")],
        "R1": [.key("E"), .key("Left Alt"), .key("Right Alt")],
        "L3": [.key("Left Shift"), .key("Right Shift")],
        "R3": [.key("Left Ctrl"), .key("Right Ctrl")],
        "Up": [.key("Up"), .wheel("Up")],
        "Right": [.key("Right")],
        "Down": [.key("Down"), .wheel("Down")],
        "Left": [.key("Left")],
        "LeftStickLeft": [.key("A")],
        "LeftStickRight": [.key("D")],
        "LeftStickUp": [.key("W")],
        "LeftStickDown": [.key("S")],
        "RightStickLeft": [.key("F")],
        "RightStickRight": [.key("H")],
        "RightStickUp": [.key("T")],
        "RightStickDown": [.key("G")],
        "TouchLeft": [.key("Backspace")],
        "TouchRight": [.key("Tab")],
        "ToggleMouse": [.mouse("Middle")],
        "Square": [.mouse("Left")],
        "R2": [.mouse("Right")],
    ]

    private(set) var overrides: [String: [InputSource]] = [:]
    private(set) var issues: [String] = []

    init() {}

    init(contents: String) {
        var lines = contents.components(separatedBy: .newlines)
        if let first = lines.first, first.hasPrefix("\u{FEFF}") { lines[0] = String(first.dropFirst()) }
        for (index, rawLine) in lines.enumerated() {
            var line = rawLine
            if let comment = line.firstIndex(where: { $0 == "#" || $0 == ";" }) { line = String(line[..<comment]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let separator = line.firstIndex(of: "=") else {
                issues.append("Line \(index + 1): expected Action = TYPE:VALUE.")
                continue
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let sourceText = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            do {
                guard let action = Self.action(named: name) else { throw InputConfigError.unknownAction(name) }
                let source = try InputSource.parse(sourceText)
                guard action.allows(source) else { throw InputConfigError.notAllowed(action: action.name, source: source.text) }
                var list = overrides[action.name] ?? []
                if !list.contains(source) { list.append(source) }
                overrides[action.name] = list
            } catch {
                issues.append("Line \(index + 1): \(error)")
            }
        }
    }

    static func action(named name: String) -> InputAction? {
        actions.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func bindings(for action: InputAction) -> [InputSource] {
        overrides[action.name] ?? Self.defaults[action.name] ?? []
    }

    func isOverridden(_ action: InputAction) -> Bool {
        overrides[action.name] != nil
    }

    func owners(of source: InputSource, excluding action: InputAction) -> [String] {
        Self.actions.filter { $0 != action && bindings(for: $0).contains(source) }.map(\.name)
    }

    mutating func add(_ source: InputSource, to action: InputAction) throws {
        if case .key(let name) = source, Self.unwritableKeys.contains(name) { throw InputConfigError.unwritableKey(name) }
        guard action.allows(source) else { throw InputConfigError.notAllowed(action: action.name, source: source.text) }
        var list = overrides[action.name] ?? Self.defaults[action.name] ?? []
        if !list.contains(source) { list.append(source) }
        overrides[action.name] = list
    }

    mutating func replace(_ action: InputAction, with source: InputSource) throws {
        if case .key(let name) = source, Self.unwritableKeys.contains(name) { throw InputConfigError.unwritableKey(name) }
        guard action.allows(source) else { throw InputConfigError.notAllowed(action: action.name, source: source.text) }
        overrides[action.name] = [source]
    }

    mutating func remove(_ source: InputSource, from action: InputAction) {
        var list = bindings(for: action)
        list.removeAll { $0 == source }
        overrides[action.name] = list.isEmpty ? nil : list
    }

    mutating func reset(_ action: InputAction) {
        overrides[action.name] = nil
    }

    mutating func resetAll() {
        overrides.removeAll()
    }

    var serialized: String {
        var lines: [String] = []
        for action in Self.actions {
            guard let list = overrides[action.name] else { continue }
            for source in list { lines.append("\(action.name) = \(source.text)") }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    static let keyNames: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x24: "Return", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x30: "Tab",
        0x31: "Space", 0x32: "`", 0x33: "Backspace", 0x35: "Escape", 0x36: "Right GUI", 0x37: "Left GUI",
        0x38: "Left Shift", 0x39: "CapsLock", 0x3A: "Left Alt", 0x3B: "Left Ctrl", 0x3C: "Right Shift",
        0x3D: "Right Alt", 0x3E: "Right Ctrl", 0x40: "F17", 0x41: "Keypad .", 0x43: "Keypad *",
        0x45: "Keypad +", 0x4B: "Keypad /", 0x4C: "Keypad Enter", 0x4E: "Keypad -", 0x4F: "F18",
        0x50: "F19", 0x51: "Keypad =", 0x52: "Keypad 0", 0x53: "Keypad 1", 0x54: "Keypad 2",
        0x55: "Keypad 3", 0x56: "Keypad 4", 0x57: "Keypad 5", 0x58: "Keypad 6", 0x59: "Keypad 7",
        0x5A: "F20", 0x5B: "Keypad 8", 0x5C: "Keypad 9", 0x60: "F5", 0x61: "F6", 0x62: "F7",
        0x63: "F3", 0x64: "F8", 0x65: "F9", 0x67: "F11", 0x69: "F13", 0x6A: "F16", 0x6B: "F14",
        0x6D: "F10", 0x6F: "F12", 0x71: "F15", 0x72: "Help", 0x73: "Home", 0x74: "PageUp",
        0x75: "Delete", 0x76: "F4", 0x77: "End", 0x78: "F2", 0x79: "PageDown", 0x7A: "F1",
        0x7B: "Left", 0x7C: "Right", 0x7D: "Down", 0x7E: "Up",
    ]

    static let modifierKeyCodes: Set<UInt16> = [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E]

    static let sdlKeyNames: Set<String> = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
        "u", "v", "w", "x", "y", "z", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "return", "escape",
        "backspace", "tab", "space", "-", "=", "[", "]", "\\", "#", ";", "'", "`", ",", ".", "/", "capslock",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "printscreen",
        "scrolllock", "pause", "insert", "home", "pageup", "delete", "end", "pagedown", "right", "left",
        "down", "up", "numlock", "keypad /", "keypad *", "keypad -", "keypad +", "keypad enter", "keypad 1",
        "keypad 2", "keypad 3", "keypad 4", "keypad 5", "keypad 6", "keypad 7", "keypad 8", "keypad 9",
        "keypad 0", "keypad .", "application", "power", "keypad =", "f13", "f14", "f15", "f16", "f17", "f18",
        "f19", "f20", "f21", "f22", "f23", "f24", "execute", "help", "menu", "select", "stop", "again",
        "undo", "cut", "copy", "paste", "find", "mute", "volumeup", "volumedown", "keypad ,",
        "keypad = (as400)", "alterase", "sysreq", "cancel", "clear", "prior", "separator", "out", "oper",
        "clear / again", "crsel", "exsel", "keypad 00", "keypad 000", "thousandsseparator",
        "decimalseparator", "currencyunit", "currencysubunit", "keypad (", "keypad )", "keypad {", "keypad }",
        "keypad tab", "keypad backspace", "keypad a", "keypad b", "keypad c", "keypad d", "keypad e",
        "keypad f", "keypad xor", "keypad ^", "keypad %", "keypad <", "keypad >", "keypad &", "keypad &&",
        "keypad |", "keypad ||", "keypad :", "keypad #", "keypad space", "keypad @", "keypad !",
        "keypad memstore", "keypad memrecall", "keypad memclear", "keypad memadd", "keypad memsubtract",
        "keypad memmultiply", "keypad memdivide", "keypad +/-", "keypad clear", "keypad clearentry",
        "keypad binary", "keypad octal", "keypad decimal", "keypad hexadecimal", "left ctrl", "left shift",
        "left alt", "left gui", "right ctrl", "right shift", "right alt", "right gui", "modeswitch",
        "audionext", "audioprev", "audiostop", "audioplay", "audiomute", "mediaselect", "www", "mail",
        "calculator", "computer", "ac search", "ac home", "ac back", "ac forward", "ac stop", "ac refresh",
        "ac bookmarks", "brightnessdown", "brightnessup", "displayswitch", "kbdillumtoggle", "kbdillumdown",
        "kbdillumup", "eject", "sleep", "app1", "app2", "audiorewind", "audiofastforward", "softleft",
        "softright", "call", "endcall",
    ]
}
