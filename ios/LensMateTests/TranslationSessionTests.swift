import AVFoundation
import XCTest
@testable import LensMate

@MainActor
final class TranslationSessionTests: XCTestCase {
    func testNewRequestCancelsOldAndLateResponseCannotReplaceOrSpeak() async {
        let (model, client, speech, _) = fixture()
        model.inputText = "first"
        model.translate()
        await eventually { client.pending.count == 1 }
        model.inputText = "second"
        model.selectTarget(.thai)
        model.translate()
        await eventually { client.pending.count == 2 }
        client.resolve(1, with: .success("ใหม่"))
        await eventually { model.result?.text == "ใหม่" }
        client.resolve(0, with: .success("stale"))
        await eventually { client.finished == 2 }
        await drainTasks()
        XCTAssertTrue(client.cancelled.contains(0))
        XCTAssertEqual(model.result?.input.text, "second")
        XCTAssertEqual(model.result?.text, "ใหม่")
        XCTAssertEqual(speech.spoken.map(\.text), ["ใหม่"])
        XCTAssertEqual(speech.spoken.map(\.language), [.thai])
        model.leave()
    }

    func testStopExitBackgroundAndLanguageChangesIsolateLateResponses() async {
        let actions: [(TranslationViewModel) -> Void] = [
            { $0.stop() }, { $0.leave() }, { $0.suspend() }, { $0.swapDirection() },
            { $0.selectSource(.thai) }, { $0.selectTarget(.thai) }, { $0.inputText = "edited" }
        ]
        for action in actions {
            let (model, client, speech, _) = fixture()
            model.inputText = "hello"
            model.translate()
            await eventually { client.pending.count == 1 }
            action(model)
            XCTAssertFalse(model.isTranslating)
            client.resolve(0, with: .success("outdated"))
            await eventually { client.finished == 1 }
            await drainTasks()
            XCTAssertNil(model.result)
            XCTAssertNil(model.error)
            XCTAssertTrue(speech.spoken.isEmpty)
            XCTAssertFalse(model.isSpeaking)
            XCTAssertTrue(client.cancelled.contains(0))
            model.leave()
        }
    }

    func testLateErrorCannotClearNewRequestOrShowError() async {
        let (model, client, _, _) = fixture()
        model.inputText = "first"
        model.translate()
        await eventually { client.pending.count == 1 }
        model.translate()
        await eventually { client.pending.count == 2 }
        client.resolve(0, with: .failure(TranslationError.authentication))
        await eventually { client.finished == 1 }
        await drainTasks()
        XCTAssertNil(model.error)
        XCTAssertTrue(model.isTranslating)
        client.resolve(1, with: .success("new result"))
        await eventually { model.result != nil }
        XCTAssertNil(model.error)
        model.leave()
    }

    func testStoppingSpeechRetainsResultAndReplayUsesResultLanguage() async {
        let (model, client, speech, _) = fixture()
        model.selectTarget(.thai)
        model.inputText = "你好"
        model.translate()
        await eventually { client.pending.count == 1 }
        client.resolve(0, with: .success("สวัสดี"))
        await eventually { model.isSpeaking }
        let stops = speech.stops
        model.stop()
        XCTAssertEqual(speech.stops, stops + 1)
        XCTAssertFalse(model.isSpeaking)
        XCTAssertEqual(model.result?.text, "สวัสดี")
        model.replay()
        XCTAssertEqual(speech.spoken.map(\.language), [.thai, .thai])
        XCTAssertTrue(model.isSpeaking)
        model.leave()
        XCTAssertFalse(model.isSpeaking)
        model.replay()
        XCTAssertEqual(speech.spoken.count, 2)
    }

    func testVoiceUnavailableKeepsTranslationAndAllowsReplayAfterVoiceDownload() async {
        let (model, client, speech, _) = fixture()
        speech.failure = .voiceUnavailable
        model.inputText = "你好"
        model.translate()
        await eventually { client.pending.count == 1 }
        client.resolve(0, with: .success("Hello"))
        await eventually { model.error == .voiceUnavailable }
        XCTAssertEqual(model.result?.text, "Hello")
        XCTAssertFalse(model.isSpeaking)
        speech.failure = nil
        model.replay()
        XCTAssertNil(model.error)
        XCTAssertTrue(model.isSpeaking)
        model.leave()
    }

    func testNoAutomaticSpeechWhenDisabledAndNetworkErrorIsShown() async {
        let (model, client, speech, _) = fixture()
        model.automaticallySpeak = false
        model.inputText = "你好"
        model.translate()
        await eventually { client.pending.count == 1 }
        client.resolve(0, with: .success("Hello"))
        await eventually { model.result != nil }
        XCTAssertTrue(speech.spoken.isEmpty)
        model.translate()
        await eventually { client.pending.count == 2 }
        client.resolve(1, with: .failure(TranslationError.timedOut))
        await eventually { model.error == .timedOut }
        XCTAssertNil(model.result)
        XCTAssertFalse(model.isTranslating)
        model.leave()
    }

    func testMissingCredentialsNeverStartsProvider() {
        let client = ControlledTranslator(), speech = TestTranslationSpeech()
        let audio = TranslationAudioCoordinator(stopAssistantSpeech: {})
        let model = TranslationViewModel(client: client, credentials: { throw TranslationError.credentialRead }, speech: speech, audio: audio)
        model.activate()
        model.inputText = "private text"
        model.translate()
        XCTAssertEqual(model.error, .credentialRead)
        XCTAssertTrue(client.pending.isEmpty)
        XCTAssertFalse(model.isTranslating)
        model.leave()
    }

    func testSelectingSameLanguageSwapsAndUITranslationIsIndependent() {
        let (model, _, _, _) = fixture()
        model.selectSource(.english)
        XCTAssertEqual(model.source, .english)
        XCTAssertEqual(model.target, .chinese)
        model.selectTarget(.english)
        XCTAssertEqual(model.source, .chinese)
        XCTAssertEqual(model.target, .english)
        model.swapDirection()
        XCTAssertEqual(model.source, .english)
        XCTAssertEqual(model.target, .chinese)
        XCTAssertEqual(L10n.text("Translation", language: .chinese), "翻译")
        XCTAssertEqual(L10n.text("Thai", language: .chinese), "泰语")
        XCTAssertEqual(L10n.text("Translation Settings", language: .system, preferredLanguages: ["th-TH"]), "Translation Settings")
        XCTAssertEqual(model.source.apiName, "English")
        model.leave()
    }

    func testAudioHandoffStopsAssistantBeforeTranslationAndDoesNotAutoResume() {
        var events: [String] = []
        let audio = TranslationAudioCoordinator(stopAssistantSpeech: { events.append("stop assistant speech") })
        audio.suspendAssistant = {
            XCTAssertTrue(audio.isTranslationActive)
            events.append("suspend assistant")
        }
        let speech = TestTranslationSpeech()
        let model = TranslationViewModel(client: ControlledTranslator(), credentials: { .init(region: .beijing, apiKey: "test") }, speech: speech, audio: audio)
        let oldGeneration = audio.assistantGeneration
        model.activate()
        model.activate()
        XCTAssertFalse(audio.acceptsAssistantWork(from: oldGeneration))
        XCTAssertEqual(events, ["suspend assistant", "stop assistant speech"])
        let stops = speech.stops
        model.leave()
        XCTAssertFalse(audio.isTranslationActive)
        XCTAssertFalse(audio.acceptsAssistantWork(from: oldGeneration))
        XCTAssertTrue(audio.acceptsAssistantWork(from: audio.assistantGeneration))
        XCTAssertEqual(speech.stops, stops + 1)
        XCTAssertEqual(events.count, 2)
    }

    func testAssistantSpeechEntryPointsRejectLateWorkDuringTranslation() {
        let audio = TranslationAudioCoordinator.shared
        audio.enterTranslation()
        defer { audio.leaveTranslation() }
        TTSService.shared.beginStreaming()
        TTSService.shared.speak("must not be enqueued")
        CloudTTSService.openAI.beginStreaming()
        CloudTTSService.openAI.speakChunk("must not be enqueued")
        KokoroTTSService.shared.beginStreaming()
        XCTAssertFalse(TTSService.shared.isSpeaking)
        XCTAssertFalse(CloudTTSService.openAI.isSpeaking)
        XCTAssertFalse(KokoroTTSService.shared.isSpeaking)
    }

    func testVoiceSelectionNeverFallsBackToWrongLanguage() {
        let voices = [(identifier: "english", language: "en-GB"), (identifier: "thai", language: "th-TH"), (identifier: "mandarin", language: "zh-CN"), (identifier: "cantonese", language: "zh-HK")]
        XCTAssertEqual(TranslationSpeechService.voiceIdentifier(for: .english, available: voices), "english")
        XCTAssertEqual(TranslationSpeechService.voiceIdentifier(for: .thai, available: voices), "thai")
        XCTAssertEqual(TranslationSpeechService.voiceIdentifier(for: .chinese, available: voices), "mandarin")
        XCTAssertNil(TranslationSpeechService.voiceIdentifier(for: .thai, available: [voices[0]]))
        XCTAssertNil(TranslationSpeechService.voiceIdentifier(for: .chinese, available: [voices[3]]))
    }

    func testMissingInstalledVoiceDoesNotActivateAudioAndStopReportsSilence() {
        var configured = false, released = false
        var states: [Bool] = []
        let speech = TranslationSpeechService(voices: { [] }, configureAudio: { configured = true }, releaseAudio: { released = true })
        speech.onSpeakingChanged = { states.append($0) }
        XCTAssertThrowsError(try speech.speak("สวัสดี", language: .thai)) {
            XCTAssertEqual($0 as? TranslationError, .voiceUnavailable)
        }
        speech.stop()
        XCTAssertFalse(configured)
        XCTAssertFalse(released)
        XCTAssertEqual(states, [false, false])
    }

    private func fixture() -> (TranslationViewModel, ControlledTranslator, TestTranslationSpeech, TranslationAudioCoordinator) {
        let client = ControlledTranslator(), speech = TestTranslationSpeech()
        let audio = TranslationAudioCoordinator(stopAssistantSpeech: {})
        let model = TranslationViewModel(client: client, credentials: { .init(region: .singapore, apiKey: "test-key") }, speech: speech, audio: audio)
        model.activate()
        return (model, client, speech, audio)
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }

    private func drainTasks() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

@MainActor
private final class ControlledTranslator: TextTranslating {
    var pending: [CheckedContinuation<String, Error>] = []
    var cancelled = Set<Int>()
    var finished = 0
    func translate(_ input: TranslationInput, credentials: TranslationCredentials) async throws -> String {
        let index = pending.count
        defer { finished += 1 }
        // Deliberately ignore cancellation until the test delivers a late success/failure.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending.append($0) }
        } onCancel: {
            Task { @MainActor in self.cancelled.insert(index) }
        }
    }
    func resolve(_ index: Int, with result: Result<String, Error>) { pending[index].resume(with: result) }
}

@MainActor
private final class TestTranslationSpeech: TranslationSpeaking {
    struct Spoken { let text: String; let language: TranslationLanguage }
    var onSpeakingChanged: ((Bool) -> Void)?
    var spoken: [Spoken] = []
    var stops = 0
    var failure: TranslationError?
    func speak(_ text: String, language: TranslationLanguage) throws {
        stop()
        if let failure { throw failure }
        spoken.append(.init(text: text, language: language))
        onSpeakingChanged?(true)
    }
    func stop() { stops += 1; onSpeakingChanged?(false) }
}
