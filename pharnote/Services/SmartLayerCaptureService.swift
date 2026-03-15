import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation

/// [Service: SmartLayerCaptureService]
/// 인강 플레이어의 현재 프레임에서 강사를 지우고 판서 내용만 추출하여 투명 레이어로 만드는 서비스입니다.
/// 모든 처리는 Latency Zero와 비용 방어를 위해 100% On-Device로 수행됩니다.
@MainActor
final class SmartLayerCaptureService {
    static let shared = SmartLayerCaptureService()
    
    private let context = CIContext()
    
    /// [Temporal Caching] 칠판의 폐쇄(Occlusion) 영역 복원을 위한 프레임 버퍼 (최근 5초/10프레임 내외)
    private var frameBuffer: [Double: CIImage] = [:]
    private let maxBufferSize = 10
    
    private init() {}
    
    /// AVPlayer의 현재 시점을 캡처하고 고도화된 Vision Pipeline을 거쳐 '순수 판서 레이어'를 반환합니다.
    func captureAndCleanBoard(from player: AVPlayer) async throws -> UIImage {
        guard let asset = player.currentItem?.asset else {
            throw SmartLayerError.noAsset
        }
        
        // 1. 프레임 추출
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let onsetTime = player.currentTime()
        let cgImage = try await imageGenerator.image(at: onsetTime).image
        let ciImage = CIImage(cgImage: cgImage)
        
        // 프레임 버퍼 업데이트 (간단한 구현)
        updateFrameBuffer(ciImage, timestamp: onsetTime.seconds)
        
        // 2. Advanced Vision Pipeline 처리 (Occlusion handling 포함)
        return try await processAdvancedBoardExtraction(from: ciImage, at: onsetTime.seconds)
    }
    
    private func updateFrameBuffer(_ image: CIImage, timestamp: Double) {
        frameBuffer[timestamp] = image
        if frameBuffer.count > maxBufferSize {
            let oldestKey = frameBuffer.keys.min() ?? 0
            frameBuffer.removeValue(forKey: oldestKey)
        }
    }
    
    /// [Advanced Pipeline] 강사 제거, 폐쇄 보간 및 글씨 추출
    private func processAdvancedBoardExtraction(from originalCI: CIImage, at timestamp: Double) async throws -> UIImage {
        // Stage 1: Instructor Masking (강사 실루엣 인식 및 제거)
        let cgImage = context.createCGImage(originalCI, from: originalCI.extent)!
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let maskPixelBuffer = request.results?.first?.pixelBuffer else {
            throw SmartLayerError.segmentationFailed
        }
        
        let originalCI = CIImage(cgImage: cgImage)
        let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        // 마스크 반전 (강사 영역을 투명하게)
        let invertFilter = CIFilter.colorInvert()
        invertFilter.inputImage = maskCI
        guard let invertedMask = invertFilter.outputImage else {
            throw SmartLayerError.filteringFailed
        }
        
        // 강사 제거 및 배경 보간 (Temporal Stitching)
        // 강사가 지워진 빈 공간(Clear 영역)을 과거 프레임 데이터로 채움
        let backgroundCI = findBestBackgroundFrame(excluding: timestamp) ?? CIImage(color: .clear).cropped(to: originalCI.extent)
        
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = originalCI
        blendFilter.maskImage = invertedMask
        blendFilter.backgroundImage = backgroundCI
        
        guard let instructorRemovedImage = blendFilter.outputImage else {
            throw SmartLayerError.filteringFailed
        }
        
        // Stage 2: Adaptive Binarization (칠판 배경 날리고 글씨만 부각)
        let finalCI = applyAdaptiveBinarization(to: instructorRemovedImage)
        
        guard let finalCG = context.createCGImage(finalCI, from: finalCI.extent) else {
            throw SmartLayerError.filteringFailed
        }
        
        return UIImage(cgImage: finalCG)
    }
    
    private func findBestBackgroundFrame(excluding currentTimestamp: Double) -> CIImage? {
        // 현재 시점과 가장 가깝지만 다른 프레임을 선택하여 배경(판서) 조각 확보
        // 실제 운영 환경에서는 강사의 위치가 다른 프레임을 찾아 매칭하는 더 복잡한 알고리즘이 필요함
        let keys = frameBuffer.keys.filter { $0 != currentTimestamp }.sorted(by: { abs($0 - currentTimestamp) < abs($1 - currentTimestamp) })
        return keys.first.map { frameBuffer[$0]! }
    }
    
    /// [Adaptive Binarization] 글씨만 남기고 배경 투명화
    private func applyAdaptiveBinarization(to image: CIImage) -> CIImage {
        // 대비 극대화 및 채도 제거
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 3.0
        colorControls.saturation = 0.0
        
        guard let bwImage = colorControls.outputImage else { return image }
        
        // 칠판/백판 배경을 투명하게 (Alpha 0) 처리
        // maskToAlpha는 밝은 영역을 마스크로 쓰므로, 흑판(어두움)일 경우 반전 필요성 검토
        let maskToAlpha = CIFilter.maskToAlpha()
        maskToAlpha.inputImage = bwImage
        
        return maskToAlpha.outputImage ?? bwImage
    }
}

enum SmartLayerError: Error {
    case noAsset
    case segmentationFailed
    case filteringFailed
}
