import PDFKit
import PencilKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    @ObservedObject var viewModel: PDFEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
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
        uiView.pageOverlayViewProvider = nil
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider, PKCanvasViewDelegate {
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
                self?.viewModel.handlePDFPageChanged(sender.currentPage)
                guard let self,
                      let document = sender.document,
                      let currentPage = sender.currentPage else {
                    self?.viewModel.setActiveOverlayCanvas(nil)
                    return
                }
                let pageIndex = document.index(for: currentPage)
                if pageIndex == NSNotFound {
                    self.viewModel.setActiveOverlayCanvas(nil)
                    return
                }
                self.viewModel.setActiveOverlayCanvas(self.pageCanvases[pageIndex])
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
            canvas.delegate = self
            configureCanvas(canvas)

            pageCanvases[pageIndex] = canvas
            canvasPageMap[ObjectIdentifier(canvas)] = pageIndex

            if pageIndex == viewModel.currentPageIndex {
                viewModel.setActiveOverlayCanvas(canvas)
            }

            Task { [weak self, weak canvas] in
                guard let self, let canvas else { return }
                let drawing = await self.viewModel.loadOverlayDrawing(for: pageIndex)
                await MainActor.run {
                    canvas.drawing = drawing
                    if pageIndex == self.viewModel.currentPageIndex {
                        self.viewModel.setActiveOverlayCanvas(canvas)
                    }
                }
            }

            return canvas
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let key = ObjectIdentifier(canvasView)
            guard let pageIndex = canvasPageMap[key] else { return }
            viewModel.overlayDrawingDidChange(pageIndex: pageIndex, drawing: canvasView.drawing)
        }

        func updateCanvasConfigurations() {
            pageCanvases.values.forEach { configureCanvas($0) }
        }

        private func configureCanvas(_ canvas: PencilPassthroughCanvasView) {
            canvas.allowsFingerDrawing = viewModel.allowsFingerDrawing()
            canvas.drawingPolicy = viewModel.currentDrawingPolicy()
            canvas.tool = viewModel.currentTool()
            canvas.becomeFirstResponder()
        }
    }
}
