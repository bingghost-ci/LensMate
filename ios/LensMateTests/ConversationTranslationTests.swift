import AVFoundation
import XCTest
@testable import LensMate

final class ConversationTranslationAudioTests: XCTestCase {
    func testConfigurableSilenceSubmitsOnlyOurTurn() {
        for seconds in [1.0, 3, 5, 10] {
            var detector = TranslationSilenceDetector(silenceDuration: seconds)
            detector.observe(decibels: -20, elapsed: 0.1)
            detector.observe(decibels: -20, elapsed: 0.2)
            XCTAssertTrue(detector.hasSpeech)
            XCTAssertFalse(detector.shouldFinish(speaker: .me, elapsed: 0.2 + seconds - 0.01))
            XCTAssertTrue(detector.shouldFinish(speaker: .me, elapsed: 0.2 + seconds))
            XCTAssertFalse(detector.shouldFinish(speaker: .partner, elapsed: 0.2 + seconds + 10))
        }
    }

    func testSpeechResetsSilenceAndSilenceAloneNeverCreatesUtterance() {
        var detector = TranslationSilenceDetector(silenceDuration: 5)
        detector.observe(decibels: -80, elapsed: 5)
        XCTAssertFalse(detector.hasSpeech)
        XCTAssertFalse(detector.shouldFinish(speaker: .me, elapsed: 10))
        detector.observe(decibels: -10, elapsed: 5.1) // a short click
        detector.observe(decibels: -80, elapsed: 5.2)
        XCTAssertFalse(detector.hasSpeech)
        detector.observe(decibels: -20, elapsed: 6)
        detector.observe(decibels: -20, elapsed: 6.1)
        detector.observe(decibels: -20, elapsed: 9)
        XCTAssertFalse(detector.shouldFinish(speaker: .me, elapsed: 13.99))
        XCTAssertTrue(detector.shouldFinish(speaker: .me, elapsed: 14))
        XCTAssertFalse(detector.shouldFinish(speaker: .partner, elapsed: 60))
    }

    func testPCMRecordingIsMonoLittleEndianWAVAndBounded() throws {
        let buffer = TranslationPCMBuffer(sampleRate: 16_000)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: false)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        audio.frameLength = 16_000
        for frame in 0..<16_000 {
            audio.floatChannelData![0][frame] = 0.5
            audio.floatChannelData![1][frame] = 0.5
        }
        buffer.append(audio)
        let clip = buffer.recording()
        XCTAssertEqual(clip.duration, 1)
        XCTAssertEqual(clip.wav.count, 32_044)
        XCTAssertEqual(String(data: clip.wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: clip.wav[8..<16], encoding: .ascii), "WAVEfmt ")
        XCTAssertEqual(Array(clip.wav[22..<24]), [1, 0]) // mono
        XCTAssertEqual(Array(clip.wav[24..<28]), [0x80, 0x3e, 0, 0]) // 16 kHz
        XCTAssertEqual(Array(clip.wav[44..<46]), [0xff, 0x3f])
        XCTAssertGreaterThan(buffer.progress().decibels, -10)
        for _ in 0..<65 { buffer.append(audio) }
        XCTAssertEqual(buffer.recording().duration, 60)
        XCTAssertEqual(buffer.recording().wav.count, 1_920_044)
    }

    func testInterleavedStereoPCMIsSafelyMixedToMono() {
        let store = TranslationPCMBuffer(sampleRate: 16_000)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2
        buffer.floatChannelData![0][0] = 0.5
        buffer.floatChannelData![0][1] = -0.5
        buffer.floatChannelData![0][2] = 0.5
        buffer.floatChannelData![0][3] = 0.5
        store.append(buffer)
        XCTAssertEqual(Array(store.recording().wav.suffix(4)), [0, 0, 0xff, 0x3f])
    }

    func testASRRequestUsesOnlyThisRecordingAndExplicitLanguageInBothRegions() throws {
        for region in TranslationRegion.allCases {
            for language in TranslationLanguage.allCases {
                let recording = testRecording()
                let request = try AliyunSpeechRecognitionClient.makeRequest(recording, language: language, credentials: .init(region: region, apiKey: "test-key"))
                XCTAssertEqual(request.url, region.endpoint)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
                XCTAssertEqual(Set(body.keys), ["model", "messages", "stream", "asr_options"])
                XCTAssertEqual(body["model"] as? String, "qwen3-asr-flash")
                XCTAssertEqual(body["stream"] as? Bool, false)
                let options = try XCTUnwrap(body["asr_options"] as? [String: Any])
                XCTAssertEqual(options["language"] as? String, language.recognitionCode)
                XCTAssertEqual(options["enable_itn"] as? Bool, false)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertEqual(messages.count, 1)
                XCTAssertEqual(messages[0]["role"] as? String, "user")
                let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
                XCTAssertEqual(content.count, 1)
                XCTAssertEqual(content[0]["type"] as? String, "input_audio")
                XCTAssertEqual(content[0]["input_audio"] as? [String: String], ["data": "data:audio/wav;base64," + recording.wav.base64EncodedString()])
            }
        }
    }

    func testASRRejectsInvalidAudioAndSanitizesRecognitionFailures() throws {
        let credentials = TranslationCredentials(region: .beijing, apiKey: "test-key")
        for audio in [RecordedTranslationSpeech(wav: Data(), duration: 0), .init(wav: testRecording().wav, duration: 61), .init(wav: Data(repeating: 0, count: 100), duration: 1)] {
            XCTAssertThrowsError(try AliyunSpeechRecognitionClient.makeRequest(audio, language: .chinese, credentials: credentials)) {
                XCTAssertEqual($0 as? TranslationError, .invalidRecording)
            }
        }
        let response = Data(#"{"choices":[{"message":{"content":"สวัสดี"},"finish_reason":"stop"}]}"#.utf8)
        XCTAssertEqual(try AliyunSpeechRecognitionClient.parse(response, status: 200), "สวัสดี")
        for (status, body, expected) in [(404, response, TranslationError.recognitionUnavailable), (401, response, .authentication), (429, response, .rateLimited), (200, Data("private backend details".utf8), .recognitionFailed)] {
            XCTAssertThrowsError(try AliyunSpeechRecognitionClient.parse(body, status: status)) { XCTAssertEqual($0 as? TranslationError, expected) }
        }
    }

    func testASRTransportTimeoutAndCancellationRemainCancellable() async {
        let credentials = TranslationCredentials(region: .beijing, apiKey: "test-key")
        for (code, expected) in [(URLError.timedOut, TranslationError.timedOut), (.notConnectedToInternet, .network)] {
            let client = AliyunSpeechRecognitionClient(transport: SpeechFailingTransport(error: URLError(code)))
            do { _ = try await client.recognize(testRecording(), language: .chinese, credentials: credentials); XCTFail() }
            catch { XCTAssertEqual(error as? TranslationError, expected) }
        }
        let client = AliyunSpeechRecognitionClient(transport: SpeechFailingTransport(error: URLError(.cancelled)))
        do { _ = try await client.recognize(testRecording(), language: .chinese, credentials: credentials); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

@MainActor
final class ConversationTranslationTests: XCTestCase {
    func testMyTurnDisplaysBothLanguagesWithoutReadingOrStartingPhoneMic() async {
        let f = Fixture()
        f.model.beginSpeaking(.me)
        await eventually { f.model.phase == .recording(.me) }
        XCTAssertEqual(f.recorder.speakers, [.me])
        XCTAssertTrue(f.asr.pending.isEmpty) // no upload before the utterance ends
        f.model.finishRecording()
        XCTAssertFalse(f.recorder.recording)
        await eventually { f.asr.pending.count == 1 }
        XCTAssertEqual(f.asr.languages, [.chinese])
        f.asr.resolve(0, "你好")
        await eventually { f.mt.pending.count == 1 }
        XCTAssertEqual(f.model.turns.first?.original, "你好")
        XCTAssertEqual(f.mt.inputs[0], .init(text: "你好", source: .chinese, target: .english))
        f.mt.resolve(0, "Hello")
        await eventually { f.model.phase == .waitingForPartner }
        XCTAssertEqual(f.model.turns.first?.translation, "Hello")
        XCTAssertEqual(f.model.turns.first?.status, .complete)
        XCTAssertTrue(f.speech.spoken.isEmpty)
        XCTAssertFalse(f.recorder.recording)
        XCTAssertEqual(f.recorder.speakers, [.me])
        f.model.leave()
    }

    func testPartnerIsManualThenPlaysInGlassesBeforeOurMicResumes() async {
        let f = Fixture()
        f.model.beginSpeaking(.partner)
        await eventually { f.model.phase == .recording(.partner) }
        f.recorder.onProgress?(.init(elapsed: 15, hasSpeech: true, silenceRemaining: nil))
        XCTAssertEqual(f.model.phase, .recording(.partner))
        XCTAssertTrue(f.asr.pending.isEmpty)
        f.model.finishRecording()
        await eventually { f.asr.pending.count == 1 }
        f.asr.resolve(0, "How are you?")
        await eventually { f.mt.pending.count == 1 }
        XCTAssertEqual(f.mt.inputs[0], .init(text: "How are you?", source: .english, target: .chinese))
        f.mt.resolve(0, "你好吗？")
        await eventually { f.speech.spoken.count == 1 }
        XCTAssertEqual(f.router.outputs, [.partner])
        XCTAssertEqual(f.speech.spoken.first?.1, .chinese)
        XCTAssertFalse(f.recorder.recording)
        XCTAssertEqual(f.recorder.speakers, [.partner])
        f.speech.complete(true)
        await eventually { f.model.phase == .recording(.me) }
        XCTAssertEqual(f.recorder.speakers, [.partner, .me])
        XCTAssertEqual(f.model.turns.count, 1)
        f.model.leave()
    }

    func testAutomaticMyTurnFinishUsesConfiguredDurationAndOnlySubmitsOnce() async {
        let f = Fixture(duration: 8)
        f.model.beginSpeaking(.me)
        await eventually { f.model.phase == .recording(.me) }
        XCTAssertEqual(f.recorder.durations, [8])
        let callback = f.recorder.onAutomaticFinish
        f.recorder.autoFinish()
        f.model.finishRecording() // a tap racing the silence callback cannot double-submit
        callback?(.success(testRecording()))
        await eventually { f.asr.pending.count == 1 }
        XCTAssertEqual(f.model.turns.count, 1)
        f.model.stop()
        f.asr.resolve(0, "late")
        await eventually { f.asr.finished == 1 }
        await drain()
        XCTAssertTrue(f.mt.pending.isEmpty)
    }

    func testStopExitLanguageChangeAndClearRejectLateRecognition() async {
        let actions: [(ConversationTranslationViewModel) -> Void] = [
            { $0.stop() }, { $0.suspend() }, { $0.leave() }, { $0.swapLanguages() },
            { $0.selectMyLanguage(.thai) }, { $0.selectPartnerLanguage(.thai) }, { $0.clearConversation() }
        ]
        for action in actions {
            let f = Fixture()
            f.model.beginSpeaking(.me)
            await eventually { f.model.phase == .recording(.me) }
            f.model.finishRecording()
            await eventually { f.asr.pending.count == 1 }
            action(f.model)
            f.asr.resolve(0, "stale transcript")
            await eventually { f.asr.finished == 1 }
            await drain()
            XCTAssertTrue(f.mt.inputs.isEmpty)
            XCTAssertTrue(f.speech.spoken.isEmpty)
            XCTAssertFalse(f.recorder.recording)
            XCTAssertFalse(f.model.isConversationRunning)
            XCTAssertFalse(f.model.turns.contains { $0.original == "stale transcript" })
            f.model.leave()
        }
    }

    func testNewTurnRejectsOldTranslationAndPreservesOrderedCards() async {
        let f = Fixture()
        f.model.beginSpeaking(.me)
        await eventually { f.model.phase == .recording(.me) }
        f.model.finishRecording()
        await eventually { f.asr.pending.count == 1 }
        f.asr.resolve(0, "old source")
        await eventually { f.mt.pending.count == 1 }
        f.model.beginSpeaking(.partner)
        await eventually { f.model.phase == .recording(.partner) }
        f.mt.resolve(0, "stale target")
        await eventually { f.mt.finished == 1 }
        await drain()
        XCTAssertEqual(f.model.phase, .recording(.partner))
        XCTAssertEqual(f.model.turns[0].status, .cancelled)
        XCTAssertEqual(f.model.turns[0].original, "old source")
        XCTAssertTrue(f.model.turns[0].translation.isEmpty)
        XCTAssertTrue(f.speech.spoken.isEmpty)
        f.model.leave()
    }

    func testStoppedOrCancelledPlaybackDoesNotRestartMic() async {
        for stop in [true, false] {
            let f = Fixture()
            await translatedPartner(f)
            if stop { f.model.stop() }
            f.speech.complete(!stop ? false : true)
            await drain()
            XCTAssertFalse(f.recorder.recording)
            XCTAssertFalse(f.model.isConversationRunning)
            XCTAssertEqual(f.recorder.speakers, [.partner])
            f.model.leave()
        }
    }

    func testLatePreparationAndOldAudioCallbacksCannotRestartStoppedRecording() async {
        let f = Fixture()
        f.recorder.delayStart = true
        f.model.beginSpeaking(.me)
        await eventually { f.recorder.pendingStart != nil }
        let callback = f.recorder.onAutomaticFinish
        f.model.stop()
        f.recorder.resolveStart()
        await drain()
        callback?(.success(testRecording()))
        XCTAssertEqual(f.model.phase, .idle)
        XCTAssertTrue(f.asr.pending.isEmpty)
        XCTAssertFalse(f.model.isConversationRunning)
        f.model.leave()
    }

    func testDeviceLossAndVoiceFailureKeepTextWithoutPhoneFallback() async {
        let f = Fixture()
        f.router.failure = .headsetUnavailable
        f.model.beginSpeaking(.partner)
        await eventually { f.model.phase == .recording(.partner) }
        f.model.finishRecording()
        await eventually { f.asr.pending.count == 1 }
        f.asr.resolve(0, "Hello")
        await eventually { f.mt.pending.count == 1 }
        f.mt.resolve(0, "你好")
        await eventually { f.model.error == .headsetUnavailable }
        XCTAssertEqual(f.model.turns[0].translation, "你好")
        XCTAssertEqual(f.model.turns[0].status, .complete)
        XCTAssertTrue(f.speech.spoken.isEmpty)
        XCTAssertFalse(f.recorder.recording)
        f.router.failure = nil
        f.speech.failure = .voiceUnavailable
        f.model.replay(f.model.turns[0].id)
        await eventually { f.model.error == .voiceUnavailable }
        XCTAssertEqual(f.model.turns[0].translation, "你好")
        f.model.leave()
    }

    func testSwitchingSpeakerInvalidatesOldMicrophoneCallbackWithoutUploading() async {
        let f = Fixture()
        f.model.beginSpeaking(.me)
        await eventually { f.model.phase == .recording(.me) }
        let oldCallback = f.recorder.onAutomaticFinish
        f.model.beginSpeaking(.partner)
        await eventually { f.model.phase == .recording(.partner) }
        oldCallback?(.success(testRecording()))
        await drain()
        XCTAssertEqual(f.model.phase, .recording(.partner))
        XCTAssertTrue(f.asr.pending.isEmpty)
        XCTAssertEqual(f.recorder.speakers, [.me, .partner])
        f.model.leave()
    }

    func testTranslationFailureKeepsSourceAndRetriesWithoutUploadingAudioAgain() async {
        let f = Fixture()
        f.model.beginSpeaking(.me)
        await eventually { f.model.phase == .recording(.me) }
        f.model.finishRecording()
        await eventually { f.asr.pending.count == 1 }
        f.asr.resolve(0, "你好")
        await eventually { f.mt.pending.count == 1 }
        f.mt.pending[0].resume(throwing: TranslationError.authentication)
        await eventually { f.model.error == .authentication }
        XCTAssertEqual(f.model.turns[0].original, "你好")
        XCTAssertEqual(f.model.turns[0].status, .failed(.authentication))
        f.model.retryTranslation(f.model.turns[0].id)
        await eventually { f.mt.pending.count == 2 }
        f.mt.resolve(1, "Hello")
        await eventually { f.model.phase == .waitingForPartner }
        XCTAssertEqual(f.asr.pending.count, 1)
        XCTAssertEqual(f.model.turns.count, 1)
        XCTAssertEqual(f.model.turns[0].translation, "Hello")
        f.model.leave()
    }

    func testMissingCredentialsPermissionAndNoSpeechDoNotUpload() async {
        let f = Fixture(credentialError: .notConfigured)
        f.model.beginSpeaking(.me)
        XCTAssertEqual(f.model.error, .notConfigured)
        XCTAssertTrue(f.recorder.speakers.isEmpty)
        for error in [TranslationError.microphonePermission, .headsetUnavailable, .noSpeech] {
            let f = Fixture()
            f.recorder.failure = error
            f.model.beginSpeaking(.me)
            await eventually { f.model.error == error }
            XCTAssertTrue(f.asr.pending.isEmpty)
            XCTAssertFalse(f.model.isConversationRunning)
            f.model.leave()
        }
        f.model.leave()
    }

    func testAudioRouteChangeStopsTurnAndReturningNeverAutomaticallyRecords() async {
        let f = Fixture()
        f.model.beginSpeaking(.partner)
        await eventually { f.model.phase == .recording(.partner) }
        f.model.audioDeviceChanged()
        XCTAssertFalse(f.recorder.recording)
        XCTAssertEqual(f.model.error, .microphoneRouteChanged)
        f.model.suspend()
        f.model.activate()
        await drain()
        XCTAssertEqual(f.recorder.speakers, [.partner])
        XCTAssertFalse(f.recorder.recording)
        f.model.leave()
    }

    func testSilencePreferenceDefaultsPersistsAndClampsWithoutTouchingSecrets() {
        let suite = "ConversationPauseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = TranslationConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.silenceDuration, 5)
        configuration.setSilenceDuration(8)
        XCTAssertEqual(TranslationConfiguration(defaults: defaults).silenceDuration, 8)
        configuration.setSilenceDuration(0)
        XCTAssertEqual(configuration.silenceDuration, 1)
        configuration.setSilenceDuration(99)
        XCTAssertEqual(configuration.silenceDuration, 10)
        configuration.setSilenceDuration(.nan)
        XCTAssertEqual(configuration.silenceDuration, 5)
        XCTAssertEqual(Set(defaults.persistentDomain(forName: suite)!.keys), [TranslationConfiguration.silenceKey])
    }

    private func translatedPartner(_ f: Fixture) async {
        f.model.beginSpeaking(.partner)
        await eventually { f.model.phase == .recording(.partner) }
        f.model.finishRecording()
        await eventually { f.asr.pending.count == 1 }
        f.asr.resolve(0, "Hello")
        await eventually { f.mt.pending.count == 1 }
        f.mt.resolve(0, "你好")
        await eventually { f.speech.spoken.count == 1 }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }

    private func drain() async { for _ in 0..<10 { await Task.yield() } }
}

@MainActor
private final class Fixture {
    let asr = ControlledConversationASR()
    let mt = ControlledConversationMT()
    let recorder = TestConversationRecorder()
    let speech = TestConversationSpeech()
    let router = TestConversationRouter()
    let model: ConversationTranslationViewModel
    init(duration: Double = 5, credentialError: TranslationError? = nil) {
        model = ConversationTranslationViewModel(recognizer: asr, translator: mt, recorder: recorder, speech: speech, router: router,
            audio: TranslationAudioCoordinator(stopAssistantSpeech: {}), credentials: {
                if let credentialError { throw credentialError }
                return .init(region: .singapore, apiKey: "test")
            }, silenceDuration: { duration })
        model.activate()
    }
}

@MainActor
private final class ControlledConversationASR: TranslationSpeechRecognizing {
    var pending: [CheckedContinuation<String, Error>] = []
    var languages: [TranslationLanguage] = []
    var finished = 0
    func recognize(_ audio: RecordedTranslationSpeech, language: TranslationLanguage, credentials: TranslationCredentials) async throws -> String {
        languages.append(language)
        defer { finished += 1 }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func resolve(_ index: Int, _ text: String) { pending[index].resume(returning: text) }
}

@MainActor
private final class ControlledConversationMT: TextTranslating {
    var pending: [CheckedContinuation<String, Error>] = []
    var inputs: [TranslationInput] = []
    var finished = 0
    func translate(_ input: TranslationInput, credentials: TranslationCredentials) async throws -> String {
        inputs.append(input)
        defer { finished += 1 }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func resolve(_ index: Int, _ text: String) { pending[index].resume(returning: text) }
}

@MainActor
private final class TestConversationRecorder: TranslationConversationRecording {
    var onProgress: ((TranslationRecordingProgress) -> Void)?
    var onAutomaticFinish: ((Result<RecordedTranslationSpeech, TranslationError>) -> Void)?
    var speakers: [TranslationSpeaker] = [], durations: [Double] = []
    var recording = false, delayStart = false
    var pendingStart: CheckedContinuation<String, Error>?
    var failure: TranslationError?
    func start(speaker: TranslationSpeaker, silenceDuration: TimeInterval) async throws -> String {
        if let failure { throw failure }
        speakers.append(speaker); durations.append(silenceDuration)
        if delayStart { return try await withCheckedThrowingContinuation { pendingStart = $0 } }
        recording = true
        return "test microphone"
    }
    func finish() throws -> RecordedTranslationSpeech { recording = false; return testRecording() }
    func cancel() { recording = false }
    func autoFinish() { recording = false; onAutomaticFinish?(.success(testRecording())) }
    func resolveStart() { pendingStart?.resume(returning: "old microphone"); pendingStart = nil }
}

@MainActor
private final class TestConversationSpeech: ConversationTranslationSpeaking {
    var onSpeakingChanged: ((Bool) -> Void)?
    var onCompletion: ((Bool) -> Void)?
    var spoken: [(String, TranslationLanguage)] = []
    var failure: TranslationError?
    func speak(_ text: String, language: TranslationLanguage) throws {
        if let failure { throw failure }
        spoken.append((text, language)); onSpeakingChanged?(true)
    }
    func stop() { onSpeakingChanged?(false) }
    func complete(_ success: Bool) { onSpeakingChanged?(false); onCompletion?(success) }
}

@MainActor
private final class TestConversationRouter: TranslationConversationRouting {
    var outputs: [TranslationSpeaker] = []
    var failure: TranslationError?
    func prepareInput(for speaker: TranslationSpeaker) async throws -> String { "test microphone" }
    func prepareOutput(for speaker: TranslationSpeaker) async throws {
        outputs.append(speaker)
        if let failure { throw failure }
    }
    func inputIsCurrent() -> Bool { true }
    func release() {}
}

private struct SpeechFailingTransport: TranslationTransport {
    let error: Error
    func data(for request: URLRequest) async throws -> (Data, URLResponse) { throw error }
}

private func testRecording() -> RecordedTranslationSpeech {
    var data = Data("RIFF".utf8)
    data.append(Data(repeating: 0, count: 4))
    data.append(Data("WAVE".utf8))
    data.append(Data(repeating: 0, count: 64))
    return .init(wav: data, duration: 0.5)
}
