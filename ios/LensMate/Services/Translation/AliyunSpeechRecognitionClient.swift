import Foundation

protocol TranslationSpeechRecognizing {
    func recognize(_ audio: RecordedTranslationSpeech, language: TranslationLanguage,
                   credentials: TranslationCredentials) async throws -> String
}

/// One finished utterance per request. No live upload, assistant context or public audio URL.
struct AliyunSpeechRecognitionClient: TranslationSpeechRecognizing {
    static let model = "qwen3-asr-flash"
    static let maximumBase64Bytes = 10_000_000
    static let timeout: TimeInterval = 90
    private let transport: any TranslationTransport

    init(transport: any TranslationTransport = TranslationURLSessionTransport(timeout: Self.timeout)) {
        self.transport = transport
    }

    static func makeRequest(_ audio: RecordedTranslationSpeech, language: TranslationLanguage,
                            credentials: TranslationCredentials) throws -> URLRequest {
        try TranslationConfiguration.validateKey(credentials.apiKey)
        guard audio.duration > 0, audio.duration <= TranslationRecordingOptions.durationRange.upperBound,
              audio.wav.count > 44, audio.wav.count <= Self.maximumBase64Bytes / 4 * 3,
              audio.wav.prefix(4) == Data("RIFF".utf8),
              audio.wav.dropFirst(8).prefix(4) == Data("WAVE".utf8) else { throw TranslationError.invalidRecording }
        var request = URLRequest(url: credentials.region.endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": [[
                "type": "input_audio", "input_audio": ["data": "data:audio/wav;base64," + audio.wav.base64EncodedString()]
            ]]]],
            "stream": false,
            "asr_options": ["language": language.recognitionCode, "enable_itn": false]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func recognize(_ audio: RecordedTranslationSpeech, language: TranslationLanguage,
                   credentials: TranslationCredentials) async throws -> String {
        try Task.checkCancellation()
        let request = try Self.makeRequest(audio, language: language, credentials: credentials)
        do {
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw TranslationError.recognitionFailed }
            return try Self.parse(data, status: response.statusCode)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let error = error as? TranslationError { throw error }
            if (error as? URLError)?.code == .timedOut { throw TranslationError.timedOut }
            throw TranslationError.network
        }
    }

    static func parse(_ data: Data, status: Int) throws -> String {
        if status == 404 { throw TranslationError.recognitionUnavailable }
        do { return try AliyunTranslationClient.parse(data, status: status) }
        catch TranslationError.invalidResponse { throw TranslationError.recognitionFailed }
        catch TranslationError.rejected { throw TranslationError.recognitionFailed }
    }
}
