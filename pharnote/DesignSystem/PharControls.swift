import SwiftUI

struct PharToolbarIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    var isSelected: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: PharTheme.Icon.toolbar, weight: .semibold))
        }
        .buttonStyle(
            PharToolbarButtonStyle(
                isSelected: isSelected,
                isDestructive: isDestructive
            )
        )
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct PharToolbarButtonStyle: ButtonStyle {
    var isSelected: Bool
    var isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: PharTheme.HitArea.comfortable, minHeight: PharTheme.HitArea.comfortable)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(backgroundStyle(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: PharTheme.ColorToken.overlayShadow.opacity(configuration.isPressed ? 0.03 : 0.08),
                radius: configuration.isPressed ? 6 : 14,
                x: 0,
                y: configuration.isPressed ? 3 : 8
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(PharTheme.AnimationToken.buttonPress, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous))
            .hoverEffect(.lift)
    }

    private var foregroundColor: Color {
        if isDestructive {
            return PharTheme.ColorToken.destructive
        }
        if isSelected {
            return PharTheme.ColorToken.accentBlue
        }
        return PharTheme.ColorToken.inkPrimary
    }

    private var borderColor: Color {
        if isSelected {
            return PharTheme.ColorToken.accentBlue.opacity(0.18)
        }
        return PharTheme.ColorToken.borderSoft
    }

    private func backgroundStyle(isPressed: Bool) -> AnyShapeStyle {
        if isPressed {
            return AnyShapeStyle(PharTheme.ColorToken.surfaceTertiary)
        }
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        PharTheme.ColorToken.accentBlue.opacity(0.14),
                        PharTheme.ColorToken.accentMint.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(PharTheme.ColorToken.toolbarFill)
    }
}

struct PharPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PharTypography.bodyStrong)
            .foregroundStyle(Color.white)
            .padding(.horizontal, PharTheme.Spacing.medium)
            .padding(.vertical, PharTheme.Spacing.small)
            .background(
                Capsule(style: .continuous)
                    .fill(PharTheme.GradientToken.heroPanel)
            )
            .shadow(
                color: PharTheme.ColorToken.accentBlue.opacity(configuration.isPressed ? 0.10 : 0.24),
                radius: configuration.isPressed ? 8 : 18,
                x: 0,
                y: configuration.isPressed ? 4 : 10
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(PharTheme.AnimationToken.buttonPress, value: configuration.isPressed)
            .hoverEffect(.highlight)
    }
}

struct PharSoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PharTypography.bodyStrong)
            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
            .padding(.horizontal, PharTheme.Spacing.medium)
            .padding(.vertical, PharTheme.Spacing.small)
            .background(
                Capsule(style: .continuous)
                    .fill(PharTheme.ColorToken.surfacePrimary.opacity(configuration.isPressed ? 0.82 : 0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
            )
            .shadow(
                color: PharTheme.ColorToken.overlayShadow.opacity(configuration.isPressed ? 0.03 : 0.08),
                radius: configuration.isPressed ? 6 : 12,
                x: 0,
                y: configuration.isPressed ? 3 : 8
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(PharTheme.AnimationToken.buttonPress, value: configuration.isPressed)
            .hoverEffect(.highlight)
    }
}

struct PharSurfaceCard<Content: View>: View {
    private let fill: AnyShapeStyle
    private let stroke: Color
    private let shadow: ShadowStyle
    private let content: Content

    init(
        fill: some ShapeStyle = PharTheme.ColorToken.surfacePrimary,
        stroke: Color = PharTheme.ColorToken.borderSoft,
        shadow: ShadowStyle = PharTheme.ShadowToken.card,
        @ViewBuilder content: () -> Content
    ) {
        self.fill = AnyShapeStyle(fill)
        self.stroke = stroke
        self.shadow = shadow
        self.content = content()
    }

    var body: some View {
        content
            .padding(PharTheme.Spacing.large)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

struct PharTagPill: View {
    let text: String
    var tint: Color = PharTheme.ColorToken.surfaceTertiary
    var foreground: Color = PharTheme.ColorToken.inkPrimary

    var body: some View {
        Text(text)
            .font(PharTypography.eyebrow)
            .foregroundStyle(foreground)
            .padding(.horizontal, PharTheme.Spacing.small)
            .padding(.vertical, PharTheme.Spacing.xSmall)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
    }
}

struct PharPanelContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(PharTheme.Spacing.small)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(PharTheme.ColorToken.borderStrong),
                alignment: .top
            )
    }
}
