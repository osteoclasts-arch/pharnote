import SwiftUI

enum PharTheme {
    enum ColorToken {
        static let appBackground = Color(uiColor: .systemGroupedBackground)
        static let canvasBackground = Color.white
        static let cardBackground = Color(uiColor: .secondarySystemBackground)
        static let toolbarFill = Color(uiColor: .tertiarySystemBackground)
        static let border = Color(uiColor: .separator)
        static let subtleText = Color(uiColor: .secondaryLabel)
        static let destructive = Color(uiColor: .systemRed)
    }

    enum Spacing {
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
    }

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum Icon {
        static let toolbar: CGFloat = 18
    }

    enum HitArea {
        static let minimum: CGFloat = 44
    }

    enum AnimationToken {
        static let toolbarVisibility = Animation.spring(response: 0.3, dampingFraction: 0.86)
        static let pageTransition = Animation.easeInOut(duration: 0.2)
    }
}

enum PharTypography {
    static let navigationTitle = Font.title3.weight(.semibold)
    static let sectionTitle = Font.headline
    static let body = Font.body
    static let caption = Font.caption
    static let captionStrong = Font.caption.weight(.semibold)
    static let numberMono = Font.subheadline.monospacedDigit()
}
