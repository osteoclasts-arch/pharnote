import Foundation

actor PDFOverlayStore {
    private let fileManager = FileManager.default
    private let overlaysDirectoryName = "PDFOverlayDrawings"

    func loadDrawingData(documentURL: URL, pageIndex: Int) -> Data? {
        let fileURL = drawingFileURL(documentURL: documentURL, pageIndex: pageIndex)
        return try? Data(contentsOf: fileURL)
    }

    func saveDrawingData(_ data: Data, documentURL: URL, pageIndex: Int) throws {
        let directoryURL = overlaysDirectoryURL(documentURL: documentURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = drawingFileURL(documentURL: documentURL, pageIndex: pageIndex)
        try data.write(to: fileURL, options: .atomic)
    }

    private func overlaysDirectoryURL(documentURL: URL) -> URL {
        documentURL.appendingPathComponent(overlaysDirectoryName, isDirectory: true)
    }

    private func drawingFileURL(documentURL: URL, pageIndex: Int) -> URL {
        overlaysDirectoryURL(documentURL: documentURL)
            .appendingPathComponent(String(format: "page-%04d.drawing", pageIndex), isDirectory: false)
    }
}
