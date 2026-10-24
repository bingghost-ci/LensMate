import Foundation

@MainActor
final class ConversationTranslationViewModel: ObservableObject {
    @Published private(set) var myLanguage: TranslationLanguage = .chinese
    @Published private(set) var partnerLanguage: TranslationLanguage = .english
    @Published private(set) var phase: ConversationTranslationPhase = .idle
    @Published private(set) var turns: [ConversationTranslationTurn] = []
    @Published private(set) var error: TranslationError?
    @Published private(set) var recordingProgress: TranslationRecordingProgress?
    @Published private(set) var inputDevice = ""
    @Published private(set) var isConversationRunning = false

    private let recognizer: any TranslationSpeechRecognizing
    private let translator: any TextTranslating
    private let recorder: any TranslationConversationRecording
    private let speech: any ConversationTranslationSpeaking
    private let router: any TranslationConversationRouting
    private let audio: TranslationAudioCoordinator
    private let credentials: @MainActor () throws -> TranslationCredentials
    private let silenceDuration: @MainActor () -> TimeInterval
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var active = false
    private var pendingTurn: UUID?
    private var resumeAfterSpeech = false
    private var playbackGeneration: UUID?

    init(recognizer: any TranslationSpeechRecognizing = AliyunSpeechRecognitionClient(),
         translator: any TextTranslating = AliyunTranslationClient(),
         recorder: (any TranslationConversationRecording)? = nil,
         speech: (any ConversationTranslationSpeaking)? = nil,
         router: (any TranslationConversationRouting)? = nil,
         audio: TranslationAudioCoordinator? = nil,
         credentials: (@MainActor () throws -> TranslationCredentials)? = nil,
         silenceDuration: (@MainActor () -> TimeInterval)? = nil) {
        let routing = router ?? TranslationConversationAudioRouter()
        self.recognizer = recognizer
        self.translator = translator
        self.router = routing
        self.recorder = recorder ?? TranslationConversationRecorder(router: routing)
        self.speech = speech ?? TranslationSpeechService(configureAudio: {}, releaseAudio: { routing.release() })
        self.audio = audio ?? .shared
        self.credentials = credentials ?? { try TranslationConfiguration.shared.credentials() }
        self.silenceDuration = silenceDuration ?? { TranslationConfiguration.shared.silenceDuration }
        self.speech.onCompletion = { [weak self] completed in self?.speechCompleted(completed) }
    }

    func activate() {
        audio.enterTranslation()
        active = true
        // Returning to this page never starts a microphone without a new Start action.
    }

    func suspend() { active = false; stop() }
    func leave() { suspend(); audio.leaveTranslation() }

    func selectMyLanguage(_ language: TranslationLanguage) {
        guard language != myLanguage else { return }
        stop()
        let previous = myLanguage
        myLanguage = language
        if partnerLanguage == language { partnerLanguage = previous }
    }

    func selectPartnerLanguage(_ language: TranslationLanguage) {
        guard language != partnerLanguage else { return }
        stop()
        let previous = partnerLanguage
        partnerLanguage = language
        if myLanguage == language { myLanguage = previous }
    }

    func swapLanguages() {
        stop()
        let previous = myLanguage
        myLanguage = partnerLanguage
        partnerLanguage = previous
    }

    func beginSpeaking(_ speaker: TranslationSpeaker) {
        guard active else { return }
        invalidate()
        do { _ = try credentials() }
        catch { fail(error); return }
        isConversationRunning = true
        phase = .preparing(speaker)
        let id = generation
        let duration = TranslationSilenceDetector.clampedDuration(silenceDuration())
        recorder.onProgress = { [weak self] progress in
            guard let self, self.isCurrent(id), self.phase == .recording(speaker) else { return }
            self.recordingProgress = progress
        }
        recorder.onAutomaticFinish = { [weak self] result in
            guard let self, self.isCurrent(id), self.phase == .recording(speaker) else { return }
            self.acceptRecording(result, speaker: speaker, id: id)
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let name = try await self.recorder.start(speaker: speaker, silenceDuration: duration)
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.inputDevice = name
                self.phase = .recording(speaker)
                self.task = nil
            } catch {
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.fail(error)
            }
        }
    }

    func finishRecording() {
        guard case .recording(let speaker) = phase else { return }
        let id = generation
        do { acceptRecording(.success(try recorder.finish()), speaker: speaker, id: id) }
        catch { acceptRecording(.failure((error as? TranslationError) ?? .recordingFailed), speaker: speaker, id: id) }
    }

    private func acceptRecording(_ result: Result<RecordedTranslationSpeech, TranslationError>,
                                 speaker: TranslationSpeaker, id: UUID) {
        guard isCurrent(id) else { return }
        recordingProgress = nil
        inputDevice = ""
        switch result {
        case .failure(let error): fail(error)
        case .success(let recording):
            let source = speaker == .me ? myLanguage : partnerLanguage
            let target = speaker == .me ? partnerLanguage : myLanguage
            let turn = ConversationTranslationTurn(id: UUID(), speaker: speaker, source: source, target: target)
            turns.append(turn)
            pendingTurn = turn.id
            phase = .recognizing(speaker)
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    let credential = try self.credentials()
                    let original = try await self.recognizer.recognize(recording, language: source, credentials: credential)
                    guard self.isCurrent(id), !Task.isCancelled else { return }
                    self.updateTurn(turn.id) { $0.original = original; $0.status = .translating }
                    self.phase = .translating(speaker)
                    let translated = try await self.translator.translate(.init(text: original, source: source, target: target), credentials: credential)
                    guard self.isCurrent(id), !Task.isCancelled else { return }
                    self.updateTurn(turn.id) { $0.translation = translated; $0.status = .complete }
                    self.pendingTurn = nil
                    self.task = nil
                    if speaker == .partner { self.play(turnID: turn.id, resume: true) }
                    else { self.phase = .waitingForPartner }
                } catch {
                    guard self.isCurrent(id), !Task.isCancelled else { return }
                    self.fail(error)
                }
            }
        }
    }

    func retryTranslation(_ turnID: UUID) {
        guard active, let turn = turns.first(where: { $0.id == turnID }), !turn.original.isEmpty else { return }
        invalidate()
        let id = generation
        isConversationRunning = true
        pendingTurn = turnID
        phase = .translating(turn.speaker)
        updateTurn(turnID) { $0.status = .translating }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let translated = try await self.translator.translate(.init(text: turn.original, source: turn.source, target: turn.target), credentials: self.credentials())
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.updateTurn(turnID) { $0.translation = translated; $0.status = .complete }
                self.pendingTurn = nil
                self.task = nil
                if turn.speaker == .partner { self.play(turnID: turnID, resume: true) }
                else { self.phase = .waitingForPartner }
            } catch {
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.fail(error)
            }
        }
    }

    func replay(_ turnID: UUID) { play(turnID: turnID, resume: false) }

    private func play(turnID: UUID, resume: Bool) {
        guard active, let turn = turns.first(where: { $0.id == turnID }), !turn.translation.isEmpty else { return }
        invalidate()
        isConversationRunning = resume
        let id = generation
        phase = .preparing(turn.speaker)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.router.prepareOutput(for: turn.speaker)
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.phase = .speaking(turn.id)
                self.playbackGeneration = id
                self.resumeAfterSpeech = resume
                self.task = nil
                try self.speech.speak(turn.translation, language: turn.target)
            } catch {
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.fail((error as? TranslationError) ?? .audioUnavailable)
            }
        }
    }

    private func speechCompleted(_ completed: Bool) {
        guard let id = playbackGeneration, isCurrent(id), case .speaking = phase else { return }
        playbackGeneration = nil
        if completed && resumeAfterSpeech && isConversationRunning {
            beginSpeaking(.me)
        } else {
            stop()
        }
    }

    func stop() {
        invalidate()
        isConversationRunning = false
        phase = turns.isEmpty ? .idle : .paused
    }

    func audioDeviceChanged() {
        guard active, phase != .idle, phase != .paused else { return }
        stop()
        error = .microphoneRouteChanged
    }

    func clearConversation() { stop(); turns.removeAll(); phase = .idle }

    private func isCurrent(_ id: UUID) -> Bool { active && generation == id }

    private func invalidate() {
        generation = UUID()
        task?.cancel(); task = nil
        playbackGeneration = nil
        resumeAfterSpeech = false
        recorder.onProgress = nil
        recorder.onAutomaticFinish = nil
        recorder.cancel()
        speech.stop()
        router.release()
        recordingProgress = nil
        inputDevice = ""
        error = nil
        if let pendingTurn { updateTurn(pendingTurn) { $0.status = .cancelled } }
        pendingTurn = nil
    }

    private func fail(_ failure: Error) {
        let message = (failure as? TranslationError) ?? .network
        let turnID = pendingTurn
        stop()
        if let turnID { updateTurn(turnID) { $0.status = .failed(message) } }
        error = message
    }

    private func updateTurn(_ id: UUID, _ update: (inout ConversationTranslationTurn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        update(&turns[index])
    }
}
