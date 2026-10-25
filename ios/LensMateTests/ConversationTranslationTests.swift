import AVFoundation
import XCTest
@testable import LensMate

final class ConversationTranslationAudioTests: XCTestCase {
    func testManualModeNeverSubmitsEitherSideAndAutomaticModeHonorsConfiguredCap() {
        for limit in [30.0, 120, 300] {
            var manual = TranslationSilenceDetector(options: .init(maximumDuration: limit))
            manual.observe(decibels: -20, elapsed: 0.2)
            for speaker in [TranslationSpeaker.me, .partner] {
                XCTAssertFalse(manual.shouldFinish(speaker: speaker, elapsed: 10))
                XCTAssertFalse(manual.shouldFinish(speaker: speaker, elapsed: limit))
            }
            var automatic = TranslationSilenceDetector(options: .init(maximumDuration: limit, automaticallyEndsMyTurn: true))
            automatic.observe(decibels: -20, elapsed: limit - 0.1)
            XCTAssertFalse(automatic.shouldFinish(speaker: .me, elapsed: limit - 0.01))
            XCTAssertTrue(automatic.shouldFinish(speaker: .me, elapsed: limit))
            XCTAssertFalse(automatic.shouldFinish(speaker: .partner, elapsed: limit))
        }
    }

    func testConverterPreservesSpeechAcrossPhoneAndHFPFormats() throws {
        for rate in [8_000.0, 16_000, 24_000, 44_100, 48_000] {
            for interleaved in [true, false] {
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: interleaved)!
                let converter = try TranslationAudioConverter(inputFormat: format)
                let store = TranslationPCMBuffer(sampleRate: Int(converter.outputFormat.sampleRate))
                let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
                input.frameLength = 1_024
                var frames = 0
                while frames < Int(rate * 2) {
                    for frame in 0..<1_024 {
                        let value = Float(sin(2 * Double.pi * 440 * Double(frames + frame) / rate) * 0.5)
                        for channel in 0..<2 {
                            if interleaved { input.floatChannelData![0][frame * 2 + channel] = value }
                            else { input.floatChannelData![channel][frame] = value }
                        }
                    }
                    store.append(try converter.convert(input))
                    frames += 1_024
                }
                let actual = store.progress()
                XCTAssertEqual(store.sampleRate, Int(min(rate, 12_000)))
                XCTAssertEqual(actual.elapsed, Double(frames) / rate, accuracy: 0.03)
                XCTAssertGreaterThan(actual.decibels, -15)
                XCTAssertLessThan(actual.decibels, -5)
                XCTAssertFalse(actual.failed)
            }
        }
    }

    func testFiveMinuteRecordingFitsEncodedASRLimitAndStopsAtSelectedDuration() throws {
        let store = TranslationPCMBuffer(sampleRate: 12_000, maximumDuration: 300)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 12_000, channels: 1, interleaved: false)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 12_000)!
        audio.frameLength = 12_000
        for frame in 0..<12_000 { audio.floatChannelData![0][frame] = 0.25 }
        for _ in 0..<301 { store.append(audio) }
        let recording = store.recording()
        XCTAssertEqual(recording.duration, 300)
        XCTAssertEqual(recording.wav.count, 7_200_044)
        XCTAssertLessThan(recording.wav.base64EncodedData().count, AliyunSpeechRecognitionClient.maximumBase64Bytes)
        let request = try AliyunSpeechRecognitionClient.makeRequest(recording, language: .english, credentials: .init(region: .beijing, apiKey: "test-key"))
        XCTAssertEqual(request.timeoutInterval, 90)
        var oversized = recording.wav
        oversized.append(Data(repeating: 0, count: 400_000))
        XCTAssertThrowsError(try AliyunSpeechRecognitionClient.makeRequest(.init(wav: oversized, duration: 300), language: .english, credentials: .init(region: .beijing, apiKey: "test-key")))
        store.markConversionFailed()
        XCTAssertTrue(store.progress().failed)
    }

    func testLongTranscriptChunksPreserveChineseEnglishThaiAndGraphemeBoundaries() throws {
        for text in [String(repeating: "This is a sentence. ", count: 250), String(repeating: "你好世界。", count: 500), String(repeating: "สวัสดี", count: 700), String(repeating: "👨‍👩‍👧‍👦", count: 400)] {
            let chunks = TranslationTranscript.chunks(text)
            XCTAssertGreaterThan(chunks.count, 1)
            XCTAssertEqual(chunks.joined(), text)
            for chunk in chunks {
                XCTAssertLessThanOrEqual(chunk.unicodeScalars.count, TranslationInput.maximumLength)
                XCTAssertFalse(chunk.isEmpty)
                try TranslationInput(text: chunk, source: .english, target: .chinese).validate()
            }
        }
    }

    func testConfigurableSilenceSubmitsOnlyOurTurn() {
        for seconds in [1.0, 3, 5, 10] {
            var detector = TranslationSilenceDetector(options: .init(silenceDuration: seconds, automaticallyEndsMyTurn: true))
            detector.observe(decibels: -20, elapsed: 0.1)
            detector.observe(decibels: -20, elapsed: 0.2)
            XCTAssertTrue(detector.hasSpeech)
            XCTAssertFalse(detector.shouldFinish(speaker: .me, elapsed: 0.2 + seconds - 0.01))
            XCTAssertTrue(detector.shouldFinish(speaker: .me, elapsed: 0.2 + seconds))
            XCTAssertFalse(detector.shouldFinish(speaker: .partner, elapsed: 0.2 + seconds + 10))
        }
    }

    func testSpeechResetsSilenceAndSilenceAloneNeverCreatesUtterance() {
        var detector = TranslationSilenceDetector(options: .init(automaticallyEndsMyTurn: true))
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
        for audio in [RecordedTranslationSpeech(wav: Data(), duration: 0), .init(wav: testRecording().wav, duration: 301), .init(wav: Data(repeating: 0, count: 100), duration: 1)] {
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
    func testEachButtonStartsAndFinishesItsOwnSideWithoutSwitchingAnActiveRecording() async {
        for speaker in [TranslationSpeaker.me, .partner] {
            let f = Fixture(maximumDuration: 300)
            let other: TranslationSpeaker = speaker == .me ? .partner : .me
            XCTAssertTrue(f.model.canTapRecordingButton(for: speaker))
            f.model.tapRecordingButton(for: speaker)
            XCTAssertFalse(f.model.canTapRecordingButton(for: speaker)) // preparing
            await eventually { f.model.phase == .recording(speaker) }
            XCTAssertEqual(f.recorder.options.first?.maximumDuration, 300)
            XCTAssertEqual(f.recorder.options.first?.automaticallyEndsMyTurn, false)
            XCTAssertFalse(f.model.canTapRecordingButton(for: other))
            f.model.tapRecordingButton(for: other)
            XCTAssertEqual(f.recorder.speakers, [speaker])
            f.recorder.onProgress?(.init(elapsed: 300, hasSpeech: true, silenceRemaining: nil))
            XCTAssertTrue(f.asr.pending.isEmpty)
            XCTAssertEqual(f.model.phase, .recording(speaker))
            f.model.tapRecordingButton(for: speaker)
            f.model.tapRecordingButton(for: speaker) // repeated stop cannot upload twice
            await eventually { f.asr.pending.count == 1 }
            XCTAssertFalse(f.model.canTapRecordingButton(for: speaker))
            f.model.stop()
            f.asr.resolve(0, "late")
            await eventually { f.asr.finished == 1 }
            XCTAssertTrue(f.mt.inputs.isEmpty)
            f.model.leave()
        }
    }

    func testLongTranscriptProducesOneCardAndCancellationPreventsFurtherChunks() async {
        let original = String(repeating: "Hello. ", count: 700)
        let chunks = TranslationTranscript.chunks(original)
        for cancel in [false, true] {
            let f = Fixture()
            f.model.beginSpeaking(.me)
            await eventually { f.model.phase == .recording(.me) }
            f.model.finishRecording()
            await eventually { f.asr.pending.count == 1 }
            f.asr.resolve(0, original)
            await eventually { f.mt.pending.count == 1 }
            f.mt.resolve(0, "第一段")
            await eventually { f.mt.pending.count == 2 }
            XCTAssertTrue(f.model.turns[0].translation.isEmpty)
            if cancel {
                f.model.stop()
                f.mt.resolve(1, "旧的第二段")
                await eventually { f.mt.finished == 2 }
                await drain()
                XCTAssertEqual(f.mt.pending.count, 2)
                XCTAssertEqual(f.model.turns[0].status, .cancelled)
                XCTAssertTrue(f.model.turns[0].translation.isEmpty)
            } else {
                for index in 1..<chunks.count {
                    await eventually { f.mt.pending.count == index + 1 }
                    f.mt.resolve(index, "后续段落")
                }
                await eventually { f.model.phase == .waitingForPartner }
                XCTAssertEqual(f.mt.inputs.map(\.text).joined(), original)
                XCTAssertEqual(f.model.turns.count, 1)
                XCTAssertEqual(f.model.turns[0].original, original)
                XCTAssertEqual(f.model.turns[0].translation, (["第一段"] + Array(repeating: "后续段落", count: chunks.count - 1)).joined(separator: "\n"))
            }
            XCTAssertTrue(f.speech.spoken.isEmpty)
            f.model.leave()
        }
    }

    func testRecordingLimitAndAutomaticFinishPreferencesPersistAndClamp() {
        let suite = "ConversationLimitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = TranslationConfiguration(defaults: defaults)
        XCTAssertEqual(config.maximumRecordingDuration, 60)
        XCTAssertFalse(config.automaticallyEndsMyTurn)
        config.setMaximumRecordingDuration(180)
        config.setAutomaticallyEndsMyTurn(true)
        let restored = TranslationConfiguration(defaults: defaults)
        XCTAssertEqual(restored.maximumRecordingDuration, 180)
        XCTAssertTrue(restored.automaticallyEndsMyTurn)
        config.setMaximumRecordingDuration(900)
        XCTAssertEqual(config.maximumRecordingDuration, 300)
        config.setMaximumRecordingDuration(-1)
        XCTAssertEqual(config.maximumRecordingDuration, 30)
        config.setMaximumRecordingDuration(.infinity)
        XCTAssertEqual(config.maximumRecordingDuration, 60)
        XCTAssertEqual(Set(defaults.persistentDomain(forName: suite)!.keys), [TranslationConfiguration.recordingLimitKey, TranslationConfiguration.automaticFinishKey])
    }

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

    func testPartnerIsManualThenPlaysInGlassesWithoutRestartingOurMic() async {
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
        await eventually { f.model.phase == .paused }
        XCTAssertEqual(f.recorder.speakers, [.partner])
        XCTAssertFalse(f.recorder.recording)
        XCTAssertEqual(f.model.turns.count, 1)
        f.model.leave()
    }

    func testAutomaticMyTurnFinishUsesConfiguredDurationAndOnlySubmitsOnce() async {
        let f = Fixture(duration: 8, maximumDuration: 180, automaticFinish: true)
        f.model.beginSpeaking(.me)
        await eventually { f.model.phase == .recording(.me) }
        XCTAssertEqual(f.recorder.options, [.init(silenceDuration: 8, maximumDuration: 180, automaticallyEndsMyTurn: true)])
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
    init(duration: Double = 5, maximumDuration: Double = 60, automaticFinish: Bool = false, credentialError: TranslationError? = nil) {
        model = ConversationTranslationViewModel(recognizer: asr, translator: mt, recorder: recorder, speech: speech, router: router,
            audio: TranslationAudioCoordinator(stopAssistantSpeech: {}), credentials: {
                if let credentialError { throw credentialError }
                return .init(region: .singapore, apiKey: "test")
            }, recordingOptions: { .init(silenceDuration: duration, maximumDuration: maximumDuration, automaticallyEndsMyTurn: automaticFinish) })
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
    var speakers: [TranslationSpeaker] = []
    var options: [TranslationRecordingOptions] = []
    var recording = false, delayStart = false
    var pendingStart: CheckedContinuation<String, Error>?
    var failure: TranslationError?
    func start(speaker: TranslationSpeaker, options: TranslationRecordingOptions) async throws -> String {
        if let failure { throw failure }
        speakers.append(speaker); self.options.append(options)
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
