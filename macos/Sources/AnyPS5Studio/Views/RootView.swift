import AppKit
import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .top) {
            Backdrop()

            Group {
                switch model.route {
                case .convert: ConvertView()
                case .console: ConsoleView()
                case .system: SystemView()
                }
            }
            .id(model.route)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 14)),
                removal: .opacity
            ))

            TopBar()
                .padding(.top, 14)
        }
        .animation(Motion.settle, value: model.route)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            withAnimation(Motion.settle) {
                model.open(url)
                model.route = .convert
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshEnvironment()
            model.reinspect()
        }
    }
}

/// Floating island navigation, detached from the window edge.
private struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Namespace var namespace

    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 2) {
                ForEach(Route.allCases) { route in
                    let selected = model.route == route
                    Button {
                        model.route = route
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: route.symbol)
                                .font(.system(size: 11, weight: .light))
                            Text(route.title)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        }
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                                    .matchedGeometryEffect(id: "route", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, 8)

                RunIndicator()
                    .padding(.trailing, 10)
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
            Spacer()
        }
    }
}

private struct RunIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            switch model.runner.state {
            case .running(let label, _):
                StatusDot(color: Theme.accent, pulsing: true)
                Text(label).foregroundStyle(Theme.textPrimary)
            case .finished(_, let code, _):
                StatusDot(color: code == 0 ? Theme.success : Theme.failure)
                Text(code == 0 ? "Done" : "Exit \(code)").foregroundStyle(Theme.textSecondary)
            case .failedToStart:
                StatusDot(color: Theme.failure)
                Text("Failed").foregroundStyle(Theme.textSecondary)
            case .idle:
                StatusDot(color: model.relinker == nil ? Theme.warning : Theme.success)
                Text(model.relinker == nil ? "No relinker" : "Ready").foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .animation(Motion.snap, value: model.runner.state)
    }
}

/// Page scaffold shared by the three routes: heading block and generous margins.
struct Page<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var scrolls = true
    @ViewBuilder var content: Content

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: eyebrow, tint: Theme.accent)
                Text(title)
                    .font(.display)
                    .tracking(-1.1)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .reveal()
            content
        }
        .padding(.horizontal, 48)
        .padding(.top, 92)
        .padding(.bottom, 48)
        .frame(maxWidth: 1380, alignment: .leading)
        .frame(maxWidth: .infinity)

        if scrolls {
            ScrollView { stack }.scrollIndicators(.never)
        } else {
            stack.frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
