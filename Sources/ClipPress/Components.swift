import SwiftUI

// MARK: - Button (Action/Button)

enum ButtonVariant {
    case filled, tonal, outlined, text
    /// Neutral text button, used for Cancel.
    case neutralText
}

struct KButtonStyle: ButtonStyle {
    enum Size { case medium, small }

    var variant: ButtonVariant
    var size: Size = .medium
    var fullWidth = false
    var isLoading = false

    func makeBody(configuration: Configuration) -> some View {
        KButtonBody(configuration: configuration, style: self)
    }
}

private struct KButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: KButtonStyle

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    private var isTextVariant: Bool { style.variant == .text || style.variant == .neutralText }

    private var foreground: Color {
        guard isEnabled else { return isTextVariant ? Palette.neutral60 : Palette.neutral50 }
        switch style.variant {
        case .filled: return Palette.onPrimary
        case .tonal: return Palette.onSecondaryContainer
        case .outlined, .text: return Palette.primary
        case .neutralText: return Palette.neutral30
        }
    }

    private var background: Color {
        if isTextVariant { return .clear }
        guard isEnabled else { return Palette.neutral95 }
        switch style.variant {
        case .filled: return Palette.primary
        case .tonal: return Palette.secondaryContainer
        default: return Palette.surface
        }
    }

    private var stateLayer: Color {
        guard isEnabled, !style.isLoading else { return .clear }
        let base: Color = style.variant == .filled ? .white : foreground
        if configuration.isPressed { return base.opacity(0.16) }
        if isHovered { return base.opacity(0.08) }
        return .clear
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s)
        HStack(spacing: Space.s2) {
            if style.isLoading {
                Spinner(color: foreground)
            }
            configuration.label
        }
        .textStyle(style.size == .medium ? .bodyL : .bodyM, .semibold, color: foreground)
        .lineLimit(1)
        .padding(.horizontal, isTextVariant ? Space.s4 : Space.s6)
        .frame(maxWidth: style.fullWidth ? .infinity : nil)
        .frame(height: style.size == .medium ? 48 : 40)
        .background(shape.fill(background))
        .overlay {
            if style.variant == .outlined {
                shape.strokeBorder(isEnabled ? Palette.primary : Palette.neutral80, lineWidth: 1)
            }
        }
        .overlay(shape.fill(stateLayer))
        .shadow(color: .black.opacity(style.variant == .filled && isEnabled && !configuration.isPressed ? 0.36 : 0),
                radius: 2, x: 1, y: 1)
        .focusRing(isFocused, cornerRadius: Radius.s)
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .allowsHitTesting(!style.isLoading)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Icon button

struct IconButton: View {
    let icon: TablerIcon
    let label: String
    var isDestructive = false
    /// Overrides the neutral icon colour, e.g. inside a tinted notification.
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 18)
        }
        .buttonStyle(IconButtonStyle(isDestructive: isDestructive, tint: tint))
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct IconButtonStyle: ButtonStyle {
    let isDestructive: Bool
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, isDestructive: isDestructive, tint: tint)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isDestructive: Bool
    let tint: Color?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    private var foreground: Color {
        guard isEnabled else { return Palette.neutral80 }
        if let tint { return tint }
        if isDestructive && isHovered { return Palette.error }
        return isHovered ? Palette.neutral30 : Palette.neutral60
    }

    private var background: Color {
        guard isEnabled else { return .clear }
        if let tint {
            return tint.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.08 : 0)
        }
        if configuration.isPressed { return Palette.neutral90 }
        return isHovered ? Palette.neutral95 : .clear
    }

    var body: some View {
        configuration.label
            .foregroundColor(foreground)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.s).fill(background))
            .focusRing(isFocused, cornerRadius: Radius.s)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

// MARK: - Primary tabs (Navigation/Tabs/Primary)

struct SegmentedTabs<Option: SegmentOption>: View {
    let label: String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(Option.allCases) { option in
                Button(option.title) { selection = option }
                    .buttonStyle(TabStyle(isActive: selection == option))
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(Space.s1)
        .background(RoundedRectangle(cornerRadius: Radius.s).fill(Palette.neutral95))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct TabStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabBody(configuration: configuration, isActive: isActive)
    }
}

private struct TabBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    private var foreground: Color {
        if !isEnabled { return Palette.neutral70 }
        if isActive { return Palette.neutral20 }
        return isHovered || configuration.isPressed ? Palette.neutral30 : Palette.neutral50
    }

    var body: some View {
        configuration.label
            .textStyle(.bodyM, isActive ? .semibold : .regular, color: foreground)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: Radius.s).fill(Palette.surface).cardShadow()
                }
            }
            .focusRing(isFocused, cornerRadius: Radius.s)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Checkbox

struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
        }
        .buttonStyle(CheckboxButtonStyle(isOn: configuration.isOn))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private struct CheckboxButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        CheckboxBody(configuration: configuration, isOn: isOn)
    }
}

private struct CheckboxBody: View {
    let configuration: ButtonStyleConfiguration
    let isOn: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        let box = RoundedRectangle(cornerRadius: Radius.xs)
        HStack(spacing: Space.s3) {
            ZStack {
                if isOn {
                    box.fill(isEnabled ? Palette.primary : Palette.neutral80)
                    Icon(.check, size: 14).foregroundColor(Palette.onPrimary)
                } else {
                    box.fill(Palette.surface)
                    box.strokeBorder(isEnabled ? (isHovered ? Palette.neutral50 : Palette.neutral70) : Palette.neutral80, lineWidth: 2)
                }
            }
            .frame(width: 18, height: 18)
            .focusRing(isFocused, cornerRadius: Radius.xs)

            configuration.label
                .textStyle(.bodyM, color: isEnabled ? Palette.neutral30 : Palette.neutral60)
        }
        .frame(minHeight: 44)
        .opacity(configuration.isPressed ? 0.8 : 1)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Decimal field (Form/TextField, Small, with step buttons)

/// A number input that accepts decimals like 1.25, with − and + buttons for quick steps.
struct DecimalField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let support: String

    @State private var text = ""
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func format(_ number: Double) -> String {
        formatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    /// Accepts "1.5", "1,5" and "1.5x".
    private var parsed: Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: CharacterSet(charactersIn: "×xX "))
        return Double(cleaned)
    }

    private var isValid: Bool { parsed.map(range.contains) ?? false }

    private var borderColor: Color {
        if !isEnabled { return Palette.neutral80 }
        if !isValid { return Palette.error }
        if isFocused { return Palette.primary }
        return isHovered ? Palette.neutral50 : Palette.neutral70
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .textStyle(.bodyM, .medium, color: isFocused && isValid ? Palette.primary : Palette.neutral40)

            HStack(spacing: 0) {
                IconButton(icon: .minus, label: "Decrease \(label.lowercased())") { nudge(-step) }
                    .disabled(value <= range.lowerBound)

                HStack(spacing: Space.s1) {
                    TextField(label, text: $text)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .focused($isFocused)
                        .onSubmit { text = Self.format(value) }
                    Text(unit)
                        .accessibilityHidden(true)
                }
                .textStyle(.bodyM, color: isEnabled ? Palette.neutral30 : Palette.neutral60)
                .padding(.horizontal, Space.s2)
                .frame(width: 88, height: 40)
                .background(RoundedRectangle(cornerRadius: Radius.s).fill(isEnabled ? Palette.surface : Palette.neutral95))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.s)
                        .strokeBorder(borderColor, lineWidth: isFocused || !isValid ? 2 : 1)
                )
                .onHover { isHovered = $0 }

                IconButton(icon: .plus, label: "Increase \(label.lowercased())") { nudge(step) }
                    .disabled(value >= range.upperBound)
            }

            Text(isValid ? support : "Enter a number from \(Self.format(range.lowerBound)) to \(Self.format(range.upperBound)).")
                .textStyle(.bodyS, color: isValid ? Palette.tertiary : Palette.error)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { newValue in
            if !isFocused { text = Self.format(newValue) }
        }
        .onChange(of: text) { _ in
            // Apply valid input as it is typed; invalid input only shows the error.
            if let number = parsed, range.contains(number) {
                value = (number * 100).rounded() / 100
            }
        }
        .onChange(of: isFocused) { focused in
            if !focused { text = Self.format(value) }
        }
    }

    private func nudge(_ delta: Double) {
        let stepped = ((value + delta) / step).rounded() * step
        value = min(max((stepped * 100).rounded() / 100, range.lowerBound), range.upperBound)
        text = Self.format(value)
    }
}

// MARK: - Notification (Feedback/Notification)

struct Banner: Equatable {
    enum Kind { case info, success, warning, error }

    let kind: Kind
    let message: String
    /// When set, the banner offers "Show in Finder" for this file.
    var revealURL: URL?
}

struct BannerView: View {
    let banner: Banner
    let onReveal: (URL) -> Void
    let onDismiss: () -> Void

    private var colors: (foreground: Color, background: Color, icon: TablerIcon) {
        switch banner.kind {
        case .info: return (Palette.info, Palette.infoContainer, .infoCircle)
        case .success: return (Palette.success, Palette.successContainer, .circleCheck)
        case .warning: return (Palette.warning, Palette.warningContainer, .alertCircle)
        case .error: return (Palette.errorStrong, Palette.errorContainer, .alertCircle)
        }
    }

    var body: some View {
        let colors = self.colors
        HStack(alignment: .center, spacing: Space.s2) {
            Icon(colors.icon, size: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(banner.message)
                    .textStyle(.bodyS, .medium, color: colors.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = banner.revealURL {
                    Button("Show in Finder") { onReveal(url) }
                        .buttonStyle(KButtonStyle(variant: .text, size: .small))
                        .padding(.leading, -Space.s4)
                }
            }
            Spacer(minLength: 0)
            IconButton(icon: .x, label: "Dismiss", tint: colors.foreground, action: onDismiss)
        }
        .foregroundColor(colors.foreground)
        .padding(.leading, Space.s3)
        .frame(minHeight: 32)
        .background(RoundedRectangle(cornerRadius: Radius.s).fill(colors.background))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Progress

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.xs).fill(Palette.neutral90)
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(Palette.primary)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.2), value: value)
        .accessibilityElement()
        .accessibilityLabel("Export progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct Spinner: View {
    var color: Color
    var size: CGFloat = 16
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
            .accessibilityHidden(true)
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m)
        content
            .clipShape(shape)
            .background(shape.fill(Palette.surface).cardShadow())
    }
}
