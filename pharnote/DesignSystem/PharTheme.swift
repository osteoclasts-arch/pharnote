import SwiftUI

enum PharTheme {
    enum ColorToken {
        static let appBackground = Color(hex: 0xF5F7FB)
        static let sidebarBackground = Color(hex: 0xEEF3FB)
        static let canvasBackground = Color(hex: 0xFFFDF8)
        static let surfacePrimary = Color(hex: 0xFFFFFF)
        static let surfaceSecondary = Color(hex: 0xF8FAFD)
        static let surfaceTertiary = Color(hex: 0xEAF1FB)
        static let cardBackground = surfacePrimary
        static let heroBlueStart = Color(hex: 0x3B82F6)
        static let heroBlueEnd = Color(hex: 0x6CC6FF)
        static let accentBlue = Color(hex: 0x2F6BFF)
        static let accentMint = Color(hex: 0x8AE3C2)
        static let accentPeach = Color(hex: 0xFFB8A2)
        static let accentCoral = Color(hex: 0xFF8977)
        static let accentButter = Color(hex: 0xFFD86B)
        static let inkPrimary = Color(hex: 0x132238)
        static let inkSecondary = Color(hex: 0x5F6C85)
        static let borderStrong = Color(hex: 0xD6E0F0)
        static let borderSoft = Color(hex: 0xE5ECF6)
        static let border = borderStrong
        static let toolbarFill = Color.white.opacity(0.86)
        static let subtleText = inkSecondary
        static let destructive = Color(hex: 0xE45858)
        static let success = Color(hex: 0x39B37C)
        static let warning = Color(hex: 0xF0B64C)
        static let overlayShadow = Color.black.opacity(0.08)
    }

    enum GradientToken {
        static let appBackdrop = LinearGradient(
            colors: [
                ColorToken.appBackground,
                ColorToken.sidebarBackground,
                Color(hex: 0xFFF8F2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let heroPanel = LinearGradient(
            colors: [
                ColorToken.heroBlueStart,
                ColorToken.heroBlueEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let accentWash = LinearGradient(
            colors: [
                ColorToken.accentMint.opacity(0.55),
                ColorToken.accentButter.opacity(0.42),
                ColorToken.surfacePrimary.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Spacing {
        static let xxxSmall: CGFloat = 2
        static let xxSmall: CGFloat = 6
        static let xSmall: CGFloat = 10
        static let small: CGFloat = 14
        static let medium: CGFloat = 18
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 40
    }

    enum CornerRadius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 30
        static let capsule: CGFloat = 999
    }

    enum Icon {
        static let toolbar: CGFloat = 18
        static let medium: CGFloat = 20
        static let large: CGFloat = 28
    }

    enum HitArea {
        static let minimum: CGFloat = 44
        static let comfortable: CGFloat = 52
    }

    enum ShadowToken {
        static let card = ShadowStyle(color: ColorToken.overlayShadow, radius: 18, x: 0, y: 8)
        static let lifted = ShadowStyle(color: Color.black.opacity(0.12), radius: 28, x: 0, y: 14)
    }

    enum AnimationToken {
        static let toolbarVisibility = Animation.spring(response: 0.34, dampingFraction: 0.84)
        static let pageTransition = Animation.easeInOut(duration: 0.22)
        static let panelReveal = Animation.spring(response: 0.42, dampingFraction: 0.82)
        static let buttonPress = Animation.easeOut(duration: 0.16)
    }
}

enum PharTypography {
    static let heroDisplay = Font.system(size: 34, weight: .bold, design: .rounded)
    static let heroSubtitle = Font.system(size: 16, weight: .medium, design: .rounded)
    static let navigationTitle = Font.system(size: 22, weight: .bold, design: .rounded)
    static let sectionTitle = Font.system(size: 22, weight: .bold, design: .rounded)
    static let cardTitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular, design: .rounded)
    static let bodyStrong = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
    static let captionStrong = Font.system(size: 13, weight: .bold, design: .rounded)
    static let eyebrow = Font.system(size: 11, weight: .bold, design: .rounded)
    static let numberMono = Font.system(size: 15, weight: .semibold, design: .monospaced)
}

enum PharFeatureFlags {
    static var showsInternalTools: Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment["PHARNOTE_HIDE_INTERNAL_TOOLS"] != "1"
#else
        return false
#endif
    }
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
