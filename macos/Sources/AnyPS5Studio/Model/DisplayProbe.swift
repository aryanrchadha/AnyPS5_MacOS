import AppKit
import Metal

struct GPUReport: Equatable {
    var name: String
    var unifiedMemory: Bool
    var recommendedWorkingSetBytes: UInt64
    var supportsRaytracing: Bool
}

enum DisplayProbe {
    static func displays() -> [DisplayTarget] {
        NSScreen.screens.map { screen in
            let scale = screen.backingScaleFactor
            let mode = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .flatMap { CGDisplayCopyDisplayMode(CGDirectDisplayID($0.uint32Value)) }
            let width = mode.map { Int($0.pixelWidth) } ?? Int(screen.frame.width * scale)
            let height = mode.map { Int($0.pixelHeight) } ?? Int(screen.frame.height * scale)
            return DisplayTarget(name: screen.localizedName, pixelWidth: width, pixelHeight: height,
                                 maximumRefreshRate: screen.maximumFramesPerSecond)
        }
    }

    static func gpu() -> GPUReport? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return GPUReport(name: device.name,
                         unifiedMemory: device.hasUnifiedMemory,
                         recommendedWorkingSetBytes: device.recommendedMaxWorkingSetSize,
                         supportsRaytracing: device.supportsRaytracing)
    }
}
