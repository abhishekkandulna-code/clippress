import SwiftUI

struct OutputPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s6) {
                        Text("Output")
                            .textStyle(.header3, .medium, color: Palette.neutral20)

                        settings
                            .disabled(model.isExporting)

                        estimate
                    }
                    .padding(Space.s6)
                }

                VStack(alignment: .leading, spacing: Space.s4) {
                    status
                    Button(model.primaryActionTitle) { model.export() }
                        .buttonStyle(KButtonStyle(variant: .filled, fullWidth: true, isLoading: model.isExporting))
                        .disabled(model.clips.isEmpty || model.importingCount > 0)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(Space.s6)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Field(label: "Quality", support: model.settings.quality.hint) {
                SegmentedTabs(label: "Quality", selection: $model.settings.quality)
            }
            Field(label: "Format", support: model.settings.codec.hint) {
                SegmentedTabs(label: "Format", selection: $model.settings.codec)
            }
            Field(label: "Resolution", support: nil) {
                SegmentedTabs(label: "Resolution", selection: $model.settings.resolution)
            }
        }
    }

    // MARK: Estimate

    @ViewBuilder
    private var estimate: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Estimated size")
                .textStyle(.bodyM, .medium, color: Palette.neutral40)
            if let plan = model.plan {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text("≈ \(Format.bytes(plan.estimatedBytes))")
                        .textStyle(.header2, .semibold, color: Palette.neutral20)
                    if let savings = savings(plan) {
                        Text(savings)
                            .textStyle(.bodyS, .medium, color: Palette.success)
                    }
                }
                Text("\(Int(plan.renderSize.width))×\(Int(plan.renderSize.height)) · \(Int(plan.frameRate.rounded())) fps · \(Format.duration(plan.duration)) long")
                    .textStyle(.bodyS, color: Palette.neutral40)
            } else {
                Text("Add a video to see how small it can get.")
                    .textStyle(.bodyS, color: Palette.neutral40)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.s).fill(Palette.neutral95))
    }

    private func savings(_ plan: ExportPlan) -> String? {
        let source = model.totalSourceBytes
        guard source > 0, plan.estimatedBytes < source else { return nil }
        return "\(Int((1 - Double(plan.estimatedBytes) / Double(source)) * 100))% smaller than \(Format.bytes(source))"
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        if case .exporting(let progress, let startedAt) = model.phase {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("Compressing… \(Int(progress * 100))%")
                        .textStyle(.bodyM, .medium, color: Palette.neutral30)
                    Spacer()
                    Button("Cancel") { model.cancelExport() }
                        .buttonStyle(KButtonStyle(variant: .neutralText, size: .small))
                }
                ProgressBar(value: progress)
                HStack {
                    Text(timeLeft(progress, since: startedAt))
                    Spacer()
                    Text("Elapsed \(Format.duration(Date().timeIntervalSince(startedAt)))")
                }
                .textStyle(.bodyS, color: Palette.neutral40)
            }
        } else if let banner = model.banner {
            BannerView(
                banner: banner,
                onReveal: { model.revealInFinder($0) },
                onDismiss: { model.banner = nil }
            )
        }
    }

    private func timeLeft(_ progress: Double, since start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        guard progress > 0.03, elapsed > 2 else { return "Working out time left…" }
        return Format.timeLeft(elapsed * (1 - progress) / progress)
    }
}

/// Label above, control, support text below (same anatomy as Form/TextField).
private struct Field<Content: View>: View {
    let label: String
    let support: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .textStyle(.bodyM, .medium, color: Palette.neutral40)
            content
            if let support {
                Text(support)
                    .textStyle(.bodyS, color: Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
