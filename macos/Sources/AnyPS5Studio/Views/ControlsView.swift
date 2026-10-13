import AppKit
import Observation
import SwiftUI

@Observable
final class KeyRecorder {
    private(set) var action: InputAction?
    private(set) var hint: String?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onKey: ((String) -> Void)?

    func start(_ action: InputAction, onKey: @escaping (String) -> Void) {
        stop()
        self.action = action
        self.onKey = onKey
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        action = nil
        onKey = nil
        hint = nil
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            guard InputConfig.modifierKeyCodes.contains(event.keyCode), isPressed(event) else { return }
        } else if event.isARepeat {
            return
        }
        guard let name = InputConfig.keyNames[event.keyCode] else {
            hint = "That key has no SDL name. Try another key."
            return
        }
        guard !InputConfig.unwritableKeys.contains(name) else {
            hint = "'\(name)' starts a comment in \(InputConfig.fileName). Try another key."
            return
        }
        let callback = onKey
        stop()
        callback?(name)
    }

    private func isPressed(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        switch event.keyCode {
        case 0x38, 0x3C: return flags.contains(.shift)
        case 0x3B, 0x3E: return flags.contains(.control)
        case 0x3A, 0x3D: return flags.contains(.option)
        case 0x36, 0x37: return flags.contains(.command)
        case 0x39: return flags.contains(.capsLock)
        default: return false
        }
    }
}

struct ControlsView: View {
    @Environment(AppModel.self) private var model
    @State var recorder = KeyRecorder()

    var body: some View {
        Page(eyebrow: "Controls",
             title: "Keyboard and mouse",
             subtitle: "Edit \(InputConfig.fileName) beside a converted title. Controllers recognised by SDL work without configuration; these bindings change the keyboard and mouse only.") {
            VStack(alignment: .leading, spacing: 20) {
                ControlsHeader(recorder: recorder).reveal(0.04)
                ControllerStatus().reveal(0.05)
                if !model.controllers.controllers.isEmpty {
                    ControllerTesterCard().reveal(0.055)
                }
                if model.inputConfigDirectory != nil {
                    if !model.inputConfig.issues.isEmpty {
                        Callout(text: "The existing file has lines the runtime would reject. Saving rewrites the file without them.\n"
                                + model.inputConfig.issues.joined(separator: "\n"))
                            .reveal(0.06)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 640), spacing: 20, alignment: .top)],
                              alignment: .leading, spacing: 20) {
                        ForEach(Array(InputConfig.groups.enumerated()), id: \.element) { index, group in
                            ActionGroupCard(group: group, recorder: recorder)
                                .reveal(0.08 + Double(index) * 0.04)
                        }
                    }
                    PreviewCard().reveal(0.3)
                }
            }
        }
        .onAppear {
            if model.inputConfigDirectory == nil {
                if let output = model.outputExecutable, FileManager.default.fileExists(atPath: output.path) {
                    model.selectControlsTarget(output.deletingLastPathComponent())
                } else if let first = model.controlsTargets.first {
                    model.selectControlsTarget(first.output.deletingLastPathComponent())
                }
            } else {
                model.reloadInputConfigIfSaved()
            }
        }
        .onDisappear { recorder.stop() }
    }
}

private struct ControlsHeader: View {
    @Environment(AppModel.self) private var model
    let recorder: KeyRecorder

    var body: some View {
        BezelCard {
            if let directory = model.inputConfigDirectory {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Eyebrow(text: "Title")
                            targetMenu(current: directory)
                        }
                        Text(model.inputConfigURL?.path ?? "")
                            .font(.monoSmall)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Chip(text: model.inputConfigSaved ? "Saved" : "Unsaved changes",
                         symbol: model.inputConfigSaved ? "checkmark" : "pencil",
                         tint: model.inputConfigSaved ? Theme.success : Theme.warning)
                    GhostButton(title: "Reset all", symbol: "arrow.uturn.backward") {
                        recorder.stop()
                        model.updateInputConfig { $0.resetAll() }
                    }
                    GhostButton(title: "Reveal", symbol: "folder") { model.reveal(model.inputConfigURL ?? directory) }
                    IslandButton(title: "Save", symbol: "square.and.arrow.down", enabled: !model.inputConfigSaved) {
                        recorder.stop()
                        model.saveInputConfig()
                    }
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(Theme.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No converted title yet")
                            .font(.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Bindings are saved beside a title's executable. Convert a title, then edit its controls here.")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    IslandButton(title: "Convert a title") { model.route = .convert }
                }
            }
        }
    }

    private func targetMenu(current: URL) -> some View {
        Menu {
            ForEach(model.controlsTargets) { entry in
                Button(entry.title + "  ·  " + entry.output.deletingLastPathComponent().lastPathComponent) {
                    recorder.stop()
                    model.selectControlsTarget(entry.output.deletingLastPathComponent())
                }
            }
        } label: {
            Text(model.controlsTargets.first { $0.output.deletingLastPathComponent().standardizedFileURL == current.standardizedFileURL }?.title
                 ?? current.lastPathComponent)
                .font(.cardTitle)
                .foregroundStyle(Theme.textPrimary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct ActionGroupCard: View {
    @Environment(AppModel.self) private var model
    let group: String
    let recorder: KeyRecorder

    var body: some View {
        let actions = InputConfig.actions.filter { $0.group == group }
        BezelCard {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(eyebrow: group, title: "\(actions.count) actions")
                    .padding(.bottom, 6)
                ForEach(actions) { action in
                    ActionRow(action: action, recorder: recorder)
                    if action != actions.last { Hairline() }
                }
            }
        }
    }
}

private struct ActionRow: View {
    @Environment(AppModel.self) private var model
    let action: InputAction
    let recorder: KeyRecorder

    var body: some View {
        let config = model.inputConfig
        let bindings = config.bindings(for: action)
        let recording = recorder.action == action
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(action.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if config.isOverridden(action) {
                    Chip(text: "Custom", tint: Theme.accent)
                }
                Spacer()
                if recording {
                    StatusDot(color: Theme.accent, pulsing: true)
                    Text(recorder.hint ?? "Press a key…")
                        .font(.captionText)
                        .foregroundStyle(recorder.hint == nil ? Theme.accent : Theme.warning)
                    GhostButton(title: "Cancel", symbol: "xmark") { recorder.stop() }
                } else {
                    GhostButton(title: "Key", symbol: "keyboard") {
                        recorder.start(action) { name in
                            model.updateInputConfig { try $0.add(.key(name), to: action) }
                        }
                    }
                    sourceMenu
                    if config.isOverridden(action) {
                        Button {
                            model.updateInputConfig { $0.reset(action) }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.white.opacity(0.05)))
                        }
                        .buttonStyle(PressableStyle())
                        .help("Restore built-in bindings")
                    }
                }
            }
            if bindings.isEmpty {
                Text("No keyboard or mouse binding")
                    .font(.captionText)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                HStack(spacing: 6) {
                    ForEach(bindings, id: \.self) { source in
                        BindingChip(source: source,
                                    custom: config.isOverridden(action),
                                    sharedWith: config.owners(of: source, excluding: action)) {
                            model.updateInputConfig { $0.remove(source, from: action) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .animation(Motion.snap, value: recording)
    }

    private var sourceMenu: some View {
        Menu {
            Section("Mouse") {
                ForEach(InputSource.mouseButtons, id: \.self) { button in
                    Button(button) { model.updateInputConfig { try $0.add(.mouse(button), to: action) } }
                        .disabled(!action.allows(.mouse(button)))
                }
            }
            Section("Wheel") {
                ForEach(InputSource.wheelDirections, id: \.self) { direction in
                    Button("Wheel \(direction)") { model.updateInputConfig { try $0.add(.wheel(direction), to: action) } }
                        .disabled(!action.allows(.wheel(direction)))
                }
            }
        } label: {
            Image(systemName: "computermouse")
                .font(.system(size: 11, weight: .light))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .help(action.kind == .fullscreen ? "ToggleFullscreen accepts keyboard keys only" : "Add a mouse button or wheel direction")
    }
}

private struct BindingChip: View {
    let source: InputSource
    let custom: Bool
    let sharedWith: [String]
    let remove: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: source.symbol).font(.system(size: 10, weight: .light))
            Text(source.label).font(.system(size: 11.5, weight: .medium, design: .monospaced))
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .foregroundStyle(custom ? Theme.textPrimary : Theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(custom ? Theme.accent.opacity(0.10) : Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(sharedWith.isEmpty ? Theme.hairline : Theme.warning.opacity(0.5), lineWidth: 1))
        .help(sharedWith.isEmpty ? source.text : "\(source.text) is also bound to \(sharedWith.joined(separator: ", "))")
        .onHover { inside in withAnimation(Motion.snap) { hovering = inside } }
    }
}

private struct ControllerStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controllers = model.controllers.controllers
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(controllers.isEmpty ? Theme.textTertiary : Theme.success)
            if controllers.isEmpty {
                Text("No game controller connected. Pair one in System Settings › Bluetooth; titles use it without configuration.")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Connected:")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(controllers) { controller in
                    Chip(text: controller.battery.map { "\(controller.name) · \(Int($0 * 100))%" } ?? controller.name,
                         symbol: "gamecontroller", tint: Theme.success)
                        .help(controller.category)
                }
                Text("The first one is used.")
                    .font(.captionText)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            GhostButton(title: "Refresh", symbol: "arrow.clockwise") { model.controllers.refresh() }
        }
        .padding(.horizontal, 6)
    }
}

private struct PreviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let text = model.inputConfig.serialized
        BezelCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(eyebrow: "Preview", title: InputConfig.fileName)
                Text(text.isEmpty ? "No overrides. The file is removed on save and the built-in bindings apply." : text)
                    .font(.mono)
                    .foregroundStyle(text.isEmpty ? Theme.textTertiary : Theme.accent.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            }
        }
    }
}

private struct ControllerTesterCard: View {
    @State var tester = ControllerTester()

    var body: some View {
        let snapshot = tester.snapshot
        BezelCard {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(eyebrow: "Controller test", title: tester.controllerName ?? "Waiting for input")
                if tester.controllerName != nil && !tester.hasExtendedProfile {
                    Callout(text: "This controller does not report a full gamepad profile to macOS, so it cannot be tested here.")
                } else {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(PadButton.groups, id: \.self) { group in
                                HStack(spacing: 6) {
                                    ForEach(group) { button in
                                        PadButtonCell(label: button.label, pressed: snapshot.pressed.contains(button))
                                    }
                                }
                            }
                        }
                        StickView(title: "Left stick", stick: snapshot.leftStick, note: snapshot.restNote(for: snapshot.leftStick))
                        StickView(title: "Right stick", stick: snapshot.rightStick, note: snapshot.restNote(for: snapshot.rightStick))
                        HStack(alignment: .bottom, spacing: 10) {
                            TriggerBar(title: "L2", value: snapshot.l2)
                            TriggerBar(title: "R2", value: snapshot.r2)
                        }
                    }
                    Text("Reads the first controller, the one SDL uses, through macOS. Press buttons and move the sticks; a stick that stays off centre with your hands off can drift in games.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { tester.start() }
        .onDisappear { tester.stop() }
    }
}

private struct PadButtonCell: View {
    let label: String
    let pressed: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .frame(minWidth: 44, minHeight: 26)
            .padding(.horizontal, 4)
            .foregroundStyle(pressed ? Color.black : Theme.textSecondary)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(pressed ? Theme.accent : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .animation(Motion.snap, value: pressed)
    }
}

private struct StickView: View {
    let title: String
    let stick: PadSnapshot.Stick
    let note: String?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.white.opacity(0.04))
                Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1)
                Circle()
                    .stroke(Theme.hairline, lineWidth: 1)
                    .frame(width: 84 * CGFloat(PadSnapshot.restThreshold), height: 84 * CGFloat(PadSnapshot.restThreshold))
                Circle()
                    .fill(note == nil ? Theme.accent : Theme.warning)
                    .frame(width: 12, height: 12)
                    .offset(x: CGFloat(stick.x) * 36, y: CGFloat(-stick.y) * 36)
            }
            .frame(width: 84, height: 84)
            Text(title)
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
            Text(String(format: "%+.2f  %+.2f", stick.x, stick.y))
                .font(.monoSmall)
                .foregroundStyle(Theme.textTertiary)
            if let note {
                Text(note)
                    .font(.captionText)
                    .foregroundStyle(Theme.warning)
            }
        }
    }
}

private struct TriggerBar: View {
    let title: String
    let value: Float

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.05))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.accent)
                    .frame(height: 84 * CGFloat(max(0, min(1, value))))
            }
            .frame(width: 18, height: 84)
            Text(title)
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
            Text(String(format: "%.2f", value))
                .font(.monoSmall)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
