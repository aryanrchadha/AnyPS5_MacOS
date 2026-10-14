import Foundation
import GameController
import Observation

@Observable
final class ControllerTester {
    private(set) var snapshot = PadSnapshot()
    private(set) var controllerName: String?
    private(set) var hasExtendedProfile = false
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        snapshot = PadSnapshot()
    }

    private func poll() {
        guard let controller = GCController.controllers().first else {
            controllerName = nil
            hasExtendedProfile = false
            if snapshot != PadSnapshot() { snapshot = PadSnapshot() }
            return
        }
        controllerName = controller.vendorName ?? "Game controller"
        guard let pad = controller.extendedGamepad else {
            hasExtendedProfile = false
            return
        }
        hasExtendedProfile = true
        var next = PadSnapshot()
        func mark(_ button: PadButton, _ input: GCControllerButtonInput?) {
            if input?.isPressed == true { next.pressed.insert(button) }
        }
        mark(.up, pad.dpad.up)
        mark(.down, pad.dpad.down)
        mark(.left, pad.dpad.left)
        mark(.right, pad.dpad.right)
        mark(.cross, pad.buttonA)
        mark(.circle, pad.buttonB)
        mark(.square, pad.buttonX)
        mark(.triangle, pad.buttonY)
        mark(.l1, pad.leftShoulder)
        mark(.r1, pad.rightShoulder)
        mark(.l3, pad.leftThumbstickButton)
        mark(.r3, pad.rightThumbstickButton)
        mark(.options, pad.buttonMenu)
        mark(.create, pad.buttonOptions)
        mark(.ps, pad.buttonHome)
        if let dualSense = pad as? GCDualSenseGamepad {
            mark(.touchpad, dualSense.touchpadButton)
        } else if let dualShock = pad as? GCDualShockGamepad {
            mark(.touchpad, dualShock.touchpadButton)
        }
        next.leftStick = PadSnapshot.Stick(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
        next.rightStick = PadSnapshot.Stick(x: pad.rightThumbstick.xAxis.value, y: pad.rightThumbstick.yAxis.value)
        next.l2 = pad.leftTrigger.value
        next.r2 = pad.rightTrigger.value
        if next != snapshot { snapshot = next }
    }
}
