import PencilKit
import SwiftUI

struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var viewModel: BlankNoteEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = SmartShapeCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.contentInset = .zero
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 4.0
        canvasView.zoomScale = 1.0
        canvasView.bouncesZoom = true
        canvasView.onSmartShapeApplied = { [weak viewModel] _ in
            viewModel?.canvasDidChange()
        }
        canvasView.onInteractionDidEnd = { [weak viewModel] _ in
            viewModel?.refreshCanvasInteractionState()
        }

        context.coordinator.setCanvasView(canvasView)
        viewModel.attachCanvasView(canvasView)

        DispatchQueue.main.async {
            context.coordinator.updateCanvasState()
        }

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.updateCanvasState()
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let viewModel: BlankNoteEditorViewModel
        private weak var canvasView: PKCanvasView?
        private let toolPicker = PKToolPicker()
        private var currentPickerVisibility: Bool = false
        private var windowLookupRetryCount: Int = 0

        init(viewModel: BlankNoteEditorViewModel) {
            self.viewModel = viewModel
        }

        func setCanvasView(_ canvasView: PKCanvasView) {
            self.canvasView = canvasView
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            viewModel.canvasDidChange()
        }

        func updateCanvasState() {
            guard let canvasView else { return }
            canvasView.tool = viewModel.currentTool()
            canvasView.drawingPolicy = viewModel.currentDrawingPolicy()
            if #available(iOS 18.0, *) {
                toolPicker.selectedToolItem = pickerItem(for: viewModel.currentTool())
            }
            updateToolPickerVisibility(isVisible: viewModel.isToolPickerVisible)
        }

        @available(iOS 18.0, *)
        private func pickerItem(for tool: PKTool) -> PKToolPickerItem {
            if let inkingTool = tool as? PKInkingTool {
                return PKToolPickerInkingItem(
                    type: inkingTool.inkType,
                    color: inkingTool.color,
                    width: inkingTool.width
                )
            }

            if let eraserTool = tool as? PKEraserTool {
                return PKToolPickerEraserItem(type: eraserTool.eraserType)
            }

            if tool is PKLassoTool {
                return PKToolPickerLassoItem()
            }

            return toolPicker.selectedToolItem
        }

        func updateToolPickerVisibility(isVisible: Bool) {
            guard let canvasView else { return }
            guard let window = canvasView.window else {
                guard windowLookupRetryCount < 3 else { return }
                windowLookupRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.updateToolPickerVisibility(isVisible: isVisible)
                }
                return
            }
            windowLookupRetryCount = 0

            _ = window
            let picker = toolPicker

            if isVisible {
                if !currentPickerVisibility {
                    picker.addObserver(canvasView)
                }
                picker.setVisible(true, forFirstResponder: canvasView)
                canvasView.becomeFirstResponder()
            } else {
                if currentPickerVisibility {
                    picker.removeObserver(canvasView)
                }
                picker.setVisible(false, forFirstResponder: canvasView)
            }

            currentPickerVisibility = isVisible
        }

        func cleanup() {
            guard let canvasView else { return }
            toolPicker.setVisible(false, forFirstResponder: canvasView)
            toolPicker.removeObserver(canvasView)
        }
    }
}
