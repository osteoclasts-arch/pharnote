import PDFKit
import PencilKit
import SwiftUI
import UIKit

struct PDFKitView: UIViewRepresentable {
    @ObservedObject var viewModel: PDFEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
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
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.stopObservingPageChanges()
        uiView.delegate = nil
        uiView.pageOverlayViewProvider = nil
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider, PKCanvasViewDelegate, PDFViewDelegate {
        private let viewModel: PDFEditorViewModel
        private var pageChangeObserver: NSObjectProtocol?
        private var pageCanvases: [Int: PencilPassthroughCanvasView] = [:]
        private var canvasPageMap: [ObjectIdentifier: Int] = [:]

        init(viewModel: PDFEditorViewModel) {
            self.viewModel = viewModel
        }

        func startObservingPageChanges(of pdfView: PDFView) {
            stopObservingPageChanges()
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
            pageCanvases.removeAll()
            canvasPageMap.removeAll()
            viewModel.setActiveOverlayCanvas(nil)
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let document = view.document else { return nil }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return nil }

            if let existingCanvas = pageCanvases[pageIndex] {
                configureCanvas(existingCanvas)
                return existingCanvas
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

            pageCanvases[pageIndex] = canvas
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

            return canvas
        }

        func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
            guard let canvas = overlayView as? PencilPassthroughCanvasView else { return }
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
            canvas.isUserInteractionEnabled = !viewModel.isReadOnlyMode
            canvas.allowsFingerTouchInput = viewModel.allowsFingerDrawing()
            canvas.drawingPolicy = viewModel.currentDrawingPolicy()
            canvas.tool = viewModel.currentTool()
        }

        private func setActiveOverlayCanvas(_ canvas: PencilPassthroughCanvasView?) {
            viewModel.setActiveOverlayCanvas(canvas)
            canvas?.becomeFirstResponder()
        }

        private func conflictingPDFGestures(in pdfView: PDFView) -> [UIGestureRecognizer] {
            allDescendantGestureRecognizers(in: pdfView).filter { gesture in
                guard gesture.view?.isDescendant(of: pdfView) == true else {
                    return false
                }

                return gesture is UIPanGestureRecognizer || gesture is UIPinchGestureRecognizer
            }
        }

        private func allDescendantGestureRecognizers(in rootView: UIView) -> [UIGestureRecognizer] {
            var gestures = rootView.gestureRecognizers ?? []

            rootView.subviews.forEach { subview in
                gestures.append(contentsOf: allDescendantGestureRecognizers(in: subview))
            }

            return gestures
        }
    }
}
