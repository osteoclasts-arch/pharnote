import Foundation
import PDFKit
import UIKit

actor PDFThumbnailGenerator {
    func generateThumbnailData(pdfURL: URL, targetSize: CGSize) -> [Int: Data] {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            return [:]
        }

        var result: [Int: Data] = [:]
        let pageCount = pdfDocument.pageCount

        for index in 0..<pageCount {
            guard let page = pdfDocument.page(at: index) else { continue }
            let image = page.thumbnail(of: targetSize, for: .mediaBox)
            if let jpegData = image.jpegData(compressionQuality: 0.75) {
                result[index] = jpegData
            }
        }

        return result
    }
}
