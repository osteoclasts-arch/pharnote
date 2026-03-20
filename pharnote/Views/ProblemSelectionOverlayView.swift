import QuartzCore
import UIKit

final class ProblemSelectionOverlayView: UIView {
    struct SelectionCardModel {
        var title: String
        var subtitle: String
        var statusText: String
        var primaryActionTitle: String
        var secondaryActionTitle: String?
    }

    var onSelectionCompleted: ((ProblemSelection) -> Void)?
    var onPrimaryAction: (() -> Void)?
    var onSecondaryAction: (() -> Void)?
    var onCancelAction: (() -> Void)?
    var documentId: UUID = UUID()
    var pageId: UUID = UUID()
    var pageIndex: Int = 0
    var selectionType: ProblemSelectionType = .wholeProblem

    var isSelectionEnabled: Bool = false {
        didSet {
            if !isSelectionEnabled {
                resetDrawingState()
            }
            setNeedsLayout()
        }
    }

    var selectedSelection: ProblemSelection? {
        didSet { updateSelectionRendering() }
    }

    var cardModel: SelectionCardModel? {
        didSet { updateCardVisibility() }
    }

    private let selectionStrokeLayer = CAShapeLayer()
    private let selectionFillLayer = CAShapeLayer()
    private let bubbleView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let bubbleStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statusPill = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)

    private var trackingPoints: [CGPoint] = []
    private var currentSelectionPath: UIBezierPath?
    private var bubbleFrame: CGRect = .zero

    private let minSelectionDistance: CGFloat = 18
    private let minSelectionArea: CGFloat = 1600

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        setupLayers()
        setupBubble()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectionRendering()
        layoutBubble()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }

        if bubbleView.alpha > 0.01, bubbleView.frame.insetBy(dx: -12, dy: -12).contains(point) {
            let converted = convert(point, to: bubbleView)
            return bubbleView.hitTest(converted, with: event) ?? bubbleView
        }

        if isSelectionEnabled {
            return self
        }

        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isSelectionEnabled else {
            super.touchesBegan(touches, with: event)
            return
        }

        guard let touch = touches.first else { return }
        resetSelectionCard()
        trackingPoints = [touch.location(in: self)]
        updateSelectionPath()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isSelectionEnabled else {
            super.touchesMoved(touches, with: event)
            return
        }

        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        if let last = trackingPoints.last, point.distance(to: last) < 2 {
            return
        }
        trackingPoints.append(point)
        updateSelectionPath()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isSelectionEnabled else {
            super.touchesEnded(touches, with: event)
            return
        }

        guard let completed = finishSelection() else {
            resetDrawingState()
            return
        }
        onSelectionCompleted?(completed)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isSelectionEnabled else {
            super.touchesCancelled(touches, with: event)
            return
        }

        resetDrawingState()
        onCancelAction?()
    }

    func clearSelection() {
        selectedSelection = nil
        cardModel = nil
        resetDrawingState()
    }

    func showReviewedBadge(_ text: String) {
        cardModel = SelectionCardModel(
            title: "Review saved",
            subtitle: text,
            statusText: "완료",
            primaryActionTitle: "닫기",
            secondaryActionTitle: nil
        )
        updateCardVisibility()
    }

    func showRecognitionCard(title: String, subtitle: String, statusText: String, primaryActionTitle: String, secondaryActionTitle: String? = "선택 변경") {
        cardModel = SelectionCardModel(
            title: title,
            subtitle: subtitle,
            statusText: statusText,
            primaryActionTitle: primaryActionTitle,
            secondaryActionTitle: secondaryActionTitle
        )
        updateCardVisibility()
    }

    private func setupLayers() {
        selectionFillLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
        selectionStrokeLayer.fillColor = UIColor.clear.cgColor
        selectionStrokeLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.95).cgColor
        selectionStrokeLayer.lineWidth = 2.4
        selectionStrokeLayer.lineJoin = .round
        selectionStrokeLayer.lineCap = .round
        layer.addSublayer(selectionFillLayer)
        layer.addSublayer(selectionStrokeLayer)
    }

    private func setupBubble() {
        bubbleView.layer.cornerRadius = 18
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.clipsToBounds = true
        bubbleView.alpha = 0
        bubbleView.isUserInteractionEnabled = true

        addSubview(bubbleView)

        bubbleStack.axis = .vertical
        bubbleStack.spacing = 8
        bubbleStack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2

        statusPill.font = .systemFont(ofSize: 11, weight: .bold)
        statusPill.textColor = .label
        statusPill.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        statusPill.textAlignment = .center
        statusPill.layer.cornerRadius = 10
        statusPill.layer.masksToBounds = true
        statusPill.setContentHuggingPriority(.required, for: .horizontal)
        statusPill.setContentCompressionResistancePriority(.required, for: .horizontal)

        let headerRow = UIStackView(arrangedSubviews: [statusPill, UIView()])
        headerRow.axis = .horizontal
        headerRow.spacing = 8

        primaryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        primaryButton.backgroundColor = UIColor.systemBlue
        primaryButton.setTitleColor(.white, for: .normal)
        primaryButton.layer.cornerRadius = 12
        primaryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        primaryButton.addTarget(self, action: #selector(handlePrimaryTap), for: .touchUpInside)

        secondaryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        secondaryButton.backgroundColor = UIColor.secondarySystemBackground
        secondaryButton.setTitleColor(.label, for: .normal)
        secondaryButton.layer.cornerRadius = 12
        secondaryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        secondaryButton.addTarget(self, action: #selector(handleSecondaryTap), for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [primaryButton, secondaryButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        bubbleStack.addArrangedSubview(headerRow)
        bubbleStack.addArrangedSubview(titleLabel)
        bubbleStack.addArrangedSubview(subtitleLabel)
        bubbleStack.addArrangedSubview(buttonRow)

        bubbleView.contentView.addSubview(bubbleStack)
        NSLayoutConstraint.activate([
            bubbleStack.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor, constant: 14),
            bubbleStack.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor, constant: 14),
            bubbleStack.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor, constant: -14),
            bubbleStack.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor, constant: -14)
        ])
    }

    private func updateSelectionPath() {
        guard trackingPoints.count >= 2 else {
            selectionStrokeLayer.path = nil
            selectionFillLayer.path = nil
            return
        }

        let path = UIBezierPath()
        path.move(to: trackingPoints[0])
        for point in trackingPoints.dropFirst() {
            path.addLine(to: point)
        }
        if let first = trackingPoints.first, let last = trackingPoints.last, first.distance(to: last) > 10 {
            path.addLine(to: first)
        }

        currentSelectionPath = path
        selectionStrokeLayer.path = path.cgPath
        selectionFillLayer.path = path.cgPath
    }

    private func finishSelection() -> ProblemSelection? {
        guard trackingPoints.count >= 6 else { return nil }
        guard let bounds = selectionBounds() else { return nil }
        guard bounds.width * bounds.height >= minSelectionArea else { return nil }

        let normalizedPoints = trackingPoints.map {
            ProblemSelectionPoint(
                x: Double(($0.x / max(boundsOfSelectionSpace().width, 1)).clamped(to: 0...1)),
                y: Double(($0.y / max(boundsOfSelectionSpace().height, 1)).clamped(to: 0...1))
            )
        }

        let normalizedBox = ProblemSelectionBoundingBox(
            x: Double((bounds.minX / max(boundsOfSelectionSpace().width, 1)).clamped(to: 0...1)),
            y: Double((bounds.minY / max(boundsOfSelectionSpace().height, 1)).clamped(to: 0...1)),
            width: Double((bounds.width / max(boundsOfSelectionSpace().width, 1)).clamped(to: 0...1)),
            height: Double((bounds.height / max(boundsOfSelectionSpace().height, 1)).clamped(to: 0...1))
        )

        guard normalizedBox.isValid else { return nil }

        let selection = ProblemSelection(
            id: UUID(),
            documentId: documentId,
            pageId: pageId,
            pageIndex: pageIndex,
            selectionType: selectionType,
            polygon: normalizedPoints,
            boundingBox: normalizedBox,
            createdAt: Date(),
            updatedAt: Date(),
            recognitionStatus: .idle,
            recognitionText: nil,
            pageTextFingerprint: nil,
            recognizedMatch: nil
        )

        selectedSelection = selection
        return selection
    }

    private func selectionBounds() -> CGRect? {
        guard !trackingPoints.isEmpty else { return nil }
        let xs = trackingPoints.map(\.x)
        let ys = trackingPoints.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    private func boundsOfSelectionSpace() -> CGSize {
        CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
    }

    private func resetDrawingState() {
        trackingPoints.removeAll()
        currentSelectionPath = nil
        selectionStrokeLayer.path = nil
        selectionFillLayer.path = nil
    }

    private func resetSelectionCard() {
        bubbleView.alpha = 0
        bubbleFrame = .zero
    }

    private func updateSelectionRendering() {
        guard let selection = selectedSelection else {
            bubbleView.alpha = 0
            return
        }

        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let path = UIBezierPath()
        let points = selection.polygon.map {
            CGPoint(x: CGFloat($0.x) * size.width, y: CGFloat($0.y) * size.height)
        }
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.close()
        currentSelectionPath = path
        selectionStrokeLayer.path = path.cgPath
        selectionFillLayer.path = path.cgPath
    }

    private func updateCardVisibility() {
        guard let model = cardModel else {
            bubbleView.alpha = 0
            bubbleFrame = .zero
            return
        }

        titleLabel.text = model.title
        subtitleLabel.text = model.subtitle
        statusPill.text = "  \(model.statusText)  "
        primaryButton.setTitle(model.primaryActionTitle, for: .normal)
        secondaryButton.setTitle(model.secondaryActionTitle, for: .normal)
        secondaryButton.isHidden = model.secondaryActionTitle == nil
        bubbleView.alpha = 1
        setNeedsLayout()
    }

    private func layoutBubble() {
        guard bubbleView.alpha > 0.01, let selection = selectedSelection ?? currentSelectionSelectionForDisplay() else { return }

        let bubbleWidth = min(max(bounds.width * 0.42, 240), 320)
        let bubbleHeight: CGFloat = secondaryButton.isHidden ? 136 : 184

        let selectionFrame = CGRect(
            x: CGFloat(selection.boundingBox.x) * bounds.width,
            y: CGFloat(selection.boundingBox.y) * bounds.height,
            width: CGFloat(selection.boundingBox.width) * bounds.width,
            height: CGFloat(selection.boundingBox.height) * bounds.height
        )

        let preferredX = min(max(selectionFrame.maxX + 12, 12), max(bounds.width - bubbleWidth - 12, 12))
        let preferredY = max(selectionFrame.minY - bubbleHeight - 12, 12)
        let fittedY = min(preferredY, max(bounds.height - bubbleHeight - 12, 12))
        bubbleFrame = CGRect(x: preferredX, y: fittedY, width: bubbleWidth, height: bubbleHeight)
        bubbleView.frame = bubbleFrame
    }

    private func currentSelectionSelectionForDisplay() -> ProblemSelection? {
        selectedSelection
    }

    @objc private func handlePrimaryTap() {
        onPrimaryAction?()
    }

    @objc private func handleSecondaryTap() {
        onSecondaryAction?()
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
