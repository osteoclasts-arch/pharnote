import SwiftUI

struct DocumentEditorView: View {
    let document: PharDocument

    var body: some View {
        switch document.type {
        case .blankNote:
            BlankNoteEditorView(document: document)
        case .pdf:
            PDFDocumentEditorView(document: document)
        }
    }
}
