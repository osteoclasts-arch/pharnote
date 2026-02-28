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
            .frame(
                minWidth: PharTheme.HitArea.minimum,
                minHeight: PharTheme.HitArea.minimum
            )
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.small, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.small, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .hoverEffect(.lift)
    }

    private var foregroundColor: Color {
        if isDestructive {
            return PharTheme.ColorToken.destructive
        }
        if isSelected {
            return .accentColor
        }
        return .primary
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return PharTheme.ColorToken.toolbarFill.opacity(0.9)
        }
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        return PharTheme.ColorToken.toolbarFill.opacity(0.62)
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
                    .foregroundStyle(PharTheme.ColorToken.border),
                alignment: .top
            )
    }
}
