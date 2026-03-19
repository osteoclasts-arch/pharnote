import Foundation

struct PharDocument: Identifiable, Codable, Hashable {
    enum DocumentType: String, Codable, CaseIterable {
        case blankNote
        case pdf
        case lesson
    }

    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var type: DocumentType
    var path: String
    var studyMaterial: StudyMaterialMetadata?
    var progress: StudyProgressSnapshot?
    var folderID: UUID?

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        type: DocumentType,
        path: String,
        studyMaterial: StudyMaterialMetadata? = nil,
        progress: StudyProgressSnapshot? = nil,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.type = type
        self.path = path
        self.studyMaterial = studyMaterial
        self.progress = progress
        self.folderID = folderID
    }
}

extension PharDocument {
    nonisolated var studySubjectTitle: String? {
        guard let studyMaterial, studyMaterial.subject != .unspecified else { return nil }
        return studyMaterial.subject.title
    }

    nonisolated var studyProviderTitle: String? {
        guard let studyMaterial, studyMaterial.provider != .unspecified else { return nil }
        return studyMaterial.provider.title
    }

    nonisolated var materialSummaryLine: String? {
        guard let studyMaterial else { return nil }
        let parts = [
            studyMaterial.provider == .unspecified ? nil : studyMaterial.provider.title,
            studyMaterial.subject == .unspecified ? nil : studyMaterial.subject.title
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    nonisolated var progressSummaryLine: String? {
        guard let progress else { return nil }
        if let sectionProgressLabel = progress.sectionProgressLabel {
            return "\(sectionProgressLabel) · \(progress.percentComplete)%"
        }
        return "진도 \(progress.currentPage)/\(max(progress.totalPages, 1)) · \(progress.percentComplete)%"
    }

    nonisolated var progressDetailLine: String? {
        progress?.dashboardSubheadline
    }

    nonisolated var analysisSubjectLabel: String? {
        studySubjectTitle
    }
}
