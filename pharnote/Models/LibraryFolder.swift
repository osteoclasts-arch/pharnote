import Foundation

enum LibraryFolder: CaseIterable, Identifiable {
    case all
    case blankNotes
    case pdfs

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "홈"
        case .blankNotes:
            return "노트"
        case .pdfs:
            return "PDF"
        }
    }

    var subtitle: String {
        switch self {
        case .all:
            return "오늘 이어서 공부할 자료"
        case .blankNotes:
            return "직접 쓰는 개념 정리 노트"
        case .pdfs:
            return "문제집과 교재 PDF"
        }
    }

    var detailTitle: String {
        switch self {
        case .all:
            return "Study Home"
        case .blankNotes:
            return "Notes"
        case .pdfs:
            return "PDF Workspace"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "sparkles.rectangle.stack"
        case .blankNotes:
            return "square.and.pencil"
        case .pdfs:
            return "doc.richtext"
        }
    }
}

struct UserLibraryFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var accentHex: UInt

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        accentHex: UInt = 0xF1E1D0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.accentHex = accentHex
    }
}
