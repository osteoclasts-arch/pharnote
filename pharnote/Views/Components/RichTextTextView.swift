import SwiftUI
import UIKit

final class GrowingTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let fittingWidth = bounds.width > 0 ? bounds.width : (window?.windowScene?.screen.bounds.width ?? 320)
        let fittingSize = sizeThatFits(
            CGSize(width: fittingWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(fittingSize.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

struct RichTextTextView: UIViewRepresentable {
    @Binding var element: PharTextElement
    var isActive: Bool
    var onActivate: () -> Void
    var onSelectionChange: (NSRange?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            element: $element,
            onActivate: onActivate,
            onSelectionChange: onSelectionChange
        )
    }

    func makeUIView(context: Context) -> GrowingTextView {
        let textView = GrowingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.attributedText = element.attributedString()
        textView.typingAttributes = typingAttributes(for: textView, element: element)
        context.coordinator.syncSelectionState(from: textView)
        return textView
    }

    func updateUIView(_ uiView: GrowingTextView, context: Context) {
        let desiredAttributedText = element.attributedString()
        if !uiView.attributedText.isEqual(desiredAttributedText) {
            let currentSelection = uiView.selectedRange
            uiView.attributedText = desiredAttributedText
            if currentSelection.location <= uiView.attributedText.length {
                let preservedLocation = min(currentSelection.location, uiView.attributedText.length)
                let preservedLength = min(currentSelection.length, uiView.attributedText.length - preservedLocation)
                uiView.selectedRange = NSRange(location: preservedLocation, length: preservedLength)
            }
        }

        if uiView.isFirstResponder != isActive {
            if isActive {
                uiView.becomeFirstResponder()
            } else {
                uiView.resignFirstResponder()
            }
        }

        uiView.typingAttributes = typingAttributes(for: uiView, element: element)

        context.coordinator.element = $element
    }

    private func typingAttributes(for textView: UITextView, element: PharTextElement) -> [NSAttributedString.Key: Any] {
        let sourceText = textView.attributedText ?? element.attributedString()
        guard sourceText.length > 0 else {
            return element.defaultTextAttributes()
        }

        let probeLocation: Int
        if textView.selectedRange.length > 0 {
            probeLocation = min(textView.selectedRange.location, sourceText.length - 1)
        } else {
            probeLocation = min(max(textView.selectedRange.location, 0), sourceText.length - 1)
        }

        return sourceText.attributes(at: probeLocation, effectiveRange: nil)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var element: Binding<PharTextElement>
        let onActivate: () -> Void
        let onSelectionChange: (NSRange?) -> Void

        init(
            element: Binding<PharTextElement>,
            onActivate: @escaping () -> Void,
            onSelectionChange: @escaping (NSRange?) -> Void
        ) {
            self.element = element
            self.onActivate = onActivate
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            onActivate()
            syncSelectionState(from: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            var updatedElement = element.wrappedValue
            updatedElement.storeAttributedString(textView.attributedText ?? NSAttributedString(string: ""))
            element.wrappedValue = updatedElement
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            syncSelectionState(from: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            syncSelectionState(from: textView)
        }

        func syncSelectionState(from textView: UITextView) {
            let range = textView.selectedRange
            onSelectionChange(range.length > 0 ? range : nil)
        }
    }
}
