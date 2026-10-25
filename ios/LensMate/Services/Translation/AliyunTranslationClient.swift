import Foundation

protocol TextTranslating {
    func translate(_ input: TranslationInput, credentials: TranslationCredentials) async throws -> String
}

protocol TranslationTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Dedicated, memory-only session. Redirects must never forward translation credentials or text.
final class TranslationURLSessionTransport: TranslationTransport {
    final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral, timeout: TimeInterval = 30) {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 5
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

struct AliyunTranslationClient: TextTranslating {
    static let model = "qwen-mt-flash"
    private let transport: any TranslationTransport

    init(transport: any TranslationTransport = TranslationURLSessionTransport()) {
        self.transport = transport
    }

    /// Only the current text and language pair cross this boundary. No assistant state is accepted.
    static func makeRequest(_ input: TranslationInput, credentials: TranslationCredentials) throws -> URLRequest {
        try input.validate()
        try TranslationConfiguration.validateKey(credentials.apiKey)
        var request = URLRequest(url: credentials.region.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            model: model, messages: [.init(role: "user", content: input.text)], stream: false,
            translation_options: .init(source_lang: input.source.apiName, target_lang: input.target.apiName)
        ))
        return request
    }

    func translate(_ input: TranslationInput, credentials: TranslationCredentials) async throws -> String {
        try Task.checkCancellation()
        let request = try Self.makeRequest(input, credentials: credentials)
        do {
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
            return try Self.parse(data, status: response.statusCode)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let error = error as? TranslationError { throw error }
            if (error as? URLError)?.code == .timedOut { throw TranslationError.timedOut }
            // Never expose server bodies, URL descriptions or credentials in UI/logs.
            throw TranslationError.network
        }
    }

    static func parse(_ data: Data, status: Int) throws -> String {
        switch status {
        case 200: break
        case 401, 403: throw TranslationError.authentication
        case 429: throw TranslationError.rateLimited
        case 404: throw TranslationError.modelUnavailable
        case 400, 422: throw TranslationError.rejected
        case 500...599: throw TranslationError.serviceUnavailable
        default: throw TranslationError.invalidResponse
        }
        guard data.count <= 256_000,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.choices.count == 1, let choice = response.choices.first else {
            throw TranslationError.invalidResponse
        }
        if choice.finish_reason == "length" { throw TranslationError.incompleteResponse }
        guard choice.finish_reason == "stop", choice.message.refusal == nil,
              let text = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw TranslationError.invalidResponse }
        return text
    }

    private struct Body: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        struct Options: Encodable { let source_lang: String; let target_lang: String }
        let model: String
        let messages: [Message]
        let stream: Bool
        let translation_options: Options
    }

    private struct Response: Decodable {
        struct Message: Decodable { let content: String?; let refusal: String? }
        struct Choice: Decodable { let message: Message; let finish_reason: String? }
        let choices: [Choice]
    }
}
