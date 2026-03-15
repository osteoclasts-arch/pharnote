import Foundation

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
