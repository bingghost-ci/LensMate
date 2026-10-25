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
    @Published private(set) var recordingOptions = TranslationRecordingOptions()

    private let recognizer: any TranslationSpeechRecognizing
    private let translator: any TextTranslating
    private let recorder: any TranslationConversationRecording
    private let speech: any ConversationTranslationSpeaking
    private let router: any TranslationConversationRouting
    private let audio: TranslationAudioCoordinator
    private let credentials: @MainActor () throws -> TranslationCredentials
    private let options: @MainActor () -> TranslationRecordingOptions
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var active = false
    private var pendingTurn: UUID?
    private var playbackGeneration: UUID?

    init(recognizer: any TranslationSpeechRecognizing = AliyunSpeechRecognitionClient(),
         translator: any TextTranslating = AliyunTranslationClient(),
         recorder: (any TranslationConversationRecording)? = nil,
         speech: (any ConversationTranslationSpeaking)? = nil,
         router: (any TranslationConversationRouting)? = nil,
         audio: TranslationAudioCoordinator? = nil,
         credentials: (@MainActor () throws -> TranslationCredentials)? = nil,
         recordingOptions: (@MainActor () -> TranslationRecordingOptions)? = nil) {
        let routing = router ?? TranslationConversationAudioRouter()
        self.recognizer = recognizer
        self.translator = translator
        self.router = routing
        self.recorder = recorder ?? TranslationConversationRecorder(router: routing)
        self.speech = speech ?? TranslationSpeechService(configureAudio: {}, releaseAudio: { routing.release() })
        self.audio = audio ?? .shared
        self.credentials = credentials ?? { try TranslationConfiguration.shared.credentials() }
        self.options = recordingOptions ?? { TranslationConfiguration.shared.recordingOptions }
        self.speech.onCompletion = { [weak self] _ in self?.speechCompleted() }
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

    func canTapRecordingButton(for speaker: TranslationSpeaker) -> Bool {
        switch phase {
        case .idle, .paused, .waitingForPartner: return active
        case .recording(let current): return current == speaker
        default: return false
        }
    }

    func tapRecordingButton(for speaker: TranslationSpeaker) {
        guard canTapRecordingButton(for: speaker) else { return }
        if phase == .recording(speaker) { finishRecording() }
        else { beginSpeaking(speaker) }
    }

    func beginSpeaking(_ speaker: TranslationSpeaker) {
        guard active else { return }
        invalidate()
        do { _ = try credentials() }
        catch { fail(error); return }
        isConversationRunning = true
        phase = .preparing(speaker)
        let id = generation
        let recordingOptions = options()
        self.recordingOptions = recordingOptions
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
                let name = try await self.recorder.start(speaker: speaker, options: recordingOptions)
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
                    let translated = try await self.translateTranscript(original, source: source, target: target, credentials: credential, generation: id)
                    guard self.isCurrent(id), !Task.isCancelled else { return }
                    self.updateTurn(turn.id) { $0.translation = translated; $0.status = .complete }
                    self.pendingTurn = nil
                    self.task = nil
                    if speaker == .partner { self.play(turnID: turn.id) }
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
                let translated = try await self.translateTranscript(turn.original, source: turn.source, target: turn.target, credentials: self.credentials(), generation: id)
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.updateTurn(turnID) { $0.translation = translated; $0.status = .complete }
                self.pendingTurn = nil
                self.task = nil
                if turn.speaker == .partner { self.play(turnID: turnID) }
                else { self.phase = .waitingForPartner }
            } catch {
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.fail(error)
            }
        }
    }

    private func translateTranscript(_ text: String, source: TranslationLanguage, target: TranslationLanguage,
                                     credentials: TranslationCredentials, generation id: UUID) async throws -> String {
        var translated: [String] = []
        for chunk in TranslationTranscript.chunks(text) where !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard isCurrent(id), !Task.isCancelled else { throw CancellationError() }
            let input = TranslationInput(text: chunk, source: source, target: target)
            try input.validate()
            let result = try await translator.translate(input, credentials: credentials)
            guard isCurrent(id), !Task.isCancelled else { throw CancellationError() }
            translated.append(result)
        }
        guard !translated.isEmpty else { throw TranslationError.noSpeech }
        return translated.joined(separator: "\n")
    }

    func replay(_ turnID: UUID) { play(turnID: turnID) }

    private func play(turnID: UUID) {
        guard active, let turn = turns.first(where: { $0.id == turnID }), !turn.translation.isEmpty else { return }
        invalidate()
        isConversationRunning = true
        let id = generation
        phase = .preparing(turn.speaker)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.router.prepareOutput(for: turn.speaker)
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.phase = .speaking(turn.id)
                self.playbackGeneration = id
                self.task = nil
                try self.speech.speak(turn.translation, language: turn.target)
            } catch {
                guard self.isCurrent(id), !Task.isCancelled else { return }
                self.fail((error as? TranslationError) ?? .audioUnavailable)
            }
        }
    }

    private func speechCompleted() {
        guard let id = playbackGeneration, isCurrent(id), case .speaking = phase else { return }
        playbackGeneration = nil
        // Every new recording starts with a deliberate tap, including after partner playback.
        stop()
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
