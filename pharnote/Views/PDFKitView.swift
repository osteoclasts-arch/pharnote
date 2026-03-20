import PDFKit
import PencilKit
import SwiftUI
import UIKit

struct PDFKitView: UIViewRepresentable {
    @ObservedObject var viewModel: PDFEditorViewModel
    @ObservedObject var workspaceController: DocumentWorkspaceController
    var onEditAttachment: ((UUID) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            workspaceController: workspaceController,
            onEditAttachment: onEditAttachment
        )
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.delegate = context.coordinator
        pdfView.pageOverlayViewProvider = context.coordinator
        context.coordinator.startObservingPageChanges(of: pdfView)
        viewModel.attachPDFView(pdfView)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.updateCanvasConfigurations()
        context.coordinator.updatePDFInteractionMode(of: uiView)
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.stopObservingPageChanges()
        uiView.delegate = nil
        uiView.pageOverlayViewProvider = nil
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider, PKCanvasViewDelegate, PDFViewDelegate {
        private let viewModel: PDFEditorViewModel
        private let workspaceController: DocumentWorkspaceController
        private let onEditAttachment: ((UUID) -> Void)?
        private weak var observedPDFView: PDFView?
        private var pageChangeObserver: NSObjectProtocol?
        private var scaleFactorObservation: NSKeyValueObservation?
        private var pageCanvases: [Int: PencilPassthroughCanvasView] = [:]
        private var pageContainers: [Int: PDFPageOverlayContainerView] = [:]
        private var canvasPageMap: [ObjectIdentifier: Int] = [:]
        private var managedPDFGestureStates: [ObjectIdentifier: Bool] = [:]
        private var canvasConfigurationCache: [ObjectIdentifier: CanvasConfigurationSignature] = [:]

        init(
            viewModel: PDFEditorViewModel,
            workspaceController: DocumentWorkspaceController,
            onEditAttachment: ((UUID) -> Void)?
        ) {
            self.viewModel = viewModel
            self.workspaceController = workspaceController
            self.onEditAttachment = onEditAttachment
        }

        func startObservingPageChanges(of pdfView: PDFView) {
            stopObservingPageChanges()
            observedPDFView = pdfView
            scaleFactorObservation = pdfView.observe(\.scaleFactor, options: [.initial, .new]) { [weak self, weak pdfView] _, _ in
                guard let self, let pdfView else { return }
                self.updateCanvasRenderingScale(in: pdfView)
            }
            pageChangeObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] notification in
                guard let sender = notification.object as? PDFView else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.viewModel.handlePDFPageChanged(sender.currentPage)
                    guard let document = sender.document,
                          let currentPage = sender.currentPage else {
                        self.setActiveOverlayCanvas(nil)
                        return
                    }
                    let pageIndex = document.index(for: currentPage)
                    if pageIndex == NSNotFound {
                        self.setActiveOverlayCanvas(nil)
                        return
                    }
                    self.setActiveOverlayCanvas(self.pageCanvases[pageIndex])
                }
            }
        }

        func stopObservingPageChanges() {
            if let pageChangeObserver {
                NotificationCenter.default.removeObserver(pageChangeObserver)
                self.pageChangeObserver = nil
            }
            scaleFactorObservation = nil
            if let observedPDFView {
                restoreManagedPDFGestures(in: observedPDFView)
            }
            observedPDFView = nil
            pageCanvases.removeAll()
            pageContainers.removeAll()
            canvasPageMap.removeAll()
            managedPDFGestureStates.removeAll()
            canvasConfigurationCache.removeAll()
            viewModel.setActiveOverlayCanvas(nil)
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let document = view.document else { return nil }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return nil }

            if let existingContainer = pageContainers[pageIndex] {
                configureCanvas(existingContainer.canvas)
                configureAttachmentContainer(existingContainer, pageIndex: pageIndex)
                configureProblemSelectionContainer(existingContainer, pageIndex: pageIndex)
                return existingContainer
            }

            let canvas = PencilPassthroughCanvasView()
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.isScrollEnabled = false
            canvas.alwaysBounceVertical = false
            canvas.alwaysBounceHorizontal = false
            canvas.bouncesZoom = false
            canvas.minimumZoomScale = 1
            canvas.maximumZoomScale = 1
            canvas.contentInset = .zero
            canvas.delegate = self
            canvas.onSmartShapeApplied = { [weak self, weak canvas] _ in
                guard let self, let canvas else { return }
                self.viewModel.overlayDrawingDidChange(pageIndex: pageIndex, drawing: canvas.drawing)
            }
            canvas.onInteractionDidEnd = { [weak self] _ in
                self?.viewModel.refreshCanvasInteractionState()
            }
            canvas.onCanvasTapped = { [weak self] point in
                self?.viewModel.handleCanvasTap(at: point, pageIndex: pageIndex)
            }
            configureCanvas(canvas)

            let container = PDFPageOverlayContainerView(
                canvas: canvas,
                workspaceController: workspaceController,
                pageKey: pageKey(for: pageIndex),
                onEditAttachment: onEditAttachment
            )
            configureAttachmentContainer(container, pageIndex: pageIndex)
            configureProblemSelectionContainer(container, pageIndex: pageIndex)

            pageCanvases[pageIndex] = canvas
            pageContainers[pageIndex] = container
            canvasPageMap[ObjectIdentifier(canvas)] = pageIndex

            if pageIndex == viewModel.currentPageIndex {
                setActiveOverlayCanvas(canvas)
            }

            Task { [weak self, weak canvas] in
                guard let self, let canvas else { return }
                let drawing = await self.viewModel.loadOverlayDrawing(for: pageIndex)
                await MainActor.run {
                    canvas.drawing = drawing
                    if pageIndex == self.viewModel.currentPageIndex {
                        self.setActiveOverlayCanvas(canvas)
                    }
                }
            }

            return container
        }

        func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
            let canvas: PencilPassthroughCanvasView
            if let container = overlayView as? PDFPageOverlayContainerView {
                canvas = container.canvas
            } else if let overlayCanvas = overlayView as? PencilPassthroughCanvasView {
                canvas = overlayCanvas
            } else {
                return
            }
            let drawingGesture = canvas.drawingGestureRecognizer

            conflictingPDFGestures(in: pdfView).forEach { gesture in
                guard gesture !== drawingGesture else { return }
                gesture.require(toFail: drawingGesture)
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let key = ObjectIdentifier(canvasView)
            guard let pageIndex = canvasPageMap[key] else { return }
            viewModel.overlayDrawingDidChange(pageIndex: pageIndex, drawing: canvasView.drawing)
        }

        func updateCanvasConfigurations() {
            pageCanvases.values.forEach { configureCanvas($0) }
            pageContainers.forEach { pageIndex, container in
                configureAttachmentContainer(container, pageIndex: pageIndex)
                configureProblemSelectionContainer(container, pageIndex: pageIndex)
            }
            if let observedPDFView {
                updateCanvasRenderingScale(in: observedPDFView)
            }
        }

        func updatePDFInteractionMode(of pdfView: PDFView) {
            let allowsNavigation = viewModel.allowsPDFNavigation
            let isMarkupModeEnabled = viewModel.isCanvasInputEnabled

            pdfView.isInMarkupMode = isMarkupModeEnabled
            if isMarkupModeEnabled {
                pdfView.clearSelection()
            }

            descendantScrollViews(in: pdfView).forEach { scrollView in
                guard !(scrollView is PKCanvasView) else { return }

                scrollView.isScrollEnabled = allowsNavigation
                scrollView.panGestureRecognizer.isEnabled = allowsNavigation
                scrollView.panGestureRecognizer.allowedTouchTypes = allowsNavigation
                    ? [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                    : []
                scrollView.pinchGestureRecognizer?.isEnabled = allowsNavigation
                scrollView.pinchGestureRecognizer?.allowedTouchTypes = allowsNavigation
                    ? [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                    : []
            }

            updateManagedPDFGestures(in: pdfView, allowsNavigation: allowsNavigation)
            updateCanvasRenderingScale(in: pdfView)
        }

        func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
            if let pageIndex = viewModel.pageIndex(forLinkURL: url) {
                viewModel.goToPage(index: pageIndex)
                return
            }

            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        }

        private func configureCanvas(_ canvas: PencilPassthroughCanvasView) {
            let isInputEnabled = viewModel.isCanvasInputEnabled
            let signature = CanvasConfigurationSignature(
                isInputEnabled: isInputEnabled,
                allowsFingerTouchInput: viewModel.allowsFingerDrawing(),
                drawingPolicy: viewModel.currentDrawingPolicy(),
                toolSignature: viewModel.currentToolSignature(),
                isDrawingEnabled: isInputEnabled
            )
            let key = ObjectIdentifier(canvas)
            guard canvasConfigurationCache[key] != signature else {
                return
            }
            canvasConfigurationCache[key] = signature

            canvas.isUserInteractionEnabled = isInputEnabled
            canvas.allowsFingerTouchInput = signature.allowsFingerTouchInput
            canvas.drawingPolicy = signature.drawingPolicy
            canvas.tool = viewModel.currentTool()
            canvas.drawingGestureRecognizer.isEnabled = isInputEnabled
            if isInputEnabled {
                canvas.becomeFirstResponder()
            }
            if #available(iOS 18.0, *) {
                canvas.isDrawingEnabled = signature.isDrawingEnabled
            }
        }

        private func configureAttachmentContainer(_ container: PDFPageOverlayContainerView, pageIndex: Int) {
            container.updateAttachmentLayer(
                pageKey: pageKey(for: pageIndex),
                allowsInteraction: !viewModel.isCanvasInputEnabled && !viewModel.isReadOnlyMode && !viewModel.isProblemSelectionModeActive,
                onEditAttachment: onEditAttachment
            )
        }

        private func configureProblemSelectionContainer(_ container: PDFPageOverlayContainerView, pageIndex: Int) {
            let selection = viewModel.problemSelection
            let isActivePage = pageIndex == viewModel.currentPageIndex
            let selectionOnThisPage = selection?.pageIndex == pageIndex ? selection : nil
            let cardModel = selectionCardModel(for: pageIndex)

            container.updateProblemSelectionLayer(
                documentId: viewModel.document.id,
                pageId: UUID.stableAnalysisPageID(namespace: viewModel.document.id, pageIndex: pageIndex),
                pageIndex: pageIndex,
                isEnabled: viewModel.isProblemSelectionModeActive && isActivePage,
                selection: selectionOnThisPage,
                cardModel: cardModel,
                onSelectionCompleted: { [weak self] completedSelection in
                    self?.viewModel.handleProblemSelection(completedSelection)
                },
                onPrimaryAction: { [weak self] in
                    self?.handleProblemSelectionPrimaryAction()
                },
                onSecondaryAction: { [weak self] in
                    self?.handleProblemSelectionSecondaryAction()
                },
                onCancelAction: { [weak self] in
                    self?.viewModel.clearProblemSelection()
                }
            )
        }

        private func selectionCardModel(for pageIndex: Int) -> ProblemSelectionOverlayView.SelectionCardModel? {
            guard let selection = viewModel.problemSelection, selection.pageIndex == pageIndex else { return nil }
            let currentMatch = viewModel.problemRecognitionResult?.bestMatch ?? selection.recognizedMatch
            let reviewKey = reviewIdentityKey(for: selection, match: currentMatch)

            if let session = viewModel.problemReviewSession, session.pageIndex == pageIndex {
                if session.status == .completed {
                    return ProblemSelectionOverlayView.SelectionCardModel(
                        title: session.problemMatch?.displayTitle ?? "Review saved",
                        subtitle: "\(session.answers.count) responses saved",
                        statusText: "완료",
                        primaryActionTitle: "닫기",
                        secondaryActionTitle: nil
                    )
                }

                return ProblemSelectionOverlayView.SelectionCardModel(
                    title: session.problemMatch?.displayTitle ?? "복기 진행 중",
                    subtitle: viewModel.problemReviewMessage ?? "복기를 이어가고 있습니다.",
                    statusText: autosaveStatusText(viewModel.problemReviewAutosaveStatus),
                    primaryActionTitle: "계속하기",
                    secondaryActionTitle: "중단"
                )
            }

            if viewModel.reviewedProblemKeys.contains(reviewKey) {
                return ProblemSelectionOverlayView.SelectionCardModel(
                    title: currentMatch?.displayTitle ?? "Review saved",
                    subtitle: "이 문제의 복기가 이미 저장되었습니다.",
                    statusText: "완료",
                    primaryActionTitle: "닫기",
                    secondaryActionTitle: nil
                )
            }

            if let match = viewModel.problemRecognitionResult?.bestMatch {
                return ProblemSelectionOverlayView.SelectionCardModel(
                    title: match.displayTitle,
                    subtitle: trimmed(selection.recognitionText) ?? "선택한 문제를 인식했습니다.",
                    statusText: "인식됨",
                    primaryActionTitle: "복기 시작",
                    secondaryActionTitle: "매칭 변경"
                )
            }

            if let result = viewModel.problemRecognitionResult {
                switch result.status {
                case .matching:
                    return ProblemSelectionOverlayView.SelectionCardModel(
                        title: "문제를 찾는 중",
                        subtitle: "선택 영역을 바탕으로 문제를 비교하고 있습니다.",
                        statusText: "검색 중",
                        primaryActionTitle: "잠시만요",
                        secondaryActionTitle: nil
                    )
                case .ambiguous:
                    return ProblemSelectionOverlayView.SelectionCardModel(
                        title: "후보가 여러 개입니다",
                        subtitle: "가장 가까운 문제부터 확인하세요.",
                        statusText: "애매함",
                        primaryActionTitle: "복기 시작",
                        secondaryActionTitle: "후보 변경"
                    )
                case .failed:
                    return ProblemSelectionOverlayView.SelectionCardModel(
                        title: "문제 인식 실패",
                        subtitle: "선택은 유지됩니다. 복기부터 시작할 수 있습니다.",
                        statusText: "재시도",
                        primaryActionTitle: "기본 복기",
                        secondaryActionTitle: "다시 선택"
                    )
                case .idle, .matched:
                    break
                }
            }

            return ProblemSelectionOverlayView.SelectionCardModel(
                title: "선택된 문제",
                subtitle: "복기를 시작할 준비가 되었습니다.",
                statusText: "대기",
                primaryActionTitle: "복기 시작",
                secondaryActionTitle: nil
            )
        }

        private func handleProblemSelectionPrimaryAction() {
            if let session = viewModel.problemReviewSession {
                if session.status == .completed {
                    viewModel.clearProblemSelection()
                } else {
                    viewModel.isProblemReviewPanelVisible = true
                }
                return
            }

            viewModel.startProblemReview(using: viewModel.problemRecognitionResult?.bestMatch)
        }

        private func handleProblemSelectionSecondaryAction() {
            if viewModel.problemReviewSession != nil {
                viewModel.abandonCurrentProblemReview()
                return
            }

            if viewModel.problemRecognitionResult?.status == .ambiguous {
                viewModel.changeProblemMatch()
                return
            }

            if viewModel.problemRecognitionResult?.status == .failed {
                viewModel.clearProblemSelection()
            }
        }

        private func autosaveStatusText(_ status: ReviewAutosaveStatus) -> String {
            switch status {
            case .idle:
                return "대기"
            case .saving:
                return "저장 중"
            case .saved:
                return "저장됨"
            case .retryNeeded:
                return "재시도 필요"
            }
        }

        private func trimmed(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private func reviewIdentityKey(for selection: ProblemSelection, match: ProblemMatch?) -> String {
            if let canonical = trimmed(match?.canonicalProblemId) {
                return canonical
            }
            return selection.selectionSignature
        }

        private func setActiveOverlayCanvas(_ canvas: PencilPassthroughCanvasView?) {
            if let canvas {
                configureCanvas(canvas)
            }
            viewModel.setActiveOverlayCanvas(canvas)
            canvas?.becomeFirstResponder()
            if let observedPDFView {
                updateCanvasRenderingScale(in: observedPDFView)
            }
        }

        private func updateCanvasRenderingScale(in pdfView: PDFView) {
            let scale = max(1.0, min(pdfView.scaleFactor, 8.0))
            let renderedScale = UIScreen.main.scale * scale
            pageCanvases.values.forEach { canvas in
                if canvas.contentScaleFactor != renderedScale {
                    canvas.contentScaleFactor = renderedScale
                }
                if canvas.layer.contentsScale != renderedScale {
                    canvas.layer.contentsScale = renderedScale
                }
            }
        }

        private func conflictingPDFGestures(in pdfView: PDFView) -> [UIGestureRecognizer] {
            allDescendantGestureRecognizers(in: pdfView).filter { gesture in
                guard gesture.view?.isDescendant(of: pdfView) == true else {
                    return false
                }
                guard managedPDFGestureTypesContain(gesture) else {
                    return false
                }
                return !isCanvasGesture(gesture)
            }
        }

        private func updateManagedPDFGestures(in pdfView: PDFView, allowsNavigation: Bool) {
            let gestures = conflictingPDFGestures(in: pdfView)

            if allowsNavigation {
                restoreManagedPDFGestures(in: pdfView, gestures: gestures)
                return
            }

            gestures.forEach { gesture in
                let key = ObjectIdentifier(gesture)
                if managedPDFGestureStates[key] == nil {
                    managedPDFGestureStates[key] = gesture.isEnabled
                }
                gesture.isEnabled = false
            }
        }

        private func restoreManagedPDFGestures(in pdfView: PDFView, gestures: [UIGestureRecognizer]? = nil) {
            let resolvedGestures = gestures ?? conflictingPDFGestures(in: pdfView)
            resolvedGestures.forEach { gesture in
                let key = ObjectIdentifier(gesture)
                if let originalState = managedPDFGestureStates[key] {
                    gesture.isEnabled = originalState
                    managedPDFGestureStates.removeValue(forKey: key)
                }
            }
        }

        private func managedPDFGestureTypesContain(_ gesture: UIGestureRecognizer) -> Bool {
            gesture is UIPanGestureRecognizer
                || gesture is UIPinchGestureRecognizer
                || gesture is UITapGestureRecognizer
                || gesture is UILongPressGestureRecognizer
                || gesture is UISwipeGestureRecognizer
        }

        private func isCanvasGesture(_ gesture: UIGestureRecognizer) -> Bool {
            if gesture.view is PKCanvasView {
                return true
            }

            return pageCanvases.values.contains { canvas in
                gesture === canvas.drawingGestureRecognizer || gesture.view?.isDescendant(of: canvas) == true
            }
        }

        private func allDescendantGestureRecognizers(in rootView: UIView) -> [UIGestureRecognizer] {
            var gestures = rootView.gestureRecognizers ?? []

            rootView.subviews.forEach { subview in
                gestures.append(contentsOf: allDescendantGestureRecognizers(in: subview))
            }

            return gestures
        }

        private func descendantScrollViews(in rootView: UIView) -> [UIScrollView] {
            var scrollViews: [UIScrollView] = []

            rootView.subviews.forEach { subview in
                if let scrollView = subview as? UIScrollView {
                    scrollViews.append(scrollView)
                }
                scrollViews.append(contentsOf: descendantScrollViews(in: subview))
            }

            return scrollViews
        }

        private func pageKey(for pageIndex: Int) -> String {
            "pdf-page-\(pageIndex)"
        }

        private struct CanvasConfigurationSignature: Equatable {
            let isInputEnabled: Bool
            let allowsFingerTouchInput: Bool
            let drawingPolicy: PKCanvasViewDrawingPolicy
            let toolSignature: String
            let isDrawingEnabled: Bool
        }
    }
}

private final class PDFPageOverlayContainerView: UIView {
    let canvas: PencilPassthroughCanvasView
    private let attachmentView: DocumentWorkspaceAttachmentCanvasUIView
    private let selectionOverlay = ProblemSelectionOverlayView()
    private var pageKey: String?

    init(
        canvas: PencilPassthroughCanvasView,
        workspaceController: DocumentWorkspaceController,
        pageKey: String?,
        onEditAttachment: ((UUID) -> Void)?
    ) {
        self.canvas = canvas
        self.attachmentView = DocumentWorkspaceAttachmentCanvasUIView(
            controller: workspaceController,
            onEditAttachment: onEditAttachment
        )
        self.pageKey = pageKey
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false

        addSubview(attachmentView)
        addSubview(canvas)
        addSubview(selectionOverlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachmentView.frame = bounds
        canvas.frame = bounds
        selectionOverlay.frame = bounds
        if canvas.contentSize != bounds.size {
            canvas.contentSize = bounds.size
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let selectionPoint = convert(point, to: selectionOverlay)
        if selectionOverlay.isUserInteractionEnabled,
           !selectionOverlay.isHidden,
           selectionOverlay.alpha > 0.01,
           selectionOverlay.point(inside: selectionPoint, with: event) {
            return true
        }

        let canvasPoint = convert(point, to: canvas)
        if canvas.isUserInteractionEnabled,
           !canvas.isHidden,
           canvas.alpha > 0.01,
           canvas.point(inside: canvasPoint, with: event) {
            return true
        }

        let attachmentPoint = convert(point, to: attachmentView)
        return attachmentView.point(inside: attachmentPoint, with: event)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }

        let selectionPoint = convert(point, to: selectionOverlay)
        if selectionOverlay.isUserInteractionEnabled,
           !selectionOverlay.isHidden,
           selectionOverlay.alpha > 0.01,
           selectionOverlay.point(inside: selectionPoint, with: event) {
            return selectionOverlay.hitTest(selectionPoint, with: event) ?? selectionOverlay
        }

        let canvasPoint = convert(point, to: canvas)
        if canvas.isUserInteractionEnabled,
           !canvas.isHidden,
           canvas.alpha > 0.01,
           canvas.point(inside: canvasPoint, with: event) {
            return canvas.hitTest(canvasPoint, with: event) ?? canvas
        }

        let attachmentPoint = convert(point, to: attachmentView)
        if attachmentView.point(inside: attachmentPoint, with: event) {
            return attachmentView.hitTest(attachmentPoint, with: event)
        }

        return nil
    }

    func updateAttachmentLayer(
        pageKey: String?,
        allowsInteraction: Bool,
        onEditAttachment: ((UUID) -> Void)?
    ) {
        self.pageKey = pageKey
        attachmentView.onEditAttachment = onEditAttachment
        attachmentView.update(pageKey: pageKey, allowsInteraction: allowsInteraction)
        setNeedsLayout()
    }

    func updateProblemSelectionLayer(
        documentId: UUID,
        pageId: UUID,
        pageIndex: Int,
        isEnabled: Bool,
        selection: ProblemSelection?,
        cardModel: ProblemSelectionOverlayView.SelectionCardModel?,
        onSelectionCompleted: ((ProblemSelection) -> Void)?,
        onPrimaryAction: (() -> Void)?,
        onSecondaryAction: (() -> Void)?,
        onCancelAction: (() -> Void)?
    ) {
        selectionOverlay.documentId = documentId
        selectionOverlay.pageId = pageId
        selectionOverlay.pageIndex = pageIndex
        selectionOverlay.selectionType = .wholeProblem
        selectionOverlay.isSelectionEnabled = isEnabled
        selectionOverlay.onSelectionCompleted = onSelectionCompleted
        selectionOverlay.onPrimaryAction = onPrimaryAction
        selectionOverlay.onSecondaryAction = onSecondaryAction
        selectionOverlay.onCancelAction = onCancelAction

        selectionOverlay.selectedSelection = selection
        selectionOverlay.cardModel = cardModel
        if selection == nil, cardModel == nil {
            selectionOverlay.clearSelection()
        }
        setNeedsLayout()
    }
}
