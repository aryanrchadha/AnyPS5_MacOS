import AppKit
import SwiftUI

struct AppIconView: View {
    var body: some View {
        let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            Color.clear
            ZStack {
                Color(red: 0.031, green: 0.035, blue: 0.043)
                Circle()
                    .fill(Color(red: 0.10, green: 0.42, blue: 0.40).opacity(0.85))
                    .frame(width: 560, height: 560)
                    .blur(radius: 120)
                    .offset(x: -172, y: -192)
                Circle()
                    .fill(Color(red: 0.20, green: 0.22, blue: 0.49).opacity(0.80))
                    .frame(width: 570, height: 570)
                    .blur(radius: 120)
                    .offset(x: 203, y: 193)
                links.blur(radius: 18).opacity(0.9)
                links
            }
            .frame(width: 824, height: 824)
            .clipShape(squircle)
            .overlay(squircle.strokeBorder(Color.white.opacity(0.16), lineWidth: 3))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 18)
        }
        .frame(width: 1024, height: 1024)
    }

    private var links: some View {
        let link = RoundedRectangle(cornerRadius: 115, style: .continuous)
        let white = Color(red: 0.93, green: 0.94, blue: 0.95)
        let teal = Color(red: 0.47, green: 0.87, blue: 0.80)
        return ZStack {
            link.strokeBorder(white, lineWidth: 34)
                .frame(width: 350, height: 230)
                .offset(x: -87, y: -67)
            link.strokeBorder(teal, lineWidth: 34)
                .frame(width: 350, height: 230)
                .offset(x: 87, y: 67)
            link.strokeBorder(white, lineWidth: 34)
                .frame(width: 350, height: 230)
                .mask(Rectangle().frame(width: 80, height: 90).offset(x: 158, y: 36))
                .offset(x: -87, y: -67)
        }
        .frame(width: 824, height: 824)
    }
}

@MainActor
enum AppIconRenderer {
    static func image(scale: CGFloat = 1) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = scale
        return renderer.nsImage
    }

    static func renderIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-icon"), flag + 1 < arguments.count else { return }
        let destination = URL(fileURLWithPath: arguments[flag + 1])
        guard let image = image(),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("Could not render the icon\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: destination)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Could not write \(destination.path): \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
