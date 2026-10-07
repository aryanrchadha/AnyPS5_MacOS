import GameController
import Observation

struct ConnectedController: Identifiable, Equatable {
    let id: ObjectIdentifier
    let name: String
    let category: String
    let battery: Float?
}

@Observable
final class ControllerMonitor {
    private(set) var controllers: [ConnectedController] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        refresh()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        controllers = GCController.controllers().map { controller in
            ConnectedController(
                id: ObjectIdentifier(controller),
                name: controller.vendorName ?? "Game controller",
                category: controller.productCategory,
                battery: controller.battery.map { $0.batteryLevel }
            )
        }
    }
}
