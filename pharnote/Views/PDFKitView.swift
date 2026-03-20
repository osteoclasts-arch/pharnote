import Combine
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
        private var textCanvases: [Int: PDFTextAnnotationCanvasUIView] = [:]
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
            textCanvases.removeAll()
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
                configureTextCanvas(existingContainer.textCanvas, pageIndex: pageIndex, page: page, pdfView: view)
                Task { [weak self] in
                    await self?.viewModel.loadTextAnnotationsIfNeeded(for: pageIndex)
                }
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

            let textCanvas = PDFTextAnnotationCanvasUIView(
                viewModel: viewModel,
                pageIndex: pageIndex
            )
            configureTextCanvas(textCanvas, pageIndex: pageIndex, page: page, pdfView: view)
            Task { [weak self] in
                await self?.viewModel.loadTextAnnotationsIfNeeded(for: pageIndex)
            }

            let container = PDFPageOverlayContainerView(
                canvas: canvas,
                textCanvas: textCanvas,
                workspaceController: workspaceController,
                pdfView: view,
                page: page,
                pageIndex: pageIndex,
                pageKey: pageKey(for: pageIndex),
                onEditAttachment: onEditAttachment
            )
            configureAttachmentContainer(container, pageIndex: pageIndex)
            configureProblemSelectionContainer(container, pageIndex: pageIndex)

            pageCanvases[pageIndex] = canvas
            textCanvases[pageIndex] = textCanvas
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
            textCanvases.forEach { pageIndex, textCanvas in
                guard let container = pageContainers[pageIndex] else { return }
                configureTextCanvas(textCanvas, pageIndex: pageIndex, page: container.page, pdfView: observedPDFView)
            }
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
            textCanvases.values.forEach { $0.setNeedsLayout() }
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

        private func configureTextCanvas(_ textCanvas: PDFTextAnnotationCanvasUIView, pageIndex: Int, page: PDFPage, pdfView: PDFView?) {
            textCanvas.update(pageIndex: pageIndex, page: page, pdfView: pdfView)
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
    let textCanvas: PDFTextAnnotationCanvasUIView
    private let attachmentView: DocumentWorkspaceAttachmentCanvasUIView
    private let selectionOverlay = ProblemSelectionOverlayView()
    private weak var pdfView: PDFView?
    let page: PDFPage
    let pageIndex: Int
    private var pageKey: String?

    init(
        canvas: PencilPassthroughCanvasView,
        textCanvas: PDFTextAnnotationCanvasUIView,
        workspaceController: DocumentWorkspaceController,
        pdfView: PDFView,
        page: PDFPage,
        pageIndex: Int,
        pageKey: String?,
        onEditAttachment: ((UUID) -> Void)?
    ) {
        self.canvas = canvas
        self.textCanvas = textCanvas
        self.attachmentView = DocumentWorkspaceAttachmentCanvasUIView(
            controller: workspaceController,
            onEditAttachment: onEditAttachment
        )
        self.pdfView = pdfView
        self.page = page
        self.pageIndex = pageIndex
        self.pageKey = pageKey
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false

        addSubview(attachmentView)
        addSubview(canvas)
        addSubview(textCanvas)
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
        textCanvas.frame = bounds
        selectionOverlay.frame = bounds
        if canvas.contentSize != bounds.size {
            canvas.contentSize = bounds.size
        }
        textCanvas.update(pageIndex: pageIndex, page: page, pdfView: pdfView)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let selectionPoint = convert(point, to: selectionOverlay)
        if selectionOverlay.isUserInteractionEnabled,
           !selectionOverlay.isHidden,
           selectionOverlay.alpha > 0.01,
           selectionOverlay.point(inside: selectionPoint, with: event) {
            return true
        }

        let textPoint = convert(point, to: textCanvas)
        if textCanvas.isUserInteractionEnabled,
           !textCanvas.isHidden,
           textCanvas.alpha > 0.01,
           textCanvas.point(inside: textPoint, with: event) {
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

        let textPoint = convert(point, to: textCanvas)
        if textCanvas.isUserInteractionEnabled,
           !textCanvas.isHidden,
           textCanvas.alpha > 0.01,
           textCanvas.point(inside: textPoint, with: event) {
            return textCanvas.hitTest(textPoint, with: event) ?? textCanvas
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

private struct PDFPageGeometryMapper {
    let pageBounds: CGRect
    let containerBounds: CGRect

    var scaleX: CGFloat { pageBounds.width == 0 ? 1 : containerBounds.width / pageBounds.width }
    var scaleY: CGFloat { pageBounds.height == 0 ? 1 : containerBounds.height / pageBounds.height }

    func viewRect(for pageRect: CGRect) -> CGRect {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return pageRect }
        let originX = (pageRect.minX - pageBounds.minX) * scaleX
        let topDistance = pageRect.maxY - pageBounds.minY
        let originY = containerBounds.height - (topDistance * scaleY)
        return CGRect(x: originX, y: originY, width: pageRect.width * scaleX, height: pageRect.height * scaleY)
    }

    func pageRect(for viewRect: CGRect) -> CGRect {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return viewRect }
        let x = pageBounds.minX + viewRect.minX / scaleX
        let pageMaxY = pageBounds.minY + (containerBounds.height - viewRect.minY) / scaleY
        let y = pageMaxY - (viewRect.height / scaleY)
        return CGRect(x: x, y: y, width: viewRect.width / scaleX, height: viewRect.height / scaleY)
    }

    func insertionRect(for viewPoint: CGPoint, width: CGFloat) -> CGRect {
        let clampedWidth = min(max(width, 220), max(containerBounds.width - 24, 220))
        let originX = min(max(viewPoint.x, 12), max(containerBounds.width - clampedWidth - 12, 12))
        let originY = min(max(viewPoint.y - 4, 12), max(containerBounds.height - 60, 12))
        return CGRect(x: originX, y: originY, width: clampedWidth, height: 48)
    }
}

private struct PDFTextSnapGuide {
    enum Orientation {
        case vertical
        case horizontal
    }

    let orientation: Orientation
    let frame: CGRect
}

private struct PDFTextSnapResult {
    let frame: CGRect
    let guide: PDFTextSnapGuide?
}

private final class PDFTextAnnotationHaptics {
    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)

    func selectionChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    func lightImpact() {
        light.impactOccurred(intensity: 0.75)
        light.prepare()
    }

    func mediumImpact() {
        medium.impactOccurred(intensity: 0.9)
        medium.prepare()
    }
}

private final class PDFTextAnnotationSnapGuideView: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true
        alpha = 0.9
        layer.cornerRadius = 0.5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ guide: PDFTextSnapGuide?) {
        guard let guide else {
            isHidden = true
            return
        }
        isHidden = false
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.28)
        switch guide.orientation {
        case .vertical:
            frame = CGRect(x: guide.frame.minX, y: guide.frame.minY, width: 2, height: guide.frame.height).integral
        case .horizontal:
            frame = CGRect(x: guide.frame.minX, y: guide.frame.minY, width: guide.frame.width, height: 2).integral
        }
    }
}

private enum ResizeCorner: Int, CaseIterable {
    case topLeft = 0
    case topRight = 1
    case bottomLeft = 2
    case bottomRight = 3
}

private final class ResizeHandleView: UIView {
    let corner: ResizeCorner
    private let visualSize: CGFloat = 10
    private let hitSlop: CGFloat = 12

    init(corner: ResizeCorner) {
        self.corner = corner
        super.init(frame: .zero)
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.95)
        layer.cornerRadius = visualSize / 2
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.cgColor
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point)
    }
}

@MainActor
final class PDFTextAnnotationCanvasUIView: UIView, UIGestureRecognizerDelegate {
    private let viewModel: PDFEditorViewModel
    private var pageIndex: Int
    private weak var pdfView: PDFView?
    private weak var page: PDFPage?
    private var cancellables: Set<AnyCancellable> = []
    private var annotationViews: [UUID: PDFTextAnnotationView] = [:]
    private let snapGuideView = PDFTextAnnotationSnapGuideView()
    private let toolbarView = PDFTextAnnotationToolbarView()
    private let haptics = PDFTextAnnotationHaptics()
    private let backgroundTapGesture = UITapGestureRecognizer()

    init(viewModel: PDFEditorViewModel, pageIndex: Int) {
        self.viewModel = viewModel
        self.pageIndex = pageIndex
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        addSubview(snapGuideView)
        addSubview(toolbarView)
        toolbarView.isHidden = true
        toolbarView.onFontSize = { [weak self, weak viewModel] size in
            guard let self, let viewModel, let id = viewModel.selectedTextAnnotationID, let pageIndex = viewModel.selectedTextAnnotationPageIndex else { return }
            guard var annotation = viewModel.textAnnotations(for: pageIndex).first(where: { $0.id == id }) else { return }
            annotation.fontSize = size
            viewModel.upsertTextAnnotation(annotation)
            self.haptics.selectionChanged()
        }
        toolbarView.onFontWeightToggle = { [weak self, weak viewModel] in
            guard let self, let viewModel, let id = viewModel.selectedTextAnnotationID, let pageIndex = viewModel.selectedTextAnnotationPageIndex else { return }
            guard var annotation = viewModel.textAnnotations(for: pageIndex).first(where: { $0.id == id }) else { return }
            annotation.fontWeight = annotation.fontWeight == "bold" ? "regular" : "bold"
            viewModel.upsertTextAnnotation(annotation)
            self.haptics.selectionChanged()
        }
        toolbarView.onItalicToggle = { [weak self, weak viewModel] in
            guard let self, let viewModel, let id = viewModel.selectedTextAnnotationID, let pageIndex = viewModel.selectedTextAnnotationPageIndex else { return }
            guard var annotation = viewModel.textAnnotations(for: pageIndex).first(where: { $0.id == id }) else { return }
            annotation.fontStyle = annotation.fontStyle == "italic" ? "normal" : "italic"
            viewModel.upsertTextAnnotation(annotation)
            self.haptics.selectionChanged()
        }
        toolbarView.onFontFamily = { [weak self, weak viewModel] family in
            guard let self, let viewModel, let id = viewModel.selectedTextAnnotationID, let pageIndex = viewModel.selectedTextAnnotationPageIndex else { return }
            guard var annotation = viewModel.textAnnotations(for: pageIndex).first(where: { $0.id == id }) else { return }
            annotation.fontFamily = family
            viewModel.upsertTextAnnotation(annotation)
            self.haptics.selectionChanged()
        }
        toolbarView.onAlignment = { [weak self, weak viewModel] alignment in
            guard let self, let viewModel, let id = viewModel.selectedTextAnnotationID, let pageIndex = viewModel.selectedTextAnnotationPageIndex else { return }
            guard var annotation = viewModel.textAnnotations(for: pageIndex).first(where: { $0.id == id }) else { return }
            annotation.textAlignment = alignment
            viewModel.upsertTextAnnotation(annotation)
            self.haptics.selectionChanged()
        }
        toolbarView.onColor = { [weak self, weak viewModel] colorHex in
            guard let self, let viewModel, let id = viewModel.selectedTextAnnotationID, let pageIndex = viewModel.selectedTextAnnotationPageIndex else { return }
            guard var annotation = viewModel.textAnnotations(for: pageIndex).first(where: { $0.id == id }) else { return }
            annotation.textColor = colorHex
            viewModel.upsertTextAnnotation(annotation)
            self.haptics.selectionChanged()
        }
        toolbarView.onDuplicate = { [weak self, weak viewModel] in
            guard let self, let viewModel, let id = viewModel.selectedTextAnnotationID, let pageIndex = viewModel.selectedTextAnnotationPageIndex else { return }
            viewModel.duplicateTextAnnotation(id: id, pageIndex: pageIndex)
            self.haptics.lightImpact()
        }
        toolbarView.onDelete = { [weak self, weak viewModel] in
            guard let self, let viewModel, let id = viewModel.selectedTextAnnotationID, let pageIndex = viewModel.selectedTextAnnotationPageIndex else { return }
            viewModel.deleteTextAnnotation(id: id, pageIndex: pageIndex)
            self.haptics.mediumImpact()
        }

        backgroundTapGesture.addTarget(self, action: #selector(handleBackgroundTap(_:)))
        backgroundTapGesture.cancelsTouchesInView = false
        backgroundTapGesture.delegate = self
        addGestureRecognizer(backgroundTapGesture)

        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncAnnotationViews()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(pageIndex: Int, page: PDFPage, pdfView: PDFView?) {
        self.pageIndex = pageIndex
        self.page = page
        self.pdfView = pdfView
        syncAnnotationViews()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let mapper = currentMapper() else { return }
        layoutAnnotationViews(using: mapper)
        layoutToolbar(using: mapper)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return false }

        if !toolbarView.isHidden, toolbarView.frame.insetBy(dx: -12, dy: -12).contains(point) {
            return true
        }

        if annotationViews.values.contains(where: { $0.frame.insetBy(dx: -10, dy: -10).contains(point) }) {
            return true
        }

        let isEditingThisPage = viewModel.editingTextAnnotationID != nil && viewModel.selectedTextAnnotationPageIndex == pageIndex
        return viewModel.isTextInsertionModeActive || isEditingThisPage
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: self)
        let hitView = hitTest(location, with: nil)
        return hitView === self
    }

    private func syncAnnotationViews() {
        let annotations = viewModel.textAnnotations(for: pageIndex)
        let visibleIDs = Set(annotations.map(\.id))

        let removedIDs = annotationViews.keys.filter { !visibleIDs.contains($0) }
        for id in removedIDs {
            annotationViews[id]?.removeFromSuperview()
            annotationViews.removeValue(forKey: id)
        }

        for annotation in annotations {
            let view = annotationViews[annotation.id] ?? makeAnnotationView(for: annotation)
            annotationViews[annotation.id] = view
            if view.superview == nil {
                addSubview(view)
            }
            view.update(
                annotation: annotation,
                isSelected: viewModel.selectedTextAnnotationID == annotation.id && viewModel.selectedTextAnnotationPageIndex == pageIndex,
                isEditing: viewModel.editingTextAnnotationID == annotation.id
            )
        }

        toolbarView.isHidden = viewModel.isReadOnlyMode || viewModel.selectedTextAnnotationID == nil || viewModel.selectedTextAnnotationPageIndex != pageIndex
        setNeedsLayout()
    }

    private func makeAnnotationView(for annotation: PDFTextAnnotation) -> PDFTextAnnotationView {
        let view = PDFTextAnnotationView(annotation: annotation)
        view.snapTargetProvider = { [weak self] in
            self?.snapTargets(excluding: annotation.id) ?? []
        }
        view.onSelect = { [weak self] in
            guard let self else { return }
            self.viewModel.selectTextAnnotation(id: annotation.id, pageIndex: self.pageIndex)
            self.haptics.selectionChanged()
            self.setNeedsLayout()
        }
        view.onBeginEditing = { [weak self] in
            guard let self else { return }
            self.viewModel.beginEditingTextAnnotation(id: annotation.id, pageIndex: self.pageIndex)
            self.haptics.mediumImpact()
            self.setNeedsLayout()
        }
        view.onAnnotationChanged = { [weak self] frame, updated in
            self?.applyAnnotationChange(frame: frame, annotation: updated)
            self?.setNeedsLayout()
        }
        view.onSnapGuideChanged = { [weak self] guide in
            self?.snapGuideView.show(guide)
        }
        view.onEditingEnded = { [weak self] in
            self?.viewModel.commitTextAnnotationEditing()
            self?.snapGuideView.show(nil)
            self?.setNeedsLayout()
        }
        return view
    }

    private func snapTargets(excluding excludedID: UUID) -> [CGRect] {
        viewModel.textAnnotations(for: pageIndex)
            .filter { $0.id != excludedID }
            .compactMap { annotation in
                guard let view = annotationViews[annotation.id] else { return nil }
                return view.frame
            }
    }

    private func layoutAnnotationViews(using mapper: PDFPageGeometryMapper) {
        let annotations = viewModel.textAnnotations(for: pageIndex)
        for annotation in annotations {
            guard let view = annotationViews[annotation.id] else { continue }
            let pageRect = CGRect(x: CGFloat(annotation.x), y: CGFloat(annotation.y), width: CGFloat(annotation.width), height: CGFloat(annotation.height))
            let viewRect = mapper.viewRect(for: pageRect)
            if view.frame.integral != viewRect.integral {
                view.frame = viewRect.integral
            }
            view.update(
                annotation: annotation,
                isSelected: viewModel.selectedTextAnnotationID == annotation.id && viewModel.selectedTextAnnotationPageIndex == pageIndex,
                isEditing: viewModel.editingTextAnnotationID == annotation.id
            )
        }

        if let selectedID = viewModel.selectedTextAnnotationID, let selectedView = annotationViews[selectedID] {
            bringSubviewToFront(selectedView)
            bringSubviewToFront(snapGuideView)
            bringSubviewToFront(toolbarView)
        }
    }

    private func layoutToolbar(using mapper: PDFPageGeometryMapper) {
        guard let selectedID = viewModel.selectedTextAnnotationID,
              viewModel.selectedTextAnnotationPageIndex == pageIndex,
              let selectedView = annotationViews[selectedID],
              !viewModel.isReadOnlyMode else {
            toolbarView.isHidden = true
            return
        }

        toolbarView.update(annotation: selectedView.currentAnnotation)
        let size = toolbarView.sizeThatFits(CGSize(width: bounds.width - 24, height: 40))
        let selectedFrame = selectedView.frame
        let x = min(max(selectedFrame.midX - size.width / 2, 12), max(bounds.width - size.width - 12, 12))
        let aboveY = selectedFrame.minY - size.height - 12
        let belowY = selectedFrame.maxY + 12
        let y = aboveY >= 12 ? aboveY : min(belowY, max(bounds.height - size.height - 12, 12))
        toolbarView.frame = CGRect(x: x, y: y, width: size.width, height: size.height).integral
        toolbarView.isHidden = false
        bringSubviewToFront(toolbarView)
    }

    private func currentMapper() -> PDFPageGeometryMapper? {
        guard let page, bounds.width > 0, bounds.height > 0 else { return nil }
        let displayBox = pdfView?.displayBox ?? .cropBox
        let pageBounds = page.bounds(for: displayBox)
        return PDFPageGeometryMapper(pageBounds: pageBounds, containerBounds: bounds)
    }

    private func applyAnnotationChange(frame: CGRect, annotation: PDFTextAnnotation) {
        guard let mapper = currentMapper() else { return }
        var updated = annotation
        let pageRect = mapper.pageRect(for: frame)
        updated.x = Double(pageRect.minX)
        updated.y = Double(pageRect.minY)
        updated.width = Double(pageRect.width)
        updated.height = Double(pageRect.height)
        updated.pageIndex = pageIndex
        updated.pageId = UUID.stableAnalysisPageID(namespace: viewModel.document.id, pageIndex: pageIndex)
        viewModel.upsertTextAnnotation(updated)
    }

    @objc
    private func handleBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, !viewModel.isReadOnlyMode else { return }
        let location = recognizer.location(in: self)
        let hitView = hitTest(location, with: nil)
        guard hitView === self else {
            if viewModel.editingTextAnnotationID != nil {
                viewModel.commitTextAnnotationEditing()
            }
            return
        }

        guard let mapper = currentMapper() else { return }

        if viewModel.isTextInsertionModeActive {
            let insertionRect = mapper.insertionRect(for: location, width: 252)
            let pageRect = mapper.pageRect(for: insertionRect)
            _ = viewModel.createTextAnnotation(pageIndex: pageIndex, pageRect: pageRect)
            haptics.mediumImpact()
            setNeedsLayout()
        } else {
            viewModel.commitTextAnnotationEditing()
            viewModel.clearTextAnnotationSelection()
            snapGuideView.show(nil)
        }
    }
}

private final class PDFTextAnnotationView: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
    private(set) var currentAnnotation: PDFTextAnnotation
    private let textView = UITextView()
    private let accessoryView = PDFTextAnnotationAccessoryView()
    private let padding: CGFloat = 10
    private var handleViews: [ResizeCorner: ResizeHandleView] = [:]
    private let selectionLayer = CAShapeLayer()
    private var isSelected = false
    private var isEditing = false
    private var isApplyingAnnotation = false

    var onSelect: (() -> Void)?
    var onBeginEditing: (() -> Void)?
    var onAnnotationChanged: ((CGRect, PDFTextAnnotation) -> Void)?
    var onSnapGuideChanged: ((PDFTextSnapGuide?) -> Void)?
    var snapTargetProvider: (() -> [CGRect])?
    var onEditingEnded: (() -> Void)?

    init(annotation: PDFTextAnnotation) {
        self.currentAnnotation = annotation
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        layer.addSublayer(selectionLayer)
        setupTextView()
        setupHandles()
        setupGestures()
        setupAccessoryActions()
        update(annotation: annotation, isSelected: false, isEditing: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(annotation: PDFTextAnnotation, isSelected: Bool, isEditing: Bool) {
        currentAnnotation = annotation
        self.isSelected = isSelected
        self.isEditing = isEditing
        isApplyingAnnotation = true
        if textView.text != annotation.text {
            textView.text = annotation.text
        }
        textView.font = annotation.resolvedFont()
        textView.textColor = UIColor(Color(hex: annotation.textColor) ?? .black)
        textView.textAlignment = annotation.paragraphAlignment()
        textView.typingAttributes = annotation.textAttributes()
        accessoryView.update(annotation: annotation)
        textView.isEditable = isEditing
        textView.isSelectable = isEditing
        textView.isUserInteractionEnabled = isEditing
        if isEditing, !textView.isFirstResponder {
            _ = textView.becomeFirstResponder()
        } else if !isEditing, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
        selectionLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(isEditing ? 0.75 : 0.52).cgColor
        selectionLayer.isHidden = !(isSelected || isEditing)
        handleViews.values.forEach { $0.isHidden = !(isSelected && !isEditing) }
        isApplyingAnnotation = false
        updateTextSizing()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds.insetBy(dx: padding, dy: padding)
        selectionLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 12).cgPath
        layoutHandles()
    }

    func becomeEditing() {
        isEditing = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        _ = textView.becomeFirstResponder()
        updateChrome()
    }

    private func setupTextView() {
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.inputAccessoryView = accessoryView
        addSubview(textView)
    }

    private func setupAccessoryActions() {
        accessoryView.onDone = { [weak self] in
            self?.textView.resignFirstResponder()
        }
        accessoryView.onFontSizeDecrement = { [weak self] in
            self?.adjustFontSize(by: -2)
        }
        accessoryView.onFontSizeIncrement = { [weak self] in
            self?.adjustFontSize(by: 2)
        }
        accessoryView.onToggleBold = { [weak self] in
            self?.toggleFontWeight()
        }
        accessoryView.onToggleItalic = { [weak self] in
            self?.toggleFontStyle()
        }
        accessoryView.onAlignment = { [weak self] alignment in
            self?.setAlignment(alignment)
        }
    }

    private func setupHandles() {
        for corner in ResizeCorner.allCases {
            let handle = ResizeHandleView(corner: corner)
            handle.isHidden = true
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            handle.addGestureRecognizer(pan)
            addSubview(handle)
            handleViews[corner] = handle
        }
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        tap.delegate = self
        addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        movePan.maximumNumberOfTouches = 1
        movePan.delegate = self
        addGestureRecognizer(movePan)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        !isEditing
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func handleSingleTap() {
        onSelect?()
    }

    @objc private func handleDoubleTap() {
        onBeginEditing?()
        becomeEditing()
    }

    private func updateChrome() {
        selectionLayer.isHidden = !(isSelected || isEditing)
        handleViews.values.forEach { $0.isHidden = !(isSelected && !isEditing) }
        setNeedsLayout()
    }

    private func updateTextSizing() {
        guard bounds.width > 0 else { return }
        let width = max(bounds.width - padding * 2, 140)
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let desiredHeight = max(44, ceil(fitting.height))
        let desiredFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: desiredHeight + padding * 2).integral
        if abs(desiredFrame.height - frame.height) > 0.5 {
            frame = desiredFrame
            if !isApplyingAnnotation {
                onAnnotationChanged?(desiredFrame, updatedAnnotation(from: desiredFrame))
            }
        }
    }

    private func updatedAnnotation(from frame: CGRect) -> PDFTextAnnotation {
        var updated = currentAnnotation
        updated.text = textView.text ?? ""
        updated.x = Double(frame.minX)
        updated.y = Double(frame.minY)
        updated.width = Double(frame.width)
        updated.height = Double(frame.height)
        updated.updatedAt = Date()
        return updated
    }

    private func layoutHandles() {
        let size: CGFloat = 10
        let offset: CGFloat = -5
        handleViews[.topLeft]?.frame = CGRect(x: offset, y: offset, width: size, height: size)
        handleViews[.topRight]?.frame = CGRect(x: bounds.width - size - offset, y: offset, width: size, height: size)
        handleViews[.bottomLeft]?.frame = CGRect(x: offset, y: bounds.height - size - offset, width: size, height: size)
        handleViews[.bottomRight]?.frame = CGRect(x: bounds.width - size - offset, y: bounds.height - size - offset, width: size, height: size)
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingAnnotation else { return }
        currentAnnotation.text = textView.text ?? ""
        updateTextSizing()
        onAnnotationChanged?(frame, updatedAnnotation(from: frame))
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        isEditing = false
        updateChrome()
        onEditingEnded?()
    }

    @objc private func handleMovePan(_ gesture: UIPanGestureRecognizer) {
        guard !isEditing, let superview else { return }
        let translation = gesture.translation(in: superview)
        switch gesture.state {
        case .began, .changed:
            frame.origin.x += translation.x
            frame.origin.y += translation.y
            gesture.setTranslation(.zero, in: superview)
            let snapped = snapFrame(frame, in: superview.bounds, additionalTargets: snapTargetProvider?() ?? [])
            frame = snapped.frame.integral
            onSnapGuideChanged?(snapped.guide)
            onAnnotationChanged?(frame, updatedAnnotation(from: frame))
        default:
            onSnapGuideChanged?(nil)
            onAnnotationChanged?(frame, updatedAnnotation(from: frame))
        }
    }

    @objc private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard !isEditing, let handle = gesture.view as? ResizeHandleView, let superview else { return }
        let translation = gesture.translation(in: superview)
        var newFrame = frame

        switch handle.corner {
        case .topLeft:
            newFrame.origin.x += translation.x
            newFrame.origin.y += translation.y
            newFrame.size.width -= translation.x
            newFrame.size.height -= translation.y
        case .topRight:
            newFrame.origin.y += translation.y
            newFrame.size.width += translation.x
            newFrame.size.height -= translation.y
        case .bottomLeft:
            newFrame.origin.x += translation.x
            newFrame.size.width -= translation.x
            newFrame.size.height += translation.y
        case .bottomRight:
            newFrame.size.width += translation.x
            newFrame.size.height += translation.y
        }

        newFrame.size.width = max(newFrame.size.width, 150)
        newFrame.size.height = max(newFrame.size.height, 44)
        if newFrame.origin.x < 0 {
            newFrame.size.width += newFrame.origin.x
            newFrame.origin.x = 0
        }
        if newFrame.origin.y < 0 {
            newFrame.size.height += newFrame.origin.y
            newFrame.origin.y = 0
        }

        let snapped = snapFrame(newFrame, in: superview.bounds, additionalTargets: snapTargetProvider?() ?? [])
        frame = snapped.frame.integral
        gesture.setTranslation(.zero, in: superview)
        updateTextSizing()
        onSnapGuideChanged?(snapped.guide)
        onAnnotationChanged?(frame, updatedAnnotation(from: frame))
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            onSnapGuideChanged?(nil)
        }
    }

    private func snapFrame(_ frame: CGRect, in bounds: CGRect, additionalTargets: [CGRect]) -> PDFTextSnapResult {
        let threshold: CGFloat = 10
        var snapped = frame
        var guide: PDFTextSnapGuide?

        func isNear(_ value: CGFloat, _ target: CGFloat) -> Bool {
            abs(value - target) <= threshold
        }

        var bestDistance = CGFloat.greatestFiniteMagnitude
        var bestGuide: PDFTextSnapGuide?

        func considerVertical(_ candidate: CGFloat, target: CGFloat, originX: CGFloat, guideX: CGFloat) {
            let distance = abs(candidate - target)
            guard distance <= threshold, distance < bestDistance else { return }
            bestDistance = distance
            snapped.origin.x = originX
            bestGuide = PDFTextSnapGuide(orientation: .vertical, frame: CGRect(x: guideX, y: 0, width: 1, height: bounds.height))
        }

        func considerHorizontal(_ candidate: CGFloat, target: CGFloat, originY: CGFloat, guideY: CGFloat) {
            let distance = abs(candidate - target)
            guard distance <= threshold, distance < bestDistance else { return }
            bestDistance = distance
            snapped.origin.y = originY
            bestGuide = PDFTextSnapGuide(orientation: .horizontal, frame: CGRect(x: 0, y: guideY, width: bounds.width, height: 1))
        }

        considerVertical(snapped.minX, target: 0, originX: 0, guideX: 0)
        considerVertical(snapped.midX, target: bounds.midX, originX: bounds.midX - snapped.width / 2, guideX: bounds.midX)
        considerVertical(snapped.maxX, target: bounds.maxX, originX: bounds.maxX - snapped.width, guideX: bounds.maxX)

        for targetFrame in additionalTargets {
            considerVertical(snapped.minX, target: targetFrame.minX, originX: targetFrame.minX, guideX: targetFrame.minX)
            considerVertical(snapped.midX, target: targetFrame.minX, originX: targetFrame.minX - snapped.width / 2, guideX: targetFrame.minX)
            considerVertical(snapped.maxX, target: targetFrame.minX, originX: targetFrame.minX - snapped.width, guideX: targetFrame.minX)

            considerVertical(snapped.minX, target: targetFrame.midX, originX: targetFrame.midX, guideX: targetFrame.midX)
            considerVertical(snapped.midX, target: targetFrame.midX, originX: targetFrame.midX - snapped.width / 2, guideX: targetFrame.midX)
            considerVertical(snapped.maxX, target: targetFrame.midX, originX: targetFrame.midX - snapped.width, guideX: targetFrame.midX)

            considerVertical(snapped.minX, target: targetFrame.maxX, originX: targetFrame.maxX, guideX: targetFrame.maxX)
            considerVertical(snapped.midX, target: targetFrame.maxX, originX: targetFrame.maxX - snapped.width / 2, guideX: targetFrame.maxX)
            considerVertical(snapped.maxX, target: targetFrame.maxX, originX: targetFrame.maxX - snapped.width, guideX: targetFrame.maxX)
        }

        considerHorizontal(snapped.minY, target: 0, originY: 0, guideY: 0)
        considerHorizontal(snapped.midY, target: bounds.midY, originY: bounds.midY - snapped.height / 2, guideY: bounds.midY)
        considerHorizontal(snapped.maxY, target: bounds.maxY, originY: bounds.maxY - snapped.height, guideY: bounds.maxY)

        for targetFrame in additionalTargets {
            considerHorizontal(snapped.minY, target: targetFrame.minY, originY: targetFrame.minY, guideY: targetFrame.minY)
            considerHorizontal(snapped.midY, target: targetFrame.minY, originY: targetFrame.minY - snapped.height / 2, guideY: targetFrame.minY)
            considerHorizontal(snapped.maxY, target: targetFrame.minY, originY: targetFrame.minY - snapped.height, guideY: targetFrame.minY)

            considerHorizontal(snapped.minY, target: targetFrame.midY, originY: targetFrame.midY, guideY: targetFrame.midY)
            considerHorizontal(snapped.midY, target: targetFrame.midY, originY: targetFrame.midY - snapped.height / 2, guideY: targetFrame.midY)
            considerHorizontal(snapped.maxY, target: targetFrame.midY, originY: targetFrame.midY - snapped.height, guideY: targetFrame.midY)

            considerHorizontal(snapped.minY, target: targetFrame.maxY, originY: targetFrame.maxY, guideY: targetFrame.maxY)
            considerHorizontal(snapped.midY, target: targetFrame.maxY, originY: targetFrame.maxY - snapped.height / 2, guideY: targetFrame.maxY)
            considerHorizontal(snapped.maxY, target: targetFrame.maxY, originY: targetFrame.maxY - snapped.height, guideY: targetFrame.maxY)
        }

        if let bestGuide {
            guide = bestGuide
        }

        return PDFTextSnapResult(frame: snapped, guide: guide)
    }

    private func adjustFontSize(by delta: Double) {
        var annotation = currentAnnotation
        annotation.fontSize = min(max(annotation.fontSize + delta, 12), 40)
        onAnnotationChanged?(frame, annotation)
    }

    private func toggleFontWeight() {
        var annotation = currentAnnotation
        annotation.fontWeight = annotation.fontWeight == "bold" ? "regular" : "bold"
        onAnnotationChanged?(frame, annotation)
    }

    private func toggleFontStyle() {
        var annotation = currentAnnotation
        annotation.fontStyle = annotation.fontStyle == "italic" ? "normal" : "italic"
        onAnnotationChanged?(frame, annotation)
    }

    private func setAlignment(_ alignment: String) {
        var annotation = currentAnnotation
        annotation.textAlignment = alignment
        onAnnotationChanged?(frame, annotation)
    }
}

private final class PDFTextAnnotationAccessoryView: UIView {
    var onDone: (() -> Void)?
    var onFontSizeDecrement: (() -> Void)?
    var onFontSizeIncrement: (() -> Void)?
    var onToggleBold: (() -> Void)?
    var onToggleItalic: (() -> Void)?
    var onAlignment: ((String) -> Void)?

    private let stack = UIStackView()
    private let doneButton = UIButton(type: .system)
    private let smallerButton = UIButton(type: .system)
    private let largerButton = UIButton(type: .system)
    private let boldButton = UIButton(type: .system)
    private let italicButton = UIButton(type: .system)
    private let leftButton = UIButton(type: .system)
    private let centerButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 46)
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.layer.cornerRadius = 16
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -6)
        ])

        configureButton(doneButton, title: "완료", width: 52, emphasized: true)
        doneButton.addTarget(self, action: #selector(handleDone), for: .touchUpInside)

        configureButton(smallerButton, title: "A-", width: 32)
        smallerButton.addTarget(self, action: #selector(handleSmaller), for: .touchUpInside)

        configureButton(largerButton, title: "A+", width: 32)
        largerButton.addTarget(self, action: #selector(handleLarger), for: .touchUpInside)

        configureButton(boldButton, title: "B", width: 30)
        boldButton.addTarget(self, action: #selector(handleBold), for: .touchUpInside)

        configureButton(italicButton, title: "I", width: 30)
        italicButton.addTarget(self, action: #selector(handleItalic), for: .touchUpInside)

        configureButton(leftButton, image: "text.alignleft", width: 30)
        leftButton.addTarget(self, action: #selector(handleLeft), for: .touchUpInside)

        configureButton(centerButton, image: "text.aligncenter", width: 30)
        centerButton.addTarget(self, action: #selector(handleCenter), for: .touchUpInside)

        configureButton(rightButton, image: "text.alignright", width: 30)
        rightButton.addTarget(self, action: #selector(handleRight), for: .touchUpInside)

        [doneButton, smallerButton, largerButton, boldButton, italicButton, leftButton, centerButton, rightButton].forEach {
            stack.addArrangedSubview($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(annotation: PDFTextAnnotation) {
        boldButton.backgroundColor = annotation.fontWeight == "bold" ? UIColor.systemBlue.withAlphaComponent(0.18) : UIColor.clear
        italicButton.backgroundColor = annotation.fontStyle == "italic" ? UIColor.systemBlue.withAlphaComponent(0.18) : UIColor.clear
        [leftButton, centerButton, rightButton].forEach { $0.backgroundColor = UIColor.clear }
        switch annotation.textAlignment {
        case "center":
            centerButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        case "right":
            rightButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        default:
            leftButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        }
    }

    private func configureButton(_ button: UIButton, title: String? = nil, image: String? = nil, width: CGFloat, emphasized: Bool = false) {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = emphasized ? UIColor.systemBlue.withAlphaComponent(0.16) : UIColor.systemBackground.withAlphaComponent(0.72)
        configuration.baseForegroundColor = emphasized ? UIColor.systemBlue : .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        button.configuration = configuration
        if let title {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        }
        if let image {
            button.setImage(UIImage(systemName: image), for: .normal)
        }
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @objc private func handleDone() { onDone?() }
    @objc private func handleSmaller() { onFontSizeDecrement?() }
    @objc private func handleLarger() { onFontSizeIncrement?() }
    @objc private func handleBold() { onToggleBold?() }
    @objc private func handleItalic() { onToggleItalic?() }
    @objc private func handleLeft() { onAlignment?("left") }
    @objc private func handleCenter() { onAlignment?("center") }
    @objc private func handleRight() { onAlignment?("right") }
}

private final class PDFTextAnnotationToolbarView: UIVisualEffectView {
    var onFontSize: ((Double) -> Void)?
    var onFontWeightToggle: (() -> Void)?
    var onItalicToggle: (() -> Void)?
    var onFontFamily: ((String?) -> Void)?
    var onAlignment: ((String) -> Void)?
    var onColor: ((String) -> Void)?
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?

    private let stack = UIStackView()
    private let sizeButton = UIButton(type: .system)
    private let colorButton = UIButton(type: .system)
    private let boldButton = UIButton(type: .system)
    private let italicButton = UIButton(type: .system)
    private let alignmentLeft = UIButton(type: .system)
    private let alignmentCenter = UIButton(type: .system)
    private let alignmentRight = UIButton(type: .system)
    private let duplicateButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    init() {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        clipsToBounds = true

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])

        configureButton(sizeButton, width: 44)
        sizeButton.setTitle("Aa", for: .normal)
        sizeButton.menu = fontSizeMenu()
        sizeButton.showsMenuAsPrimaryAction = true

        configureButton(colorButton, width: 36)
        colorButton.menu = colorMenu()
        colorButton.showsMenuAsPrimaryAction = true

        configureButton(boldButton, width: 36)
        boldButton.setImage(UIImage(systemName: "bold"), for: .normal)
        boldButton.addTarget(self, action: #selector(toggleBold), for: .touchUpInside)

        configureButton(italicButton, width: 36)
        italicButton.setImage(UIImage(systemName: "italic"), for: .normal)
        italicButton.addTarget(self, action: #selector(toggleItalic), for: .touchUpInside)

        configureButton(alignmentLeft, width: 32)
        alignmentLeft.setImage(UIImage(systemName: "text.alignleft"), for: .normal)
        alignmentLeft.addTarget(self, action: #selector(setAlignmentLeft), for: .touchUpInside)

        configureButton(alignmentCenter, width: 32)
        alignmentCenter.setImage(UIImage(systemName: "text.aligncenter"), for: .normal)
        alignmentCenter.addTarget(self, action: #selector(setAlignmentCenter), for: .touchUpInside)

        configureButton(alignmentRight, width: 32)
        alignmentRight.setImage(UIImage(systemName: "text.alignright"), for: .normal)
        alignmentRight.addTarget(self, action: #selector(setAlignmentRight), for: .touchUpInside)

        configureButton(duplicateButton, width: 36)
        duplicateButton.setImage(UIImage(systemName: "plus.square.on.square"), for: .normal)
        duplicateButton.addTarget(self, action: #selector(duplicateAnnotation), for: .touchUpInside)

        configureButton(deleteButton, width: 36)
        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteAnnotation), for: .touchUpInside)

        [sizeButton, colorButton, boldButton, italicButton, alignmentLeft, alignmentCenter, alignmentRight, duplicateButton, deleteButton].forEach {
            stack.addArrangedSubview($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: min(size.width, 420), height: 40)
    }

    func update(annotation: PDFTextAnnotation) {
        sizeButton.setTitle("\(Int(annotation.fontSize))", for: .normal)
        colorButton.backgroundColor = UIColor(Color(hex: annotation.textColor) ?? .black)
        boldButton.backgroundColor = annotation.fontWeight == "bold" ? UIColor.systemBlue.withAlphaComponent(0.18) : UIColor.clear
        italicButton.backgroundColor = annotation.fontStyle == "italic" ? UIColor.systemBlue.withAlphaComponent(0.18) : UIColor.clear
        [alignmentLeft, alignmentCenter, alignmentRight].forEach { $0.backgroundColor = UIColor.clear }
        switch annotation.textAlignment {
        case "center":
            alignmentCenter.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        case "right":
            alignmentRight.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        default:
            alignmentLeft.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        }
    }

    private func configureButton(_ button: UIButton, width: CGFloat) {
        button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.72)
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.withAlphaComponent(0.18).cgColor
        button.tintColor = .label
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func fontSizeMenu() -> UIMenu {
        let sizes: [Double] = [12, 14, 16, 18, 20, 24, 28, 32, 36, 40]
        return UIMenu(title: "", children: sizes.map { size in
            UIAction(title: "\(Int(size))") { [weak self] _ in self?.onFontSize?(size) }
        })
    }

    private func colorMenu() -> UIMenu {
        let options: [(String, String)] = [
            ("검정", "#111111"),
            ("파랑", "#2F6BFF"),
            ("초록", "#22A06B"),
            ("주황", "#D9832E"),
            ("빨강", "#D94B4B")
        ]
        return UIMenu(title: "", children: options.map { label, hex in
            UIAction(title: label) { [weak self] _ in self?.onColor?(hex) }
        })
    }

    @objc private func toggleBold() { onFontWeightToggle?() }
    @objc private func toggleItalic() { onItalicToggle?() }
    @objc private func setAlignmentLeft() { onAlignment?("left") }
    @objc private func setAlignmentCenter() { onAlignment?("center") }
    @objc private func setAlignmentRight() { onAlignment?("right") }
    @objc private func duplicateAnnotation() { onDuplicate?() }
    @objc private func deleteAnnotation() { onDelete?() }
}
