import Foundation

struct StudyMaterialCatalogCount: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
}

struct StudyMaterialCatalogSummary: Hashable {
    let bundledEntryCount: Int
    let importedEntryCount: Int
    let mergedEntryCount: Int
    let lastImportedAt: Date?
    let providerCounts: [StudyMaterialCatalogCount]
    let subjectCounts: [StudyMaterialCatalogCount]

    var hasImportedOverride: Bool {
        importedEntryCount > 0
    }
}

struct StudyMaterialCatalogImportPreview {
    struct InvalidRow: Identifiable, Hashable {
        let id = UUID()
        let lineNumber: Int
        let reason: String
    }

    let sourceFileName: String
    let formatLabel: String
    let bundle: StudyMaterialCatalogBundle
    let newEntryCount: Int
    let replacingEntryCount: Int
    let invalidRows: [InvalidRow]

    var totalValidEntryCount: Int {
        bundle.entries.count
    }
}

final class StudyMaterialCatalogManager {
    enum CatalogError: LocalizedError {
        case invalidCatalogFile
        case emptyCatalog

        var errorDescription: String? {
            switch self {
            case .invalidCatalogFile:
                return "유효한 교재 카탈로그 JSON/CSV가 아닙니다."
            case .emptyCatalog:
                return "비어 있는 교재 카탈로그는 가져올 수 없습니다."
            }
        }
    }

    private let fileManager: FileManager
    private let bundle: Bundle
    private let localCatalogFileName = "StudyMaterialCatalog.override.json"

    init(fileManager: FileManager = .default, bundle: Bundle = .main) {
        self.fileManager = fileManager
        self.bundle = bundle
    }

    func makeStore() -> StudyMaterialCatalogStore {
        StudyMaterialCatalogStore(entries: mergedEntries())
    }

    func summary() -> StudyMaterialCatalogSummary {
        let bundledEntries = bundledCatalog()?.entries ?? StudyMaterialCatalogStore.defaultEntries
        let importedBundle = importedCatalog()
        let merged = mergedEntries()

        let providerCounts = Dictionary(grouping: merged, by: \.provider)
            .map { provider, entries in
                StudyMaterialCatalogCount(id: provider.rawValue, title: provider.title, count: entries.count)
            }
            .sorted { lhs, rhs in
                guard
                    let lhsProvider = StudyMaterialProvider(rawValue: lhs.id),
                    let rhsProvider = StudyMaterialProvider(rawValue: rhs.id)
                else {
                    return lhs.title < rhs.title
                }
                return lhsProvider.displayOrder < rhsProvider.displayOrder
            }

        let subjectCounts = Dictionary(grouping: merged, by: \.subject)
            .map { subject, entries in
                StudyMaterialCatalogCount(id: subject.rawValue, title: subject.title, count: entries.count)
            }
            .sorted { lhs, rhs in
                guard
                    let lhsSubject = StudySubject(rawValue: lhs.id),
                    let rhsSubject = StudySubject(rawValue: rhs.id)
                else {
                    return lhs.title < rhs.title
                }
                return lhsSubject.displayOrder < rhsSubject.displayOrder
            }

        return StudyMaterialCatalogSummary(
            bundledEntryCount: bundledEntries.count,
            importedEntryCount: importedBundle?.entries.count ?? 0,
            mergedEntryCount: merged.count,
            lastImportedAt: importedBundle?.importedAt,
            providerCounts: providerCounts,
            subjectCounts: subjectCounts
        )
    }

    func previewImport(from sourceURL: URL) throws -> StudyMaterialCatalogImportPreview {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL)
        let fileName = sourceURL.lastPathComponent
        let lowercasedExtension = sourceURL.pathExtension.lowercased()

        let bundle: StudyMaterialCatalogBundle
        let invalidRows: [StudyMaterialCatalogImportPreview.InvalidRow]
        let formatLabel: String

        if lowercasedExtension == "csv" {
            let parsed = try parseCSVBundle(from: data)
            bundle = parsed.bundle
            invalidRows = parsed.invalidRows
            formatLabel = "CSV"
        } else {
            guard let decoded = try? JSONDecoder().decode(StudyMaterialCatalogBundle.self, from: data) else {
                throw CatalogError.invalidCatalogFile
            }
            bundle = StudyMaterialCatalogBundle(version: decoded.version, entries: normalizedEntries(decoded.entries))
            invalidRows = []
            formatLabel = "JSON"
        }

        guard !bundle.entries.isEmpty else {
            throw CatalogError.emptyCatalog
        }

        let existingIDs = Set(mergedEntries().map(\.id))
        let newEntryCount = bundle.entries.filter { !existingIDs.contains($0.id) }.count
        let replacingEntryCount = bundle.entries.count - newEntryCount

        return StudyMaterialCatalogImportPreview(
            sourceFileName: fileName,
            formatLabel: formatLabel,
            bundle: bundle,
            newEntryCount: newEntryCount,
            replacingEntryCount: replacingEntryCount,
            invalidRows: invalidRows
        )
    }

    @discardableResult
    func importCatalog(preview: StudyMaterialCatalogImportPreview) throws -> StudyMaterialCatalogSummary {
        let payload = ImportedStudyMaterialCatalog(
            importedAt: Date(),
            bundle: preview.bundle
        )

        try ensureApplicationSupportDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(payload)
        try encoded.write(to: localCatalogURL, options: .atomic)
        return summary()
    }

    func resetImportedCatalog() throws -> StudyMaterialCatalogSummary {
        try ensureApplicationSupportDirectoryExists()
        if fileManager.fileExists(atPath: localCatalogURL.path) {
            try fileManager.removeItem(at: localCatalogURL)
        }
        return summary()
    }

    private func mergedEntries() -> [StudyMaterialCatalogEntry] {
        let bundledEntries = bundledCatalog()?.entries ?? StudyMaterialCatalogStore.defaultEntries
        let importedEntries = importedCatalog()?.entries ?? []

        var mergedByID: [String: StudyMaterialCatalogEntry] = [:]
        bundledEntries.forEach { mergedByID[$0.id] = $0 }
        importedEntries.forEach { mergedByID[$0.id] = $0 }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.provider.displayOrder == rhs.provider.displayOrder {
                if lhs.subject.displayOrder == rhs.subject.displayOrder {
                    return lhs.canonicalTitle.localizedStandardCompare(rhs.canonicalTitle) == .orderedAscending
                }
                return lhs.subject.displayOrder < rhs.subject.displayOrder
            }
            return lhs.provider.displayOrder < rhs.provider.displayOrder
        }
    }

    private func normalizedEntries(_ entries: [StudyMaterialCatalogEntry]) -> [StudyMaterialCatalogEntry] {
        entries
            .map { entry in
                StudyMaterialCatalogEntry(
                    id: entry.id.trimmingCharacters(in: .whitespacesAndNewlines),
                    canonicalTitle: entry.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    provider: entry.provider,
                    subject: entry.subject,
                    aliases: entry.aliases
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
            .filter { !$0.id.isEmpty && !$0.canonicalTitle.isEmpty }
    }

    private func bundledCatalog() -> StudyMaterialCatalogBundle? {
        guard let url = bundle.url(forResource: "StudyMaterialCatalog", withExtension: "json") else {
            return nil
        }
        let data = try? Data(contentsOf: url)
        return data.flatMap { try? JSONDecoder().decode(StudyMaterialCatalogBundle.self, from: $0) }
    }

    private func importedCatalog() -> ImportedStudyMaterialCatalog? {
        guard fileManager.fileExists(atPath: localCatalogURL.path) else { return nil }
        guard let data = try? Data(contentsOf: localCatalogURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ImportedStudyMaterialCatalog.self, from: data)
    }

    private func parseCSVBundle(from data: Data) throws -> (bundle: StudyMaterialCatalogBundle, invalidRows: [StudyMaterialCatalogImportPreview.InvalidRow]) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CatalogError.invalidCatalogFile
        }

        let lines = text
            .components(separatedBy: CharacterSet.newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else {
            throw CatalogError.emptyCatalog
        }

        let rows = lines.map(parseCSVLine)
        let hasHeader = rows.first?.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "id"
        let payloadRows = hasHeader ? Array(rows.dropFirst()) : rows
        let startingLine = hasHeader ? 2 : 1

        var entries: [StudyMaterialCatalogEntry] = []
        var invalidRows: [StudyMaterialCatalogImportPreview.InvalidRow] = []

        for (index, columns) in payloadRows.enumerated() {
            let lineNumber = startingLine + index
            guard columns.count >= 5 else {
                invalidRows.append(.init(lineNumber: lineNumber, reason: "컬럼 수 부족"))
                continue
            }

            let id = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalTitle = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let providerRaw = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let subjectRaw = columns[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let aliases = columns[4]
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !id.isEmpty, !canonicalTitle.isEmpty else {
                invalidRows.append(.init(lineNumber: lineNumber, reason: "id 또는 canonicalTitle 비어 있음"))
                continue
            }

            guard let provider = StudyMaterialProvider(rawValue: providerRaw) else {
                invalidRows.append(.init(lineNumber: lineNumber, reason: "알 수 없는 provider: \(providerRaw)"))
                continue
            }

            guard let subject = StudySubject(rawValue: subjectRaw) else {
                invalidRows.append(.init(lineNumber: lineNumber, reason: "알 수 없는 subject: \(subjectRaw)"))
                continue
            }

            entries.append(
                StudyMaterialCatalogEntry(
                    id: id,
                    canonicalTitle: canonicalTitle,
                    provider: provider,
                    subject: subject,
                    aliases: aliases
                )
            )
        }

        return (
            bundle: StudyMaterialCatalogBundle(version: 1, entries: normalizedEntries(entries)),
            invalidRows: invalidRows
        )
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if insideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if character == ",", !insideQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }

            index += 1
        }

        fields.append(current)
        return fields
    }

    private var applicationSupportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pharnote", isDirectory: true)
    }

    private var localCatalogURL: URL {
        applicationSupportDirectory.appendingPathComponent(localCatalogFileName, isDirectory: false)
    }

    private func ensureApplicationSupportDirectoryExists() throws {
        if !fileManager.fileExists(atPath: applicationSupportDirectory.path) {
            try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        }
    }
}

private struct ImportedStudyMaterialCatalog: Codable {
    var importedAt: Date
    var bundle: StudyMaterialCatalogBundle

    var entries: [StudyMaterialCatalogEntry] {
        bundle.entries
    }
}
