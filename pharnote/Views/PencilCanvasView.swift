import PencilKit
import SwiftUI

struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var viewModel: BlankNoteEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.contentInset = .zero
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        canvasView.bouncesZoom = false

        context.coordinator.setCanvasView(canvasView)
        viewModel.attachCanvasView(canvasView)

        DispatchQueue.main.async {
            context.coordinator.updateToolPickerVisibility(isVisible: viewModel.isToolPickerVisible)
        }

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.updateToolPickerVisibility(isVisible: viewModel.isToolPickerVisible)
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let viewModel: BlankNoteEditorViewModel
        private weak var canvasView: PKCanvasView?
        private weak var toolPicker: PKToolPicker?
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

            let picker = PKToolPicker.shared(for: window)
            toolPicker = picker

            guard let picker else { return }

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
                canvasView.resignFirstResponder()
            }

            currentPickerVisibility = isVisible
        }

        func cleanup() {
            guard let canvasView, let toolPicker else { return }
            toolPicker.setVisible(false, forFirstResponder: canvasView)
            toolPicker.removeObserver(canvasView)
        }
    }
}
