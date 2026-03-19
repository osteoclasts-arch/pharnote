import PencilKit
import SwiftUI

struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var viewModel: BlankNoteEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PencilPassthroughCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.contentInset = .zero
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        canvasView.zoomScale = 1.0
        canvasView.bouncesZoom = false
        canvasView.pinchGestureRecognizer?.isEnabled = false
        canvasView.allowsFingerTouchInput = viewModel.allowsFingerDrawing
        canvasView.refreshDrawingInputState(isEnabled: viewModel.isCanvasInputEnabled)
        canvasView.onSmartShapeApplied = { [weak viewModel] _ in
            viewModel?.canvasDidChange()
        }
        canvasView.onInteractionDidEnd = { [weak viewModel] _ in
            viewModel?.refreshCanvasInteractionState()
        }
        canvasView.onCanvasTapped = { [weak viewModel] point in
            viewModel?.handleCanvasTap(at: point)
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
            
            // 1. Tool 설정 (불필요한 인스턴스 생성이 루프를 유발할 수 있으므로 가볍게 가드)
            let newTool = viewModel.currentTool()
            // PKTool은 직접 비교가 어려우므로 일단 설정하되, 다른 상태 변화와 겹치지 않게 주의
            canvasView.tool = newTool
            
            // 2. Policy 및 interaction 제어 (상태가 다를 때만 설정)
            let newPolicy = viewModel.currentDrawingPolicy()
            if canvasView.drawingPolicy != newPolicy {
                canvasView.drawingPolicy = newPolicy
            }
            
            let interactionEnabled = viewModel.isCanvasInputEnabled
            if let passthroughCanvas = canvasView as? PencilPassthroughCanvasView {
                passthroughCanvas.allowsFingerTouchInput = viewModel.allowsFingerDrawing
                passthroughCanvas.refreshDrawingInputState(isEnabled: interactionEnabled)
            } else if canvasView.isUserInteractionEnabled != interactionEnabled {
                canvasView.isUserInteractionEnabled = interactionEnabled
            }
            
            if #available(iOS 18.0, *) {
                if canvasView.isDrawingEnabled != interactionEnabled {
                    canvasView.isDrawingEnabled = interactionEnabled
                }
                
                // PKToolPickerItem도 변경시에만 업데이트
                let newItem = pickerItem(for: newTool)
                if toolPicker.selectedToolItem != newItem {
                    toolPicker.selectedToolItem = newItem
                }
            }
            
            // 3. Picker 가시성 업데이트
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
                if #available(iOS 16.4, *) {
                    return PKToolPickerEraserItem(type: eraserTool.eraserType, width: eraserTool.width)
                }
                return PKToolPickerEraserItem(type: eraserTool.eraserType)
            }

            if tool is PKLassoTool {
                return PKToolPickerLassoItem()
            }

            return toolPicker.selectedToolItem
        }

        func updateToolPickerVisibility(isVisible: Bool) {
            guard let canvasView else { return }
            
            // 현재 상태와 동일하면 아무것도 하지 않음 (루프 방지의 핵심)
            if isVisible == currentPickerVisibility && isVisible == toolPicker.isVisible {
                // 이미 보이는데 FirstResponder가 아니라면 그때만 다시 설정
                if isVisible && !canvasView.isFirstResponder {
                    canvasView.becomeFirstResponder()
                }
                return
            }
            
            guard canvasView.window != nil else {
                guard windowLookupRetryCount < 3 else { return }
                windowLookupRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.updateToolPickerVisibility(isVisible: isVisible)
                }
                return
            }
            windowLookupRetryCount = 0

            if isVisible {
                if !currentPickerVisibility {
                    toolPicker.addObserver(canvasView)
                }
                toolPicker.setVisible(true, forFirstResponder: canvasView)
                if !canvasView.isFirstResponder {
                    canvasView.becomeFirstResponder()
                }
            } else {
                if currentPickerVisibility {
                    toolPicker.removeObserver(canvasView)
                }
                toolPicker.setVisible(false, forFirstResponder: canvasView)
                // 포커스 해제는 신중하게 (루프 유발 가능성 낮음)
                if canvasView.isFirstResponder {
                    canvasView.resignFirstResponder()
                }
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
