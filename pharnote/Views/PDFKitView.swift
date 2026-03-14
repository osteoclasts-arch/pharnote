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
        private var pageCanvases: [Int: PencilPassthroughCanvasView] = [:]
        private var pageContainers: [Int: PDFPageOverlayContainerView] = [:]
        private var canvasPageMap: [ObjectIdentifier: Int] = [:]
        private var managedPDFGestureStates: [ObjectIdentifier: Bool] = [:]

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
            if let observedPDFView {
                restoreManagedPDFGestures(in: observedPDFView)
            }
            observedPDFView = nil
            pageCanvases.removeAll()
            pageContainers.removeAll()
            canvasPageMap.removeAll()
            managedPDFGestureStates.removeAll()
            viewModel.setActiveOverlayCanvas(nil)
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let document = view.document else { return nil }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return nil }

            if let existingContainer = pageContainers[pageIndex] {
                configureCanvas(existingContainer.canvas)
                configureAttachmentContainer(existingContainer, pageIndex: pageIndex)
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
            configureCanvas(canvas)

            let container = PDFPageOverlayContainerView(
                canvas: canvas,
                workspaceController: workspaceController,
                pageKey: pageKey(for: pageIndex),
                onEditAttachment: onEditAttachment
            )
            configureAttachmentContainer(container, pageIndex: pageIndex)

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
            canvas.isUserInteractionEnabled = isInputEnabled
            canvas.allowsFingerTouchInput = viewModel.allowsFingerDrawing()
            canvas.drawingPolicy = viewModel.currentDrawingPolicy()
            canvas.tool = viewModel.currentTool()
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = isInputEnabled
            if isInputEnabled {
                canvas.becomeFirstResponder()
            }
            if #available(iOS 18.0, *) {
                canvas.isDrawingEnabled = isInputEnabled
            }
        }

        private func configureAttachmentContainer(_ container: PDFPageOverlayContainerView, pageIndex: Int) {
            container.updateAttachmentLayer(
                pageKey: pageKey(for: pageIndex),
                allowsInteraction: !viewModel.isCanvasInputEnabled && !viewModel.isReadOnlyMode,
                onEditAttachment: onEditAttachment
            )
        }

        private func setActiveOverlayCanvas(_ canvas: PencilPassthroughCanvasView?) {
            if let canvas {
                configureCanvas(canvas)
            }
            viewModel.setActiveOverlayCanvas(canvas)
            canvas?.becomeFirstResponder()
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
    }
}

private final class PDFPageOverlayContainerView: UIView {
    let canvas: PencilPassthroughCanvasView
    private let attachmentView: DocumentWorkspaceAttachmentCanvasUIView
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachmentView.frame = bounds
        canvas.frame = bounds
        if canvas.contentSize != bounds.size {
            canvas.contentSize = bounds.size
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
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
}
