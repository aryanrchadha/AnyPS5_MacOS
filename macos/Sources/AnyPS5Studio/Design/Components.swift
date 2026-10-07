import AppKit
import SwiftUI

struct BezelCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                    .fill(Theme.core)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .padding(Theme.bezel)
            .background(
                RoundedRectangle(cornerRadius: Theme.outerRadius, style: .continuous)
                    .fill(Theme.shell)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.outerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 40, x: 0, y: 24)
    }
}

struct CardHeader: View {
    let eyebrow: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: eyebrow)
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 12)
            if let trailing { trailing }
        }
    }
}

struct Eyebrow: View {
    let text: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.eyebrow)
            .tracking(2.0)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.045)))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false
    @State var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if pulsing && !reduceMotion {
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(pulse ? 2.4 : 1)
                    .opacity(pulse ? 0 : 1)
            }
            Circle().fill(color)
        }
        .frame(width: 7, height: 7)
        .onAppear {
            guard pulsing else { return }
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

struct Chip: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .light))
            }
            Text(text).font(.captionText)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.08)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}

struct IslandButton: View {
    let title: String
    var symbol = "arrow.up.right"
    var prominent = true
    var enabled = true
    let action: () -> Void

    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 6)
                ZStack {
                    Circle().fill(prominent ? Color.black.opacity(0.08) : Color.white.opacity(0.08))
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(width: 28, height: 28)
                .scaleEffect(hovering && enabled ? 1.06 : 1)
                .offset(x: hovering && enabled ? 2 : 0, y: hovering && enabled ? -1 : 0)
            }
            .foregroundStyle(prominent ? Color.black.opacity(0.9) : Theme.textPrimary)
            .padding(.leading, 16)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(Color.white.opacity(0.94)) : AnyShapeStyle(Color.white.opacity(0.06)))
            )
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Theme.hairlineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
        .onHover { inside in withAnimation(Motion.snap) { hovering = inside } }
    }
}

struct GhostButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .light))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.08 : 0.04)))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in withAnimation(Motion.snap) { hovering = inside } }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

struct GlassSegmented<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Namespace var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(Motion.settle) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct OptionRow: View {
    let title: String
    let detail: String
    let flag: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(flag)
                        .font(.monoSmall)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(detail)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn.animation(Motion.snap))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.accent)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

private struct RevealModifier: ViewModifier {
    let delay: Double
    @State var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 22)
            .blur(radius: visible || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(reduceMotion ? nil : Motion.reveal.delay(delay)) { visible = true }
            }
    }
}

extension View {
    func reveal(_ delay: Double = 0) -> some View { modifier(RevealModifier(delay: delay)) }
}

struct Backdrop: View {
    @State var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Theme.canvas
                Circle()
                    .fill(Theme.orbTeal.opacity(0.55))
                    .frame(width: size.width * 0.55)
                    .blur(radius: 140)
                    .offset(x: drift ? -size.width * 0.18 : -size.width * 0.30,
                            y: drift ? -size.height * 0.28 : -size.height * 0.40)
                Circle()
                    .fill(Theme.orbIndigo.opacity(0.55))
                    .frame(width: size.width * 0.50)
                    .blur(radius: 150)
                    .offset(x: drift ? size.width * 0.32 : size.width * 0.20,
                            y: drift ? size.height * 0.42 : size.height * 0.30)
                Image(nsImage: GrainTexture.shared)
                    .resizable(resizingMode: .tile)
                    .opacity(0.05)
                    .blendMode(.overlay)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.drift) { drift = true }
        }
    }
}

enum GrainTexture {
    static let shared: NSImage = {
        let side = 160
        var generator = SystemRandomNumberGenerator()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                         colorSpaceName: .deviceWhite, bytesPerRow: side, bitsPerPixel: 8),
              let pixels = rep.bitmapData else { return NSImage() }
        for index in 0..<(side * side) {
            pixels[index] = UInt8.random(in: 0...255, using: &generator)
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }()
}

struct WeightedRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 20

    private func widths(for total: CGFloat, count: Int) -> [CGFloat] {
        let used = Array(weights.prefix(count)) + Array(repeating: 1, count: max(0, count - weights.count))
        let sum = used.reduce(0, +)
        let available = max(0, total - spacing * CGFloat(max(0, count - 1)))
        return used.map { available * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 1100
        let columns = widths(for: total, count: subviews.count)
        if let height = proposal.height, height.isFinite {
            return CGSize(width: total, height: height)
        }
        let height = zip(subviews, columns)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(for: bounds.width, count: subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? .mono : .bodyText)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct Callout: View {
    let text: String
    var tint: Color = Theme.warning
    var symbol = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .light))
                .padding(.top, 1)
            Text(text)
                .font(.captionText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}
