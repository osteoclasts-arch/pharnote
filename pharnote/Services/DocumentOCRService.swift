import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import Foundation
import PDFKit
import PencilKit
import UIKit
import Vision

nonisolated struct OCRCachePayload: Codable, Sendable {
    var documentId: UUID
    var pageKey: String
    var fingerprint: String
    var engineVersion: String
    var generatedAt: Date
    var blocks: [AnalysisTextBlock]
}

private actor OCRCacheStore {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private lazy var cacheDirectoryURL: URL = {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("OCRCache", isDirectory: true)
    }()

    func load(documentId: UUID, pageKey: String, fingerprint: String) throws -> [AnalysisTextBlock]? {
        try prepareDirectoryIfNeeded()
        let fileURL = cacheFileURL(documentId: documentId, pageKey: pageKey)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let payload = try decoder.decode(OCRCachePayload.self, from: data)
        guard payload.fingerprint == fingerprint else { return nil }
        return payload.blocks
    }

    func save(documentId: UUID, pageKey: String, fingerprint: String, engineVersion: String, blocks: [AnalysisTextBlock]) throws {
        try prepareDirectoryIfNeeded()
        let payload = OCRCachePayload(
            documentId: documentId,
            pageKey: pageKey,
            fingerprint: fingerprint,
            engineVersion: engineVersion,
            generatedAt: Date(),
            blocks: blocks
        )
        let data = try encoder.encode(payload)
        try data.write(to: cacheFileURL(documentId: documentId, pageKey: pageKey), options: .atomic)
    }

    private func prepareDirectoryIfNeeded() throws {
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    private func cacheFileURL(documentId: UUID, pageKey: String) -> URL {
        let pageDigest = sha256Hex(pageKey)
        return cacheDirectoryURL.appendingPathComponent("\(documentId.uuidString.lowercased())_\(pageDigest).json", isDirectory: false)
    }

    private func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

actor DocumentOCRService {
    private struct OCRPostProcessingContext {
        var subject: StudySubject
        var provider: StudyMaterialProvider
        var customWords: [String]
        var dominantTokens: Set<String>
    }

    private nonisolated static let neutralContext = OCRPostProcessingContext(
        subject: .unspecified,
        provider: .unspecified,
        customWords: [],
        dominantTokens: []
    )

    private struct OCRLineCandidate {
        var text: String
        var confidence: Float
        var order: Int
    }

    nonisolated static let engineVersion = "vision-ocr-v3-math-aware"

    private let cacheStore: OCRCacheStore
    private let ciContext = CIContext(options: nil)
    private let blankNoteStore: BlankNoteStore
    private let overlayStore: PDFOverlayStore

    init(
        blankNoteStore: BlankNoteStore = BlankNoteStore(),
        overlayStore: PDFOverlayStore = PDFOverlayStore()
    ) {
        self.cacheStore = OCRCacheStore()
        self.blankNoteStore = blankNoteStore
        self.overlayStore = overlayStore
    }

    func recognizeBlankNoteBlocks(source: BlankNoteAnalysisSource) async -> [AnalysisTextBlock] {
        let pageKey = source.pageId.uuidString.lowercased()
        let fingerprint = blankNoteFingerprint(source: source)

        if let cached = try? await cacheStore.load(documentId: source.document.id, pageKey: pageKey, fingerprint: fingerprint) {
            return cached
        }

        guard let drawingImage = renderDrawingImage(
            from: source.drawingData,
            fallbackPreviewData: source.previewImageData,
            canvasSize: CGSize(width: 1600, height: 2200),
            longEdge: 2400
        ) else {
            return []
        }

        let customWords = makeCustomWords(document: source.document, manualTags: source.manualTags)
        let processingContext = makeProcessingContext(document: source.document, customWords: customWords)
        let blocks = recognizeBlocks(
            from: drawingImage,
            kind: "ocr-handwriting",
            pageIndex: source.pageIndex,
            context: processingContext,
            shouldTile: true,
            confidenceFloor: 0.16
        )

        try? await cacheStore.save(
            documentId: source.document.id,
            pageKey: pageKey,
            fingerprint: fingerprint,
            engineVersion: Self.engineVersion,
            blocks: blocks
        )
        return blocks
    }

    func recognizePDFBlocks(source: PDFPageAnalysisSource) async -> [AnalysisTextBlock] {
        let pageKey = "pdf-page-\(source.pageIndex)"
        let fingerprint = pdfFingerprint(source: source)

        if let cached = try? await cacheStore.load(documentId: source.document.id, pageKey: pageKey, fingerprint: fingerprint) {
            return cached
        }

        var blocks: [AnalysisTextBlock] = []
        let customWords = makeCustomWords(document: source.document, manualTags: source.manualTags)
        let processingContext = makeProcessingContext(document: source.document, customWords: customWords)

        let nativePDFTextLength = source.pdfTextBlocks.reduce(into: 0) { partial, block in
            partial += block.text.count
        }

        if nativePDFTextLength < 80,
           let basePageImage = renderPDFPageImage(document: source.document, pageIndex: source.pageIndex, longEdge: 2400) {
            blocks.append(contentsOf: recognizeBlocks(
                from: basePageImage,
                kind: "ocr-scanned-page",
                pageIndex: source.pageIndex,
                context: processingContext,
                shouldTile: true,
                confidenceFloor: 0.22
            ))
        }

        if let overlayImage = renderDrawingImage(
            from: source.drawingData,
            fallbackPreviewData: nil,
            canvasSize: CGSize(width: 1800, height: 2400),
            longEdge: 2200
        ) {
            blocks.append(contentsOf: recognizeBlocks(
                from: overlayImage,
                kind: "ocr-handwriting",
                pageIndex: source.pageIndex,
                context: processingContext,
                shouldTile: true,
                confidenceFloor: 0.16
            ))
        }

        let mergedBlocks = merged(blocks)
        try? await cacheStore.save(
            documentId: source.document.id,
            pageKey: pageKey,
            fingerprint: fingerprint,
            engineVersion: Self.engineVersion,
            blocks: mergedBlocks
        )
        return mergedBlocks
    }

    func recognizePDFSelectionBlocks(
        document: PharDocument,
        pageIndex: Int,
        normalizedRect: CGRect
    ) async -> [AnalysisTextBlock] {
        guard let pageImage = renderPDFPageImage(document: document, pageIndex: pageIndex, longEdge: 2400),
              let cgImage = pageImage.cgImage else {
            return []
        }

        let sanitizedRect = clamp(normalizedRect, to: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard sanitizedRect.width > 0.01, sanitizedRect.height > 0.01 else { return [] }

        let cropRect = CGRect(
            x: sanitizedRect.minX * CGFloat(cgImage.width),
            y: sanitizedRect.minY * CGFloat(cgImage.height),
            width: sanitizedRect.width * CGFloat(cgImage.width),
            height: sanitizedRect.height * CGFloat(cgImage.height)
        )
        .integral

        guard cropRect.width >= 24, cropRect.height >= 24,
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return []
        }

        let context = makeProcessingContext(
            document: document,
            customWords: makeCustomWords(document: document, manualTags: [])
        )
        let uiImage = UIImage(cgImage: croppedImage)
        return recognizeBlocks(
            from: uiImage,
            kind: "ocr-selection",
            pageIndex: pageIndex,
            context: context,
            shouldTile: false,
            confidenceFloor: 0.18
        )
    }

    func recognizePDFSelectionText(
        document: PharDocument,
        pageIndex: Int,
        normalizedRect: CGRect
    ) async -> String? {
        let blocks = await recognizePDFSelectionBlocks(
            document: document,
            pageIndex: pageIndex,
            normalizedRect: normalizedRect
        )
        return joinedText(from: blocks)
    }

    func recognizeIndexedText(document: PharDocument, pageKey: String) async -> String? {
        switch document.type {
        case .blankNote:
            guard let pageID = UUID(uuidString: pageKey) else { return nil }
            let documentURL = URL(fileURLWithPath: document.path, isDirectory: true)
            guard let drawingData = await blankNoteStore.loadDrawingData(documentURL: documentURL, pageID: pageID) else { return nil }
            let source = BlankNoteAnalysisSource(
                document: document,
                pageId: pageID,
                pageIndex: 0,
                pageCount: 1,
                previousPageIds: [],
                nextPageIds: [],
                pageState: [],
                previewImageData: nil,
                drawingData: drawingData,
                drawingStats: AnalysisDrawingStats(strokeCount: 0, inkLengthEstimate: 0, eraseRatio: 0, highlightCoverage: 0),
                manualTags: [],
                bookmarks: [],
                sessionId: UUID(),
                dwellMs: 0,
                foregroundEditsMs: 0,
                revisitCount: 0,
                toolUsage: [],
                lassoActions: 0,
                copyActions: 0,
                pasteActions: 0,
                undoCount: 0,
                redoCount: 0,
                navigationPath: [],
                postSolveReview: nil
            )
            let blocks = await recognizeBlankNoteBlocks(source: source)
            return joinedText(from: blocks)
        case .pdf:
            guard let pageIndex = Self.pdfPageIndex(from: pageKey) else { return nil }
            let documentURL = URL(fileURLWithPath: document.path, isDirectory: true)
            let drawingData = await overlayStore.loadDrawingData(documentURL: documentURL, pageIndex: pageIndex)
            let source = PDFPageAnalysisSource(
                document: document,
                pageId: UUID.stableAnalysisPageID(namespace: document.id, pageIndex: pageIndex),
                pageIndex: pageIndex,
                pageCount: 1,
                previousPageIds: [],
                nextPageIds: [],
                pageState: [],
                previewImageData: nil,
                drawingData: drawingData,
                drawingStats: AnalysisDrawingStats(strokeCount: 0, inkLengthEstimate: 0, eraseRatio: 0, highlightCoverage: 0),
                pdfTextBlocks: [],
                manualTags: [],
                bookmarks: [],
                sessionId: UUID(),
                dwellMs: 0,
                foregroundEditsMs: 0,
                revisitCount: 0,
                toolUsage: [],
                lassoActions: 0,
                copyActions: 0,
                pasteActions: 0,
                undoCount: 0,
                redoCount: 0,
                zoomEventCount: 0,
                navigationPath: [],
                sourceFingerprint: document.title,
                postSolveReview: nil
            )
            let blocks = await recognizePDFBlocks(source: source)
            return joinedText(from: blocks)
        case .lesson:
            // For now, treat lesson documents like blank notes for indexing purposes
            guard let pageID = UUID(uuidString: pageKey) else { return nil }
            let documentURL = URL(fileURLWithPath: document.path, isDirectory: true)
            guard let drawingData = await blankNoteStore.loadDrawingData(documentURL: documentURL, pageID: pageID) else { return nil }
            let source = BlankNoteAnalysisSource(
                document: document,
                pageId: pageID,
                pageIndex: 0,
                pageCount: 1,
                previousPageIds: [],
                nextPageIds: [],
                pageState: [],
                previewImageData: nil,
                drawingData: drawingData,
                drawingStats: AnalysisDrawingStats(strokeCount: 0, inkLengthEstimate: 0, eraseRatio: 0, highlightCoverage: 0),
                manualTags: [],
                bookmarks: [],
                sessionId: UUID(),
                dwellMs: 0,
                foregroundEditsMs: 0,
                revisitCount: 0,
                toolUsage: [],
                lassoActions: 0,
                copyActions: 0,
                pasteActions: 0,
                undoCount: 0,
                redoCount: 0,
                navigationPath: [],
                postSolveReview: nil
            )
            let blocks = await recognizeBlankNoteBlocks(source: source)
            return joinedText(from: blocks)
        }
    }

    private func recognizeBlocks(
        from image: UIImage,
        kind: String,
        pageIndex: Int,
        context: OCRPostProcessingContext,
        shouldTile: Bool,
        confidenceFloor: Float
    ) -> [AnalysisTextBlock] {
        guard let cgImage = image.cgImage else { return [] }

        var lines: [OCRLineCandidate] = []
        var order = 0

        let fullPassImages = [cgImage] + preprocessedVariants(for: cgImage)
        for sourceImage in fullPassImages {
            let recognized = recognizeLines(from: sourceImage, context: context, confidenceFloor: confidenceFloor)
            for line in recognized {
                lines.append(OCRLineCandidate(text: line.text, confidence: line.confidence, order: order))
                order += 1
            }
        }

        if shouldTile {
            for tile in tiledImages(from: cgImage) {
                let recognized = recognizeLines(from: tile, context: context, confidenceFloor: confidenceFloor)
                for line in recognized {
                    lines.append(OCRLineCandidate(text: line.text, confidence: line.confidence, order: order))
                    order += 1
                }
            }
        }

        let mergedLines = merged(lines)
        return chunkedBlocks(from: mergedLines, kind: kind, pageIndex: pageIndex, context: context)
    }

    private func recognizeLines(from image: CGImage, context: OCRPostProcessingContext, confidenceFloor: Float) -> [(text: String, confidence: Float)] {
        let configuredRequest = makeRequest(customWords: context.customWords, aggressive: false)
        let fallbackRequest = makeRequest(customWords: [], aggressive: true)

        if let lines = performRequest(configuredRequest, on: image, context: context, confidenceFloor: confidenceFloor), !lines.isEmpty {
            return lines
        }
        return performRequest(fallbackRequest, on: image, context: context, confidenceFloor: confidenceFloor) ?? []
    }

    private func makeRequest(customWords: [String], aggressive: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = !aggressive
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = aggressive ? 0.004 : 0.008
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.customWords = Array(customWords.prefix(64))
        return request
    }

    private func performRequest(
        _ request: VNRecognizeTextRequest,
        on image: CGImage,
        context: OCRPostProcessingContext,
        confidenceFloor: Float
    ) -> [(text: String, confidence: Float)]? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { observation -> (String, Float)? in
                let candidates = observation.topCandidates(3)
                guard let best = bestCandidate(from: candidates, context: context) else { return nil }
                let text = normalizedOCRText(best.string, context: context)
                guard text.count >= 2 else { return nil }
                let adjustedConfidence = adjustedConfidence(for: text, base: best.confidence, context: context)
                guard adjustedConfidence >= confidenceFloor else { return nil }
                return (text, adjustedConfidence)
            }
            return lines
        } catch {
            return nil
        }
    }

    private func preprocessedVariants(for image: CGImage) -> [CGImage] {
        let ciImage = CIImage(cgImage: image)
        var variants: [CGImage] = []

        let monochrome = CIFilter.colorControls()
        monochrome.inputImage = ciImage
        monochrome.saturation = 0
        monochrome.contrast = 1.35
        monochrome.brightness = 0.02

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = monochrome.outputImage
        sharpen.sharpness = 0.42

        if let output = sharpen.outputImage,
           let cgOutput = ciContext.createCGImage(output, from: output.extent) {
            variants.append(cgOutput)
        }

        let boosted = CIFilter.colorControls()
        boosted.inputImage = ciImage
        boosted.saturation = 0
        boosted.contrast = 1.6
        boosted.brightness = 0.05

        if let output = boosted.outputImage,
           let cgOutput = ciContext.createCGImage(output, from: output.extent) {
            variants.append(cgOutput)
        }

        let threshold = CIFilter.colorClamp()
        threshold.inputImage = boosted.outputImage ?? ciImage
        threshold.minComponents = CIVector(x: 0.18, y: 0.18, z: 0.18, w: 0)
        threshold.maxComponents = CIVector(x: 0.95, y: 0.95, z: 0.95, w: 1)

        if let output = threshold.outputImage,
           let cgOutput = ciContext.createCGImage(output, from: output.extent) {
            variants.append(cgOutput)
        }

        return variants
    }

    private func tiledImages(from image: CGImage) -> [CGImage] {
        let width = image.width
        let height = image.height
        guard width > 1200 || height > 1600 else { return [] }

        let columns = width > 1500 ? 2 : 1
        let rows = min(max(Int(ceil(Double(height) / 1200.0)), 2), 4)
        let overlap = 80
        let tileWidth = max(width / columns, 1)
        let tileHeight = max(height / rows, 1)

        var tiles: [CGImage] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let x = max(column * tileWidth - overlap, 0)
                let y = max(row * tileHeight - overlap, 0)
                let maxWidth = min(tileWidth + overlap * 2, width - x)
                let maxHeight = min(tileHeight + overlap * 2, height - y)
                let rect = CGRect(x: x, y: y, width: maxWidth, height: maxHeight)
                if let tile = image.cropping(to: rect) {
                    tiles.append(tile)
                }
            }
        }
        return tiles
    }

    private func chunkedBlocks(
        from lines: [OCRLineCandidate],
        kind: String,
        pageIndex: Int,
        context: OCRPostProcessingContext
    ) -> [AnalysisTextBlock] {
        var blocks: [AnalysisTextBlock] = []
        var currentLines: [String] = []
        var currentLength = 0

        for line in lines.sorted(by: { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.confidence > rhs.confidence
            }
            return lhs.order < rhs.order
        }) {
            let nextLength = currentLength + line.text.count + (currentLines.isEmpty ? 0 : 1)
            if nextLength > 220 || currentLines.count >= 3 {
                let text = currentLines.joined(separator: "\n")
                if !text.isEmpty {
                    blocks.append(AnalysisTextBlock(kind: kind, text: normalizedOCRText(text, context: context), pageIndex: pageIndex))
                }
                currentLines = [line.text]
                currentLength = line.text.count
            } else {
                currentLines.append(line.text)
                currentLength = nextLength
            }
        }

        if !currentLines.isEmpty {
            blocks.append(AnalysisTextBlock(kind: kind, text: normalizedOCRText(currentLines.joined(separator: "\n"), context: context), pageIndex: pageIndex))
        }

        return Array(blocks.prefix(20))
    }

    private func merged(_ blocks: [AnalysisTextBlock]) -> [AnalysisTextBlock] {
        var seen = Set<String>()
        var merged: [AnalysisTextBlock] = []

        for block in blocks {
            let normalized = normalizedOCRText(block.text, context: Self.neutralContext)
            guard !normalized.isEmpty else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            merged.append(AnalysisTextBlock(kind: block.kind, text: normalized, pageIndex: block.pageIndex))
        }
        return merged
    }

    private func merged(_ lines: [OCRLineCandidate]) -> [OCRLineCandidate] {
        var seen: [String: OCRLineCandidate] = [:]

        for line in lines {
            let normalized = normalizedOCRText(line.text, context: Self.neutralContext)
            guard !normalized.isEmpty else { continue }
            if let existing = seen[normalized] {
                if line.confidence > existing.confidence {
                    seen[normalized] = OCRLineCandidate(text: normalized, confidence: line.confidence, order: existing.order)
                }
            } else {
                seen[normalized] = OCRLineCandidate(text: normalized, confidence: line.confidence, order: line.order)
            }
        }

        return seen.values.sorted { lhs, rhs in lhs.order < rhs.order }
    }

    private func renderDrawingImage(
        from drawingData: Data?,
        fallbackPreviewData: Data?,
        canvasSize: CGSize,
        longEdge: CGFloat
    ) -> UIImage? {
        if let drawingData,
           let drawing = try? PKDrawing(data: drawingData),
           !drawing.strokes.isEmpty {
            var bounds = drawing.bounds
            if bounds.isNull || bounds.isEmpty {
                bounds = CGRect(origin: .zero, size: canvasSize)
            } else {
                bounds = bounds.insetBy(dx: -48, dy: -48)
            }

            let scale = max(longEdge / max(bounds.width, bounds.height), 1.5)
            let inkImage = drawing.image(from: bounds, scale: scale)
            let size = inkImage.size
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                inkImage.draw(in: CGRect(origin: .zero, size: size))
            }
        }

        guard let fallbackPreviewData, let image = UIImage(data: fallbackPreviewData) else { return nil }
        return image
    }

    private func renderPDFPageImage(document: PharDocument, pageIndex: Int, longEdge: CGFloat) -> UIImage? {
        guard let pdfURL = resolvePDFURL(for: document),
              let pdfDocument = PDFDocument(url: pdfURL),
              let page = pdfDocument.page(at: pageIndex) else {
            return nil
        }

        let bounds = page.bounds(for: .mediaBox)
        let scale = max(longEdge / max(bounds.width, bounds.height), 1.0)
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: targetSize.height)
            cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cgContext)
            cgContext.restoreGState()
        }
    }

    private func resolvePDFURL(for document: PharDocument) -> URL? {
        let packageURL = URL(fileURLWithPath: document.path, isDirectory: true)
        let preferredURL = packageURL.appendingPathComponent("Original.pdf", isDirectory: false)
        if FileManager.default.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let files = try? FileManager.default.contentsOfDirectory(at: packageURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return files?.first(where: { $0.pathExtension.lowercased() == "pdf" })
    }

    private func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let originX = min(max(rect.origin.x, bounds.minX), bounds.maxX)
        let originY = min(max(rect.origin.y, bounds.minY), bounds.maxY)
        let maxX = min(max(rect.maxX, bounds.minX), bounds.maxX)
        let maxY = min(max(rect.maxY, bounds.minY), bounds.maxY)
        let width = max(maxX - originX, 0)
        let height = max(maxY - originY, 0)
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func blankNoteFingerprint(source: BlankNoteAnalysisSource) -> String {
        sha256Hex(
            [
                Self.engineVersion,
                source.document.id.uuidString,
                source.pageId.uuidString,
                sha256Hex(source.drawingData),
                sha256Hex(source.previewImageData),
                source.document.title,
                source.document.studyMaterial?.canonicalTitle ?? ""
            ].joined(separator: "::")
        )
    }

    private func pdfFingerprint(source: PDFPageAnalysisSource) -> String {
        let pdfText = source.pdfTextBlocks.map(\.text).joined(separator: "\n")
        return sha256Hex(
            [
                Self.engineVersion,
                source.document.id.uuidString,
                String(source.pageIndex),
                source.sourceFingerprint ?? "",
                sha256Hex(Data(pdfText.utf8)),
                sha256Hex(source.drawingData),
                source.document.title,
                source.document.studyMaterial?.canonicalTitle ?? ""
            ].joined(separator: "::")
        )
    }

    private func makeCustomWords(document: PharDocument, manualTags: [String]) -> [String] {
        var words: Set<String> = []

        func insertTokens(from raw: String?) {
            guard let raw else { return }
            let tokens = raw
                .replacingOccurrences(of: #"[\[\]\(\),.:;_\-]"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 2 }
            for token in tokens {
                words.insert(token)
            }
            words.insert(raw)
        }

        insertTokens(from: document.title)
        insertTokens(from: document.studyMaterial?.canonicalTitle)
        insertTokens(from: document.studyProviderTitle)
        insertTokens(from: document.studySubjectTitle)
        manualTags.forEach { insertTokens(from: $0) }
        (document.progress?.sections ?? []).forEach { insertTokens(from: $0.title) }

        switch document.studyMaterial?.subject {
        case .math:
            ["미적분", "확률", "통계", "기하", "함수", "극한", "미분", "적분", "수열", "sin", "cos", "tan", "log", "ln", "lim", "dx", "dy"].forEach { words.insert($0) }
        case .physics:
            ["역학", "전자기", "파동", "열역학", "전기장", "자기장"].forEach { words.insert($0) }
        case .chemistry:
            ["화학", "반응", "평형", "산화", "환원", "몰농도"].forEach { words.insert($0) }
        case .biology:
            ["생명", "유전", "세포", "대사", "뉴런", "항상성"].forEach { words.insert($0) }
        case .earthScience:
            ["지구과학", "지질", "대기", "천체", "판구조론"].forEach { words.insert($0) }
        case .english:
            ["vocabulary", "grammar", "reading", "listening"].forEach { words.insert($0) }
        case .korean:
            ["문학", "독서", "화법", "작문", "언어", "매체"].forEach { words.insert($0) }
        default:
            break
        }

        return Array(words).sorted { $0.count > $1.count }
    }

    private func joinedText(from blocks: [AnalysisTextBlock]) -> String? {
        let text = blocks.map(\.text).joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private func makeProcessingContext(document: PharDocument, customWords: [String]) -> OCRPostProcessingContext {
        OCRPostProcessingContext(
            subject: document.studyMaterial?.subject ?? .unspecified,
            provider: document.studyMaterial?.provider ?? .unspecified,
            customWords: customWords,
            dominantTokens: Set(customWords.map { $0.lowercased() })
        )
    }

    private func bestCandidate(
        from candidates: [VNRecognizedText],
        context: OCRPostProcessingContext
    ) -> VNRecognizedText? {
        candidates.max { lhs, rhs in
            candidateScore(lhs, context: context) < candidateScore(rhs, context: context)
        }
    }

    private func candidateScore(_ candidate: VNRecognizedText, context: OCRPostProcessingContext) -> Float {
        let normalized = normalizedOCRText(candidate.string, context: context)
        guard !normalized.isEmpty else { return -.greatestFiniteMagnitude }

        var score = candidate.confidence
        let lowercased = normalized.lowercased()

        let dominantHits = context.dominantTokens.reduce(into: 0) { partial, token in
            if token.count >= 2, lowercased.contains(token) {
                partial += 1
            }
        }
        score += Float(min(dominantHits, 4)) * 0.04

        if context.subject == .math || context.subject == .physics || context.subject == .chemistry {
            let mathHits = matchCount(in: lowercased, pattern: #"[0-9][\s]*[x×+\-=/][\s]*[0-9a-z]"#)
            score += Float(min(mathHits, 3)) * 0.05
        }

        if lowercased.contains("?") || lowercased.contains("�") {
            score -= 0.12
        }

        if normalized.count < 2 {
            score -= 0.3
        }

        return score
    }

    private func adjustedConfidence(for text: String, base: Float, context: OCRPostProcessingContext) -> Float {
        var confidence = base
        let lowercased = text.lowercased()

        if context.subject == .math || context.subject == .physics || context.subject == .chemistry {
            if matchCount(in: lowercased, pattern: #"[0-9][\s]*[x×+\-=/][\s]*[0-9a-z]"#) > 0 {
                confidence += 0.05
            }
            if lowercased.contains("lim") || lowercased.contains("log") || lowercased.contains("sin") || lowercased.contains("cos") {
                confidence += 0.04
            }
        }

        if matchCount(in: lowercased, pattern: #"[가-힣]{2,}"#) > 0 {
            confidence += 0.03
        }

        return min(max(confidence, 0), 1)
    }

    private func normalizedOCRText(_ text: String, context: OCRPostProcessingContext) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "∗", with: "*")
            .replacingOccurrences(of: "∙", with: "·")
            .replacingOccurrences(of: "•", with: "·")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "＝", with: "=")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "［", with: "[")
            .replacingOccurrences(of: "］", with: "]")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let subjectNormalized = normalizeSubjectSpecificText(cleaned, context: context)
        return subjectNormalized
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeSubjectSpecificText(_ text: String, context: OCRPostProcessingContext) -> String {
        switch context.subject {
        case .math, .physics, .chemistry:
            return normalizeMathLikeText(text, context: context)
        case .english:
            return normalizeEnglishText(text)
        default:
            return normalizeGeneralText(text, context: context)
        }
    }

    private func normalizeMathLikeText(_ text: String, context: OCRPostProcessingContext) -> String {
        var normalized = normalizeGeneralText(text, context: context)
        normalized = normalized.replacingOccurrences(of: #"\bO(?=[\d\)\]\}])"#, with: "0", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[\(\[\{=+\-*/])O\b"#, with: "0", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[\d\)\]\}])\s*[xX]\s*(?=[\d\(a-zA-Z])"#, with: " × ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[\d])I(?=[\d])"#, with: "1", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[\d])l(?=[\d])"#, with: "1", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[\d])S(?=[\d])"#, with: "5", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[\d])B(?=[\d])"#, with: "8", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[\d])o(?=[\d])"#, with: "0", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[\d])D(?=[\d])"#, with: "0", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[a-zA-Z])0(?=[a-zA-Z])"#, with: "o", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=[a-zA-Z])1(?=[a-zA-Z])"#, with: "l", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?<=\b)rn(?=[a-z])"#, with: "m", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bln\b"#, with: "ln", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\blog\b"#, with: "log", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\blim\b"#, with: "lim", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bsin\b"#, with: "sin", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bcos\b"#, with: "cos", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\btan\b"#, with: "tan", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bsec\b"#, with: "sec", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bcsc\b"#, with: "csc", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bcot\b"#, with: "cot", options: .regularExpression)
        return normalized
    }

    private func normalizeEnglishText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?<=[A-Za-z])0(?=[A-Za-z])"#, with: "o", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[A-Za-z])1(?=[A-Za-z])"#, with: "l", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[A-Za-z])5(?=[A-Za-z])"#, with: "s", options: .regularExpression)
    }

    private func normalizeGeneralText(_ text: String, context: OCRPostProcessingContext) -> String {
        var normalized = text
        for token in context.customWords where token.count >= 3 {
            let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedToken.isEmpty else { continue }
            if levenshteinDistance(normalized.lowercased(), normalizedToken.lowercased()) == 1,
               abs(normalized.count - normalizedToken.count) <= 1 {
                normalized = normalizedToken
                break
            }
        }
        return normalized
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        guard !lhsChars.isEmpty else { return rhsChars.count }
        guard !rhsChars.isEmpty else { return lhsChars.count }

        var distances = Array(0...rhsChars.count)
        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var previous = distances[0]
            distances[0] = lhsIndex + 1

            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let current = distances[rhsIndex + 1]
                if lhsChar == rhsChar {
                    distances[rhsIndex + 1] = previous
                } else {
                    distances[rhsIndex + 1] = min(previous, distances[rhsIndex], current) + 1
                }
                previous = current
            }
        }

        return distances[rhsChars.count]
    }

    private func matchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private func sha256Hex(_ data: Data?) -> String {
        guard let data else { return "none" }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func pdfPageIndex(from pageKey: String) -> Int? {
        guard pageKey.hasPrefix("pdf-page-") else { return nil }
        return Int(pageKey.replacingOccurrences(of: "pdf-page-", with: ""))
    }
}
