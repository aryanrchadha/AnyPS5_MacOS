import AppKit
import SwiftUI

struct SystemView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page(eyebrow: "System",
             title: "What this Mac can do",
             subtitle: "The relinker runs natively on Apple Silicon. Converted titles are x86-64 Windows or Linux programs, so on a Mac they run through Rosetta 2 inside a Wine-based runtime.") {
            VStack(spacing: 20) {
                WeightedRow(weights: [1, 1]) {
                    ReadinessCard().reveal(0.05)
                    PipelineCard().reveal(0.12)
                }
                LimitsCard().reveal(0.18)
            }
        }
    }
}

private struct ReadinessCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let system = model.system
        BezelCard {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(eyebrow: "Readiness", title: "Checks",
                           trailing: AnyView(GhostButton(title: "Refresh", symbol: "arrow.clockwise") { model.refreshEnvironment() }))
                VStack(spacing: 0) {
                    ReadinessRow(title: "Relinker",
                                 detail: model.relinker?.path ?? "Not found. Build it with macos/scripts/build-app.sh or set it in Settings.",
                                 state: model.relinker == nil ? .missing : .ok)
                    Hairline()
                    ReadinessRow(title: system.chip,
                                 detail: "\(system.macOSLabel) · \(system.memoryLabel) memory"
                                     + (system.isTranslated ? " · this app is running under Rosetta" : ""),
                                 state: .ok)
                    Hairline()
                    ReadinessRow(title: "Rosetta 2",
                                 detail: system.isAppleSilicon
                                     ? (system.rosettaInstalled ? "Installed" : "Run: softwareupdate --install-rosetta --agree-to-license")
                                     : "Intel Mac, x86-64 runs natively",
                                 state: !system.isAppleSilicon || system.rosettaInstalled ? .ok : .missing)
                    Hairline()
                    ReadinessRow(title: "AVX2 translation",
                                 detail: system.rosettaHasAVX2 || !system.isAppleSilicon
                                     ? "Available"
                                     : "Rosetta translates AVX2 from macOS 15. PS5 code uses it widely.",
                                 state: system.rosettaHasAVX2 || !system.isAppleSilicon ? .ok : .warning)
                    Hairline()
                    ReadinessRow(title: "Wine runtime",
                                 detail: system.wineRuntimes.isEmpty
                                     ? "None found. CrossOver, Whisky or Homebrew Wine are detected automatically."
                                     : system.wineRuntimes.map(\.name).joined(separator: ", "),
                                 state: system.wineRuntimes.isEmpty ? .warning : .ok)
                }
            }
        }
    }
}

private struct ReadinessRow: View {
    enum Level { case ok, warning, missing }
    let title: String
    let detail: String
    let state: Level

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusDot(color: color).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private var color: Color {
        switch state {
        case .ok: Theme.success
        case .warning: Theme.warning
        case .missing: Theme.failure
        }
    }
}

private struct PipelineCard: View {
    private let steps: [(String, String, String)] = [
        ("Convert", "Relinker, native arm64", "Rewrites eboot.bin and its modules into a Windows PE image with AMD-only instructions lowered."),
        ("Provide libraries", "Built on Windows", "System .prx libraries come from `cmake --build build --target libs` on a Windows host."),
        ("Run", "Wine + Rosetta 2", "Wine loads the PE image; Rosetta translates x86-64 to arm64; Vulkan maps to Metal through MoltenVK."),
    ]

    var body: some View {
        BezelCard {
            VStack(alignment: .leading, spacing: 20) {
                CardHeader(eyebrow: "Pipeline", title: "From eboot.bin to a window on macOS")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 0) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Theme.accent.opacity(0.08)))
                                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
                                if index < steps.count - 1 {
                                    Rectangle().fill(Theme.hairlineStrong).frame(width: 1).frame(maxHeight: .infinity)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(step.0)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(step.1)
                                        .font(.monoSmall)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Text(step.2)
                                    .font(.captionText)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
    }
}

private struct LimitsCard: View {
    private let limits: [(String, String)] = [
        ("No native macOS output yet",
         "The relinker writes Linux ELF and Windows PE images. A Mach-O writer and macOS builds of the system libraries do not exist yet, so titles cannot run without Wine."),
        ("Wine path is unverified",
         "Launching Windows output through Wine on Apple Silicon has not been tested by the project. Expect failures in memory reservation, threading and Vulkan feature coverage."),
        ("Direct memory",
         "Titles may commit up to 13.5 GiB of direct memory at once. Machines with 16 GB of unified memory will likely run out."),
        ("Linux output",
         "Linux images need a Linux x86-64 host. Conversion works here; running them does not."),
    ]

    var body: some View {
        BezelCard(padding: 26) {
            VStack(alignment: .leading, spacing: 20) {
                CardHeader(eyebrow: "Limits", title: "Known gaps on macOS")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 28, alignment: .top),
                                    GridItem(.flexible(), spacing: 28, alignment: .top)],
                          alignment: .leading, spacing: 22) {
                    ForEach(limits.indices, id: \.self) { index in
                        let limit = limits[index]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(limit.0)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(limit.1)
                                .font(.captionText)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(RelinkerLocator.overrideKey) private var relinkerOverride = ""

    var body: some View {
        Form {
            Section("Relinker") {
                HStack {
                    TextField("Bundled relinker", text: $relinkerOverride)
                        .font(.mono)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url { relinkerOverride = url.path }
                    }
                }
                Text(model.relinker?.path ?? "No relinker found")
                    .font(.monoSmall)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onChange(of: relinkerOverride) { model.refreshEnvironment() }
    }
}
