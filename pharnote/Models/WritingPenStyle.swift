import Foundation
import PencilKit

/// 필기 도구의 펜 스타일 종류.
/// DocumentEditorView.swift에서 분리하여 컴파일 의존성 단절.
enum WritingPenStyle: String, CaseIterable, Identifiable {
    case ballpoint = "볼펜"
    case fountain = "만년필"
    case brush = "브러시"
    case monoline = "모노라인"
    case pencil = "연필"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .ballpoint:
            return "pencil.tip"
        case .fountain:
            return "fountainpen.tip"
        case .brush:
            return "paintbrush.pointed"
        case .monoline:
            return "pencil.line"
        case .pencil:
            return "pencil.and.scribble"
        }
    }
}

enum WritingEraserMode: String, CaseIterable, Identifiable {
    case precise = "정밀"
    case standard = "일반"
    case stroke = "획"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .precise:
            return "세밀하게"
        case .standard:
            return "기본"
        case .stroke:
            return "한 획씩"
        }
    }

    var accessibilityLabel: String {
        "\(rawValue) 지우개"
    }

    var eraserType: PKEraserTool.EraserType {
        switch self {
        case .precise:
            return .bitmap
        case .standard:
            if #available(iOS 16.4, *) {
                return .fixedWidthBitmap
            }
            return .bitmap
        case .stroke:
            return .vector
        }
    }

    func toolWidth() -> CGFloat? {
        guard #available(iOS 16.4, *) else { return nil }

        switch self {
        case .precise:
            let eraserType = PKEraserTool.EraserType.bitmap
            return max(eraserType.validWidthRange.lowerBound, eraserType.defaultWidth * 0.72)
        case .standard:
            return PKEraserTool.EraserType.fixedWidthBitmap.defaultWidth
        case .stroke:
            return nil
        }
    }

    static var storageKey: String { "WritingEraserMode.selected" }

    static func load(from userDefaults: UserDefaults) -> WritingEraserMode {
        guard let rawValue = userDefaults.string(forKey: storageKey),
              let mode = WritingEraserMode(rawValue: rawValue) else {
            return .stroke
        }
        return mode
    }

    func save(in userDefaults: UserDefaults) {
        userDefaults.set(rawValue, forKey: Self.storageKey)
    }
}
