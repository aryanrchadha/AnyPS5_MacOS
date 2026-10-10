import AppKit
import SwiftUI

struct ConvertView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page(eyebrow: "Relinker",
             title: "Convert a PS5 title",
             subtitle: "Drop a decrypted game folder. The relinker rewrites its executable and modules into a native Windows or Linux image without emulation.") {
            VStack(spacing: 20) {
                BannerRow()

                WeightedRow(weights: [1.65, 1]) {
                    SourceCard().reveal(0.05)
                    VStack(spacing: 20) {
                        TargetCard()
                        HostCard()
                    }
                    .reveal(0.12)
                }

                if !model.queue.isEmpty {
                    QueueCard().reveal(0.1)
                }

                WeightedRow(weights: [1.2, 1]) {
                    OptionsCard().reveal(0.18)
                    OutputCard().reveal(0.24)
                }
            }
            .animation(Motion.settle, value: model.queue.count)
        }
    }
}

private struct SourceCard: View {
    @Environment(AppModel.self) private var model
    @State var hoveringDrop = false

    var body: some View {
        BezelCard(padding: 26) {
            if let inspection = model.inspection {
                loaded(inspection)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                empty
                    .transition(.opacity)
            }
        }
        .animation(Motion.settle, value: model.inspection)
    }

    private var empty: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(hoveringDrop ? 0.14 : 0.07))
                    .frame(width: 116, height: 116)
                Circle()
                    .strokeBorder(Theme.hairlineStrong, lineWidth: 1)
                    .frame(width: 116, height: 116)
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(Theme.textPrimary)
                    .offset(y: hoveringDrop ? 3 : 0)
            }
            VStack(spacing: 8) {
                Text("Drop game folders or an eboot.bin")
                    .font(.sectionTitle)
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
                Text("The executable must be a decrypted ELF, with sce_module, sce_modules or prx beside it.")
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            IslandButton(title: "Choose games") { model.chooseExecutable() }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(Motion.settle) { hoveringDrop = inside } }
    }

    private func loaded(_ inspection: GameInspection) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 22) {
                artwork(inspection)
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: inspection.titleId ?? "Unknown title ID")
                    Text(inspection.displayTitle)
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(inspection.executable.path)
                        .font(.monoSmall)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Chip(text: inspection.kind.label,
                             symbol: inspection.kind.isConvertible ? "checkmark" : "xmark",
                             tint: inspection.kind.isConvertible ? Theme.success : Theme.failure)
                        Chip(text: ByteCountFormatter.string(fromByteCount: inspection.byteCount, countStyle: .file),
                             symbol: "internaldrive")
                        Chip(text: "\(inspection.moduleCount) modules", symbol: "square.stack.3d.up")
                    }
                    .padding(.top, 4)
                    if let record = model.compatibility?.record(for: inspection.titleId) {
                        Chip(text: record.summary, symbol: "checkmark.seal", tint: Theme.accent)
                            .help("From docs/user/COMPATIBILITY.md")
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(inspection.moduleDirectories) { directory in
                    HStack {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                        Text(directory.name + "/")
                            .font(.mono)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(directory.elfCount) ELF \(directory.elfCount == 1 ? "module" : "modules")")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 10)
                    Hairline()
                }
            }

            if let issue = inspection.blockingIssue {
                Callout(text: issue, tint: Theme.failure, symbol: "xmark.octagon")
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                GhostButton(title: "Change", symbol: "arrow.left.arrow.right") { model.chooseExecutable() }
                GhostButton(title: "Reveal", symbol: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([inspection.executable])
                }
                GhostButton(title: "Rescan", symbol: "arrow.clockwise") { model.reinspect() }
            }
        }
    }

    @ViewBuilder
    private func artwork(_ inspection: GameInspection) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Group {
            if let url = inspection.iconURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.orbTeal.opacity(0.6), Theme.coreRaised],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 34, weight: .ultraLight))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                }
            }
        }
        .frame(width: 112, height: 112)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairlineStrong, lineWidth: 1))
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

private struct QueueCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BezelCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(eyebrow: "Queue", title: "\(model.queue.count) more \(model.queue.count == 1 ? "title" : "titles") waiting",
                           trailing: AnyView(GhostButton(title: "Clear", symbol: "xmark") { model.clearQueue() }))
                Text("Convert all runs the current title, then each queued title with the same switches and output folder. Titles that cannot be converted are skipped.")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(model.queue, id: \.executable) { item in
                        HStack(spacing: 12) {
                            StatusDot(color: item.blockingIssue == nil ? Theme.success : Theme.failure)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(item.blockingIssue ?? item.executable.deletingLastPathComponent().path)
                                    .font(.monoSmall)
                                    .foregroundStyle(item.blockingIssue == nil ? Theme.textTertiary : Theme.failure)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            Spacer()
                            Button {
                                model.removeFromQueue(item)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(PressableStyle())
                            .help("Remove from queue")
                        }
                        .padding(.vertical, 9)
                        Hairline()
                    }
                }
            }
        }
    }
}

private struct TargetCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        BezelCard {
            VStack(alignment: .leading, spacing: 18) {
                CardHeader(eyebrow: "Target", title: "Output format")
                HStack(spacing: 10) {
                    ForEach(TargetPlatform.allCases) { platform in
                        TargetTile(platform: platform, selected: model.settings.target == platform) {
                            withAnimation(Motion.settle) { model.settings.target = platform }
                            model.refreshLayout()
                        }
                    }
                }
                Text(model.settings.target.summary)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(model.settings.target)
                    .transition(.opacity)
            }
        }
    }
}

private struct TargetTile: View {
    let platform: TargetPlatform
    let selected: Bool
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: platform.symbol)
                        .font(.system(size: 18, weight: .light))
                    Spacer()
                    Circle()
                        .strokeBorder(selected ? Theme.accent : Theme.hairlineStrong, lineWidth: 1)
                        .background(Circle().fill(selected ? Theme.accent : .clear).padding(4))
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("." + platform.fileExtension)
                        .font(.monoSmall)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.07) : Color.white.opacity(hovering ? 0.05 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.45) : Theme.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in withAnimation(Motion.snap) { hovering = inside } }
    }
}

private struct HostCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let system = model.system
        BezelCard {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(eyebrow: "This Mac", title: system.chip)
                VStack(spacing: 0) {
                    HostRow(label: "Architecture",
                            value: system.isAppleSilicon ? "Apple Silicon" : "Intel",
                            ok: true)
                    Hairline()
                    HostRow(label: "Rosetta 2",
                            value: system.isAppleSilicon ? (system.rosettaInstalled ? "Installed" : "Not installed") : "Not needed",
                            ok: !system.isAppleSilicon || system.rosettaInstalled)
                    Hairline()
                    HostRow(label: "AVX2 under Rosetta",
                            value: system.rosettaHasAVX2 ? system.macOSLabel : "Needs macOS 15",
                            ok: !system.isAppleSilicon || system.rosettaHasAVX2)
                }
            }
        }
    }
}

private struct HostRow: View {
    let label: String
    let value: String
    let ok: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            StatusDot(color: ok ? Theme.success : Theme.warning)
                .padding(.leading, 4)
        }
        .padding(.vertical, 9)
    }
}

private struct OptionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        BezelCard {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(eyebrow: "Options", title: "Relinker switches")
                    .padding(.bottom, 8)

                OptionRow(title: "AMD → Intel lowering",
                          detail: "Required on Apple Silicon. Rosetta 2 implements Intel x86-64, not AMD-only extensions such as SSE4a or CLZERO.",
                          flag: "--to-intel",
                          isOn: $model.settings.toIntel)
                if !model.settings.toIntel && model.system.isAppleSilicon {
                    Callout(text: "Without lowering, AMD-only instructions will fault under Rosetta.")
                }
                Hairline()

                if model.settings.target == .windows {
                    OptionRow(title: "GUI subsystem",
                              detail: "Start without a console window.",
                              flag: "--windows-gui",
                              isOn: $model.settings.windowsGUI)
                    Hairline()
                    OptionRow(title: "Startup diagnostics",
                              detail: "Report missing dependencies when the title starts.",
                              flag: "--windows-diagnostics",
                              isOn: $model.settings.windowsDiagnostics)
                    Hairline()
                }

                OptionRow(title: "Call registry",
                          detail: "Write <output>.registry.json beside the executable.",
                          flag: "--registry",
                          isOn: $model.settings.writeRegistry)
                Hairline()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Unused imports")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("unused-filter=\(model.settings.unusedFilter.rawValue)")
                            .font(.monoSmall)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    GlassSegmented(options: UnusedFilter.allCases, selection: $model.settings.unusedFilter) { $0.title }
                    Text(model.settings.unusedFilter.detail)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 10)
                Hairline()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Library search path")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("--rpath")
                            .font(.monoSmall)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    GlassField(placeholder: ConversionSettings.defaultRunPath, text: $model.settings.runPath, monospaced: true)
                        .onChange(of: model.settings.runPath) { model.refreshLayout() }
                }
                .padding(.top, 10)
            }
            .animation(Motion.settle, value: model.settings.target)
        }
    }
}

private struct OutputCard: View {
    @Environment(AppModel.self) private var model
    @State var copied = false

    var body: some View {
        @Bindable var model = model
        BezelCard {
            VStack(alignment: .leading, spacing: 18) {
                CardHeader(eyebrow: "Output", title: "Destination")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder").font(.captionText).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        Text(model.outputDirectory?.path ?? "Not chosen")
                            .font(.mono)
                            .foregroundStyle(model.outputDirectory == nil ? Theme.textTertiary : Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        GhostButton(title: "Choose", symbol: "folder") { model.chooseOutputDirectory() }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.captionText).foregroundStyle(Theme.textSecondary)
                    GlassField(placeholder: model.inspection?.suggestedOutputName ?? "app", text: $model.outputName, monospaced: true)
                        .onChange(of: model.outputName) { model.refreshLayout() }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Command").font(.captionText).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.commandPreview, forType: .string)
                            withAnimation(Motion.snap) { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                withAnimation(Motion.snap) { copied = false }
                            }
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(copied ? Theme.success : Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(model.commandPreview)
                        .font(.monoSmall)
                        .foregroundStyle(Theme.accent.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.45)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                }

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 14) {
                    if let issue = model.blockingIssue {
                        Text(issue)
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Ready. ⌘↩ converts.")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if !model.queue.isEmpty {
                        IslandButton(title: "Convert all \(model.queue.count + 1)", symbol: "square.stack.3d.down.right",
                                     prominent: false, enabled: model.canConvert) { model.convertAll() }
                    }
                    IslandButton(title: model.runner.state.isRunning ? "Converting…" : "Convert",
                                 enabled: model.canConvert) { model.convert() }
                }
            }
        }
    }
}

struct BannerRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let banner = model.banner {
            HStack {
                Callout(text: banner)
                GhostButton(title: "Dismiss", symbol: "xmark") { model.banner = nil }
            }
            .reveal()
        }
    }
}
