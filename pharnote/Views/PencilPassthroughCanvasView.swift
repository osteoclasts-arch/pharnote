import PencilKit
import UIKit

final class PencilPassthroughCanvasView: PKCanvasView {
    var allowsFingerTouchInput: Bool = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !allowsFingerTouchInput else {
            return super.hitTest(point, with: event)
        }

        guard let touches = event?.allTouches, !touches.isEmpty else {
            return nil
        }

        let hasPencilTouch = touches.contains(where: { $0.type == .pencil })
        if hasPencilTouch {
            return super.hitTest(point, with: event)
        }

        return nil
    }
}
