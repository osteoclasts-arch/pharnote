import Foundation

enum LibraryFolder: String, CaseIterable, Identifiable {
    case all = "전체 문서"
    case blankNotes = "빈 노트"
    case pdfs = "PDF"

    var id: Self { self }
}
