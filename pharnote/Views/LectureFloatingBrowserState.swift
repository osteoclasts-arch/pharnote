import Foundation
import SwiftUI

protocol LectureFloatingBrowserState: ObservableObject {
    var isLectureModeEnabled: Bool { get set }
    var lectureWindowPosition: CGPoint { get set }
    var isLectureWindowPinned: Bool { get set }
    var lectureWebURL: String { get set }

    func lecturePopupAllowed(for urlString: String) -> Bool
    func setLecturePopupAllowed(_ allowed: Bool, for urlString: String)
}
