import XCTest
@testable import LensMate

final class TranslationClientTests: XCTestCase {
    private let credentials = TranslationCredentials(region: .singapore, apiKey: "test-key")

    func testSixDirectionsContainOnlyCurrentTextAndLanguageParameters() throws {
        var pairs = Set<String>()
        for source in TranslationLanguage.allCases {
            for target in TranslationLanguage.allCases where source != target {
                let input = TranslationInput(text: "你好 Hello สวัสดี", source: source, target: target)
                let request = try AliyunTranslationClient.makeRequest(input, credentials: credentials)
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                XCTAssertEqual(Set(body.keys), ["model", "messages", "stream", "translation_options"])
                XCTAssertEqual(body["model"] as? String, "qwen-mt-flash")
                XCTAssertEqual(body["stream"] as? Bool, false)
                let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
                XCTAssertEqual(messages, [["role": "user", "content": input.text]])
                let options = try XCTUnwrap(body["translation_options"] as? [String: String])
                XCTAssertEqual(options, ["source_lang": source.apiName, "target_lang": target.apiName])
                pairs.insert("\(options["source_lang"]!)-\(options["target_lang"]!)")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                XCTAssertEqual(request.timeoutInterval, 30)
            }
        }
        XCTAssertEqual(pairs.count, 6)
    }

    func testRegionUsesFixedOfficialEndpointAndItsOwnCredential() throws {
        for (region, host) in [(TranslationRegion.beijing, "dashscope.aliyuncs.com"), (.singapore, "dashscope-intl.aliyuncs.com")] {
            let request = try AliyunTranslationClient.makeRequest(input(), credentials: .init(region: region, apiKey: region.rawValue))
            XCTAssertEqual(request.url?.absoluteString, "https://\(host)/compatible-mode/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(region.rawValue)")
        }
    }

    func testValidationRejectsEmptyOversizedSameLanguageAndHeaderInjection() throws {
        for (input, expected) in [
            (input(text: " \n"), TranslationError.emptyInput),
            (input(text: String(repeating: "ก", count: 2_001)), .inputTooLong),
            (TranslationInput(text: "Hello", source: .english, target: .english), .sameLanguage)
        ] {
            XCTAssertThrowsError(try AliyunTranslationClient.makeRequest(input, credentials: credentials)) {
                XCTAssertEqual($0 as? TranslationError, expected)
            }
        }
        XCTAssertNoThrow(try input(text: String(repeating: "中", count: 2_000)).validate())
        for key in ["", "key\r\nInjected: true", "has space", "密钥"] {
            XCTAssertThrowsError(try AliyunTranslationClient.makeRequest(input(), credentials: .init(region: .beijing, apiKey: key))) {
                XCTAssertEqual($0 as? TranslationError, .invalidCredential)
            }
        }
    }

    func testResponseParsingHandlesUnicodeWhitespaceEmptyAndTruncatedResults() throws {
        XCTAssertEqual(try AliyunTranslationClient.parse(success("  สวัสดี\n你好  "), status: 200), "สวัสดี\n你好")
        let malformed = [Data(), Data("not JSON".utf8), Data("{}".utf8), Data(#"{"choices":[]}"#.utf8), success("  "), success("answer", reason: "content_filter"), success("answer", reason: "tool_calls")]
        for body in malformed {
            XCTAssertThrowsError(try AliyunTranslationClient.parse(body, status: 200)) {
                XCTAssertEqual($0 as? TranslationError, .invalidResponse)
            }
        }
        XCTAssertThrowsError(try AliyunTranslationClient.parse(success("partial", reason: "length"), status: 200)) {
            XCTAssertEqual($0 as? TranslationError, .incompleteResponse)
        }
        let refused = Data(#"{"choices":[{"message":{"content":"answer","refusal":"no"},"finish_reason":"stop"}]}"#.utf8)
        XCTAssertThrowsError(try AliyunTranslationClient.parse(refused, status: 200))
    }

    func testHTTPErrorMappingNeverReturnsServerBody() {
        for (status, expected) in [(401, TranslationError.authentication), (403, .authentication), (429, .rateLimited), (404, .modelUnavailable), (400, .rejected), (422, .rejected), (500, .serviceUnavailable), (503, .serviceUnavailable), (302, .invalidResponse), (204, .invalidResponse)] {
            XCTAssertThrowsError(try AliyunTranslationClient.parse(Data("secret-key and private text".utf8), status: status)) {
                XCTAssertEqual($0 as? TranslationError, expected)
            }
        }
    }

    func testURLSessionAdapterParsesInjectedHTTPResponse() async throws {
        let started = expectation(description: "HTTP request")
        let body = success("สวัสดี")
        TranslationURLProtocol.handler = { stub in
            XCTAssertEqual(stub.request.url?.host, "dashscope-intl.aliyuncs.com")
            started.fulfill()
            stub.client?.urlProtocol(stub, didReceive: HTTPURLResponse(url: stub.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            stub.client?.urlProtocol(stub, didLoad: body)
            stub.client?.urlProtocolDidFinishLoading(stub)
        }
        defer { TranslationURLProtocol.handler = nil }
        let client = AliyunTranslationClient(transport: urlTransport())
        let translated = try await client.translate(input(), credentials: credentials)
        XCTAssertEqual(translated, "สวัสดี")
        await fulfillment(of: [started], timeout: 1)
    }

    func testURLSessionCancellationStopsInFlightRequest() async throws {
        let started = expectation(description: "request started")
        let stopped = expectation(description: "URLSession cancelled request")
        TranslationURLProtocol.handler = { _ in started.fulfill() }
        TranslationURLProtocol.stopped = { stopped.fulfill() }
        defer { TranslationURLProtocol.handler = nil; TranslationURLProtocol.stopped = nil }
        let client = AliyunTranslationClient(transport: urlTransport())
        let input = input(), credentials = credentials
        let task = Task { try await client.translate(input, credentials: credentials) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testRedirectPolicyDoesNotForwardCredentialOrBody() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = try! AliyunTranslationClient.makeRequest(input(), credentials: credentials)
        let task = session.dataTask(with: original)
        let redirected = URLRequest(url: URL(string: "https://example.invalid/collect")!)
        let response = HTTPURLResponse(url: original.url!, statusCode: 307, httpVersion: nil, headerFields: ["Location": redirected.url!.absoluteString])!
        var called = false
        TranslationURLSessionTransport.NoRedirects().urlSession(session, task: task,
            willPerformHTTPRedirection: response, newRequest: redirected) { forwarded in
                called = true
                XCTAssertNil(forwarded)
            }
        XCTAssertTrue(called)
    }

    func testTimeoutOfflineAndCancellationAreSanitized() async {
        for (code, expected) in [(URLError.timedOut, TranslationError.timedOut), (.notConnectedToInternet, .network)] {
            let client = AliyunTranslationClient(transport: FailingTranslationTransport(error: URLError(code)))
            do { _ = try await client.translate(input(), credentials: credentials); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? TranslationError, expected) }
        }
        let client = AliyunTranslationClient(transport: FailingTranslationTransport(error: URLError(.cancelled)))
        do { _ = try await client.translate(input(), credentials: credentials); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func input(text: String = "Hello") -> TranslationInput {
        .init(text: text, source: .english, target: .thai)
    }

    private func success(_ text: String, reason: String = "stop") -> Data {
        try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text], "finish_reason": reason]]])
    }

    private func urlTransport() -> TranslationURLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationURLProtocol.self]
        return TranslationURLSessionTransport(configuration: configuration)
    }
}

private struct FailingTranslationTransport: TranslationTransport {
    let error: Error
    func data(for request: URLRequest) async throws -> (Data, URLResponse) { throw error }
}

private final class TranslationURLProtocol: URLProtocol {
    static var handler: ((TranslationURLProtocol) -> Void)?
    static var stopped: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() { Self.stopped?() }
}
