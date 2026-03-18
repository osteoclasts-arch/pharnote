import Foundation

struct AIProcessingError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class PharNodeAIService {
    static let shared = PharNodeAIService()
    
    private let apiKey: String = "" // TODO: User should provide this or manage via Keychain
    private let baseURL = "https://api.openai.com/v1"
    
    private init() {}
    
    func transcribe(audioURL: URL) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIProcessingError(message: "OpenAI API Key가 설정되지 않았습니다.")
        }
        
        let url = URL(string: "\(baseURL)/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let audioData = try Data(contentsOf: audioURL)
        let body = NSMutableData()
        
        // File part
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")
        
        // Model part
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendString("whisper-1\r\n")
        
        // Language part
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.appendString("ko\r\n")
        
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body as Data
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw AIProcessingError(message: "Transcription failed: \(errorMsg)")
        }
        
        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
    }
    
    func summarize(text: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIProcessingError(message: "OpenAI API Key가 설정되지 않았습니다.")
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let prompt = """
        다음은 학생의 학습 음성을 텍스트로 변환한 내용입니다. 
        이를 바탕으로 핵심 내용을 3-5문장 이내로 요약해 주세요. 
        형식은 노션 스타일의 깔끔한 요약본으로 작성 부탁합니다.
        
        내용:
        \(text)
        """
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "너는 에듀테크 서비스의 AI 요약 도우미야. 학생의 발화를 정확하고 구조적으로 요약해줘."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw AIProcessingError(message: "Summarization failed: \(errorMsg)")
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }
}

private struct WhisperResponse: Codable {
    let text: String
}

private struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

extension NSMutableData {
    func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
