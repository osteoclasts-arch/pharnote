import PencilKit
import UIKit

class SmartShapeCanvasView: PKCanvasView {
    var onSmartShapeApplied: ((PKCanvasView) -> Void)?
    var onInteractionDidEnd: ((PKCanvasView) -> Void)?
    var onCanvasTapped: ((CGPoint) -> Void)?
    var isSmartShapeEnabled: Bool = true

    private var trackedTouchID: ObjectIdentifier?
    private var lastTrackedPoint: CGPoint?
    private var accumulatedMovement: CGFloat = 0
    private var didTriggerHold = false
    private var holdWorkItem: DispatchWorkItem?

    private let movementStartThreshold: CGFloat = 18
    private let stillnessTolerance: CGFloat = 3
    private let holdDelay: TimeInterval = 0.32

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        beginTrackingIfPossible(with: touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = trackedTouch(in: touches) else { return }

        let location = touch.location(in: self)
        if let lastTrackedPoint {
            let delta = hypot(location.x - lastTrackedPoint.x, location.y - lastTrackedPoint.y)
            if delta > stillnessTolerance {
                accumulatedMovement += delta
                if accumulatedMovement >= movementStartThreshold {
                    scheduleHoldDetection()
                }
            }
        }
        lastTrackedPoint = location
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        notifyInteractionDidEnd()
        guard trackedTouch(in: touches) != nil else { return }
        
        if accumulatedMovement <= stillnessTolerance {
            if let tapPoint = lastTrackedPoint {
                onCanvasTapped?(tapPoint)
            }
        }
        
        let shouldApplySmartShape = didTriggerHold && accumulatedMovement >= movementStartThreshold
        resetTouchTracking()

        guard shouldApplySmartShape else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.applySmartShapeIfNeeded()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        notifyInteractionDidEnd()
        if trackedTouch(in: touches) != nil {
            resetTouchTracking()
        }
    }

    private func beginTrackingIfPossible(with touches: Set<UITouch>) {
        guard isSmartShapeEnabled || onCanvasTapped != nil else {
            resetTouchTracking()
            return
        }

        guard trackedTouchID == nil, let touch = touches.first else { return }
        trackedTouchID = ObjectIdentifier(touch)
        lastTrackedPoint = touch.location(in: self)
        accumulatedMovement = 0
        didTriggerHold = false
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }

    private func trackedTouch(in touches: Set<UITouch>) -> UITouch? {
        guard let trackedTouchID else { return nil }
        return touches.first(where: { ObjectIdentifier($0) == trackedTouchID })
    }

    private func scheduleHoldDetection() {
        holdWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.didTriggerHold = true
        }
        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: workItem)
    }

    private func resetTouchTracking() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        trackedTouchID = nil
        lastTrackedPoint = nil
        accumulatedMovement = 0
        didTriggerHold = false
    }

    private func notifyInteractionDidEnd() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onInteractionDidEnd?(self)
        }
    }

    private func applySmartShapeIfNeeded() {
        guard isSmartShapeEnabled else { return }
        guard let lastStroke = drawing.strokes.last else { return }
        guard let snappedStroke = WritingSmartShapeRecognizer.snappedStroke(from: lastStroke) else { return }

        let originalDrawing = drawing
        var updatedStrokes = originalDrawing.strokes
        updatedStrokes[updatedStrokes.count - 1] = snappedStroke
        let updatedDrawing = PKDrawing(strokes: updatedStrokes)
        guard updatedDrawing != originalDrawing else { return }

        undoManager?.registerUndo(withTarget: self) { target in
            target.drawing = originalDrawing
            target.onSmartShapeApplied?(target)
        }
        undoManager?.setActionName("Smart Shape")

        drawing = updatedDrawing
        onSmartShapeApplied?(self)
    }
}

final class PencilPassthroughCanvasView: SmartShapeCanvasView {
    var allowsFingerTouchInput: Bool = false {
        didSet {
            updateAllowedTouchTypes()
        }
    }

    override var isUserInteractionEnabled: Bool {
        didSet {
            updateAllowedTouchTypes()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        updateAllowedTouchTypes()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        updateAllowedTouchTypes()
    }

    func refreshDrawingInputState(isEnabled: Bool) {
        updateAllowedTouchTypes()
        drawingGestureRecognizer.isEnabled = false
        drawingGestureRecognizer.isEnabled = isEnabled
        if isEnabled {
            becomeFirstResponder()
        }
    }

    private func updateAllowedTouchTypes() {
        guard isUserInteractionEnabled else {
            drawingGestureRecognizer.allowedTouchTypes = []
            return
        }

        var allowedTouchTypes: [NSNumber] = [
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]

        if allowsFingerTouchInput {
            allowedTouchTypes.insert(
                NSNumber(value: UITouch.TouchType.direct.rawValue),
                at: 0
            )
        }

        drawingGestureRecognizer.allowedTouchTypes = allowedTouchTypes
    }
}

private enum WritingSmartShapeRecognizer {
    static func snappedStroke(from stroke: PKStroke) -> PKStroke? {
        let sampledPoints = sampledPoints(from: stroke)
        guard sampledPoints.count >= 4 else { return nil }

        if let lineStroke = lineStrokeIfNeeded(from: stroke, sampledPoints: sampledPoints) {
            return lineStroke
        }

        guard isClosedShape(sampledPoints) else { return nil }

        if let rectangleStroke = rectangleStrokeIfNeeded(from: stroke, sampledPoints: sampledPoints) {
            return rectangleStroke
        }

        if let ellipseStroke = ellipseStrokeIfNeeded(from: stroke, sampledPoints: sampledPoints) {
            return ellipseStroke
        }

        return nil
    }

    private static func sampledPoints(from stroke: PKStroke) -> [PKStrokePoint] {
        let interpolated = Array(stroke.path.interpolatedPoints(in: nil, by: .distance(6)))
        if interpolated.count >= 4 {
            return interpolated
        }
        return Array(stroke.path)
    }

    private static func lineStrokeIfNeeded(from stroke: PKStroke, sampledPoints: [PKStrokePoint]) -> PKStroke? {
        let locations = sampledPoints.map(\.location)
        let totalLength = polylineLength(locations)
        guard totalLength > 24 else { return nil }

        let straightDistance = locations.first!.distance(to: locations.last!)
        guard straightDistance / max(totalLength, 1) > 0.965 else { return nil }

        return makeStroke(
            from: stroke,
            shapePoints: [locations.first!, locations.last!]
        )
    }

    private static func rectangleStrokeIfNeeded(from stroke: PKStroke, sampledPoints: [PKStrokePoint]) -> PKStroke? {
        let locations = sampledPoints.map(\.location)
        let bounds = boundingRect(for: locations)
        guard bounds.width > 18, bounds.height > 18 else { return nil }

        let simplified = simplifiedClosedPolygon(locations, epsilon: max(bounds.maxDimension * 0.05, 8))
        guard simplified.count == 4 else { return nil }

        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY)
        ]

        let tolerance = max(bounds.maxDimension * 0.24, 16)
        var matchedCornerIndices: Set<Int> = []

        for point in simplified {
            guard let closestCornerIndex = corners.enumerated()
                .filter({ !matchedCornerIndices.contains($0.offset) })
                .min(by: { point.distance(to: $0.element) < point.distance(to: $1.element) })?
                .offset else {
                return nil
            }

            guard point.distance(to: corners[closestCornerIndex]) <= tolerance else {
                return nil
            }

            matchedCornerIndices.insert(closestCornerIndex)
        }

        let orderedCorners = orderPolygonClockwise(corners)
        return makeStroke(
            from: stroke,
            shapePoints: orderedCorners + [orderedCorners.first!]
        )
    }

    private static func ellipseStrokeIfNeeded(from stroke: PKStroke, sampledPoints: [PKStrokePoint]) -> PKStroke? {
        let locations = sampledPoints.map(\.location)
        let bounds = boundingRect(for: locations)
        guard bounds.width > 18, bounds.height > 18 else { return nil }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radiusX = max(bounds.width / 2, 1)
        let radiusY = max(bounds.height / 2, 1)

        let normalizedErrors = locations.map { point in
            let x = (point.x - center.x) / radiusX
            let y = (point.y - center.y) / radiusY
            return abs(sqrt((x * x) + (y * y)) - 1)
        }

        let meanError = normalizedErrors.reduce(0, +) / CGFloat(normalizedErrors.count)
        guard meanError < 0.28 else { return nil }

        let ellipsePoints = stride(from: 0.0, through: Double.pi * 2, by: Double.pi / 16).map { angle in
            CGPoint(
                x: center.x + CGFloat(cos(angle)) * radiusX,
                y: center.y + CGFloat(sin(angle)) * radiusY
            )
        }

        return makeStroke(from: stroke, shapePoints: ellipsePoints)
    }

    private static func makeStroke(from stroke: PKStroke, shapePoints: [CGPoint]) -> PKStroke? {
        let originalPoints = Array(stroke.path)
        guard !originalPoints.isEmpty, shapePoints.count >= 2 else { return nil }

        let templatePoint = originalPoints[originalPoints.count / 2]
        let targetSize = CGSize(
            width: max(templatePoint.size.width, stroke.ink.weight),
            height: max(templatePoint.size.height, stroke.ink.weight)
        )
        let targetOpacity = templatePoint.opacity <= 0.01 ? 1.0 : templatePoint.opacity
        let targetForce = max(templatePoint.force, 1.0)

        let controlPoints = shapePoints.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: Double(index) * 0.02,
                size: targetSize,
                opacity: targetOpacity,
                force: targetForce,
                azimuth: templatePoint.azimuth,
                altitude: templatePoint.altitude
            )
        }

        let path = PKStrokePath(controlPoints: controlPoints, creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform, mask: stroke.mask)
    }

    private static func isClosedShape(_ points: [PKStrokePoint]) -> Bool {
        guard let first = points.first?.location, let last = points.last?.location else { return false }
        let bounds = boundingRect(for: points.map(\.location))
        let tolerance = max(min(bounds.maxDimension * 0.18, 26), 10)
        return first.distance(to: last) <= tolerance
    }

    private static func polylineLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { partial, segment in
            partial + segment.0.distance(to: segment.1)
        }
    }

    private static func boundingRect(for points: [CGPoint]) -> CGRect {
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func simplifiedClosedPolygon(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        var polygonPoints = points
        if let first = polygonPoints.first, let last = polygonPoints.last, first.distance(to: last) <= 8 {
            polygonPoints.removeLast()
        }

        let simplified = douglasPeucker(polygonPoints, epsilon: epsilon)
        var deduped: [CGPoint] = []
        for point in simplified {
            if deduped.last?.distance(to: point) ?? .greatestFiniteMagnitude > 6 {
                deduped.append(point)
            }
        }
        if deduped.count > 2,
           let first = deduped.first,
           let last = deduped.last,
           first.distance(to: last) <= 8 {
            deduped.removeLast()
        }
        return deduped
    }

    private static func douglasPeucker(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let first = points[0]
        let last = points[points.count - 1]
        var maxDistance: CGFloat = 0
        var index = 0

        for candidateIndex in 1..<(points.count - 1) {
            let distance = perpendicularDistance(from: points[candidateIndex], toLineFrom: first, to: last)
            if distance > maxDistance {
                maxDistance = distance
                index = candidateIndex
            }
        }

        if maxDistance > epsilon {
            let left = douglasPeucker(Array(points[0...index]), epsilon: epsilon)
            let right = douglasPeucker(Array(points[index...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }

        return [first, last]
    }

    private static func perpendicularDistance(from point: CGPoint, toLineFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard abs(dx) > .ulpOfOne || abs(dy) > .ulpOfOne else {
            return point.distance(to: start)
        }

        let numerator = abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x)
        let denominator = sqrt((dx * dx) + (dy * dy))
        return numerator / denominator
    }

    private static func orderPolygonClockwise(_ points: [CGPoint]) -> [CGPoint] {
        let center = CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )

        return points.sorted { lhs, rhs in
            atan2(lhs.y - center.y, lhs.x - center.x) < atan2(rhs.y - center.y, rhs.x - center.x)
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }
}

private extension CGRect {
    var maxDimension: CGFloat {
        max(width, height)
    }
}
