import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: Space.s6) {
                ClipListCard(isDropTargeted: isDropTargeted)
                OutputPanel()
                    .frame(width: 340)
            }
            .padding(Space.s6)
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Palette.neutral99)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            model.handleDrop(providers)
        }
        // The design tokens are defined for a light surface.
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("ClipPress")
                    .textStyle(.header1, .semibold, color: Palette.neutral20)
                Text("Join clips into one video and shrink it for sharing.")
                    .textStyle(.bodyM, color: Palette.neutral40)
            }
            Spacer()
            if !model.clips.isEmpty {
                Button {
                    model.chooseFiles()
                } label: {
                    HStack(spacing: Space.s2) {
                        Icon(.plus, size: 18)
                        Text("Add videos")
                    }
                }
                .buttonStyle(KButtonStyle(variant: .outlined, size: .small))
                .disabled(model.isExporting)
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s6)
    }
}

// MARK: - Clip list

private struct ClipListCard: View {
    @EnvironmentObject private var model: AppModel
    let isDropTargeted: Bool

    private var summary: String {
        guard !model.clips.isEmpty else { return "" }
        let count = model.clips.count == 1 ? "1 clip" : "\(model.clips.count) clips"
        return "\(count) · \(Format.duration(model.totalDuration)) · \(Format.bytes(model.totalSourceBytes))"
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Timeline")
                        .textStyle(.header3, .medium, color: Palette.neutral20)
                    Spacer()
                    Text(summary)
                        .textStyle(.bodyS, color: Palette.neutral40)
                }
                .padding(.horizontal, Space.s4)
                .frame(height: 56)

                Rectangle().fill(Palette.neutral90).frame(height: 1)

                if model.clips.isEmpty && model.importingCount == 0 {
                    EmptyDropZone(isDropTargeted: isDropTargeted)
                } else {
                    if !model.clips.isEmpty {
                        TimelineStrip(clips: model.clips, speed: model.settings.speed)
                        Rectangle().fill(Palette.neutral90).frame(height: 1)
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                                ClipRow(clip: clip, index: index, count: model.clips.count)
                                if index < model.clips.count - 1 {
                                    Rectangle().fill(Palette.neutral90).frame(height: 1)
                                        .padding(.leading, Space.s4)
                                }
                            }
                        }
                        .padding(.vertical, Space.s2)
                    }
                    if model.importingCount > 0 {
                        HStack(spacing: Space.s2) {
                            Spinner(color: Palette.primary)
                            Text(model.importingCount == 1 ? "Reading 1 video…" : "Reading \(model.importingCount) videos…")
                                .textStyle(.bodyS, .medium, color: Palette.neutral40)
                        }
                        .padding(Space.s4)
                    }
                }

                Rectangle().fill(Palette.neutral90).frame(height: 1)
                TimelineAdjustments()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.m)
                .strokeBorder(Palette.primary, lineWidth: 2)
                .opacity(isDropTargeted && !model.clips.isEmpty ? 1 : 0)
        }
    }
}

/// Each clip drawn to scale, so a 5-hour timeline still shows where the long clips are.
private struct TimelineStrip: View {
    let clips: [Clip]
    let speed: Double

    private var total: Double { max(clips.reduce(0) { $0 + $1.duration.seconds }, 0.001) }

    private var lengthLabel: String {
        speed == 1
            ? Format.duration(total)
            : "\(Format.duration(total)) → \(Format.duration(total / speed)) at \(Format.decimal(speed))×"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            GeometryReader { geometry in
                let gap: CGFloat = 2
                let usable = max(geometry.size.width - gap * CGFloat(clips.count - 1), 0)
                HStack(spacing: gap) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        let width = max(usable * clip.duration.seconds / total, 3)
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.xs)
                                .fill(index.isMultiple(of: 2) ? Palette.secondaryContainer : Palette.neutralVariant90)
                            if width >= 24 {
                                Text("\(index + 1)")
                                    .textStyle(.bodyS, .medium, color: Palette.onSecondaryContainer)
                            }
                        }
                        .frame(width: width)
                        .help("\(index + 1). \(clip.name) · \(Format.duration(clip.duration.seconds))")
                    }
                }
            }
            .frame(height: 32)
            .clipped()
            .accessibilityElement()
            .accessibilityLabel("Timeline with \(clips.count) clips, \(lengthLabel)")

            HStack {
                Text("0:00")
                Spacer()
                Text(lengthLabel)
            }
            .textStyle(.bodyS, color: Palette.neutral40)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }
}

/// Speed and volume apply to every clip on the timeline at once.
private struct TimelineAdjustments: View {
    @EnvironmentObject private var model: AppModel

    private var speedHint: String {
        let speed = model.settings.speed
        if speed == 1 { return "Normal speed. 2 is twice as fast, 0.5 is half." }
        let pitch = model.settings.volume > 0 ? " Voices keep their pitch." : ""
        return (speed > 1 ? "\(Format.decimal(speed))× faster." : "Slowed to \(Format.decimal(speed))×.") + pitch
    }

    private var volumeHint: String {
        let volume = model.settings.volume
        if volume == 0 { return "Muted. The video will have no sound." }
        if volume == 1 { return "As recorded. 0 mutes, 2 doubles." }
        return volume > 1 ? "Louder. Peaks that get too loud are clipped." : "Quieter than recorded."
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s6) {
            DecimalField(
                label: "Speed", value: $model.settings.speed, range: ExportSettings.speedRange,
                step: 0.25, unit: "×", support: speedHint
            )
            .frame(maxWidth: 260, alignment: .leading)

            DecimalField(
                label: "Volume", value: $model.settings.volume, range: ExportSettings.volumeRange,
                step: 0.1, unit: "×", support: volumeHint
            )
            .frame(maxWidth: 260, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .disabled(model.isExporting)
    }
}

private struct EmptyDropZone: View {
    @EnvironmentObject private var model: AppModel
    let isDropTargeted: Bool

    var body: some View {
        VStack(spacing: Space.s4) {
            Icon(.movie, size: 40)
                .foregroundColor(isDropTargeted ? Palette.primary : Palette.neutral60)
            VStack(spacing: Space.s1) {
                Text("Drop videos here")
                    .textStyle(.header3, .medium, color: Palette.neutral20)
                Text("MP4, MOV or M4V. Clips are joined in the order listed.")
                    .textStyle(.bodyM, color: Palette.neutral40)
                    .multilineTextAlignment(.center)
            }
            Button("Choose videos") { model.chooseFiles() }
                .buttonStyle(KButtonStyle(variant: .tonal))
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.s)
                .fill(isDropTargeted ? Palette.neutral95 : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.s)
                .strokeBorder(isDropTargeted ? Palette.primary : Palette.neutral70,
                              style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4]))
        )
        .padding(Space.s4)
    }
}

private struct ClipRow: View {
    @EnvironmentObject private var model: AppModel
    let clip: Clip
    let index: Int
    let count: Int
    @State private var isHovered = false

    private var details: String {
        var parts = [
            "\(Int(clip.displaySize.width))×\(Int(clip.displaySize.height))",
            Format.duration(clip.duration.seconds),
            Format.bytes(clip.fileSize),
        ]
        if clip.audio == nil { parts.append("No audio") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Space.s4) {
            Text("\(index + 1)")
                .textStyle(.bodyS, .medium, color: Palette.neutral50)
                .frame(width: 16)

            thumbnail

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(clip.name)
                    .textStyle(.bodyM, .medium, color: Palette.neutral20)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details)
                    .textStyle(.bodyS, color: Palette.neutral40)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s2)

            HStack(spacing: 0) {
                IconButton(icon: .chevronUp, label: "Move up") { model.move(clip, by: -1) }
                    .disabled(index == 0)
                IconButton(icon: .chevronDown, label: "Move down") { model.move(clip, by: 1) }
                    .disabled(index == count - 1)
                IconButton(icon: .trash, label: "Remove \(clip.name)", isDestructive: true) { model.remove(clip) }
            }
            .disabled(model.isExporting)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(isHovered ? Palette.neutral95 : Palette.surface)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clip \(index + 1), \(clip.name)")
    }

    private var thumbnail: some View {
        ZStack {
            Palette.neutral90
            if let image = clip.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Icon(.movie, size: 20).foregroundColor(Palette.neutral60)
            }
        }
        .frame(width: 80, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
    }
}
