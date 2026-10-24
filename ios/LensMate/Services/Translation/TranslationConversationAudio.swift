import AVFoundation
import Foundation

@MainActor
protocol TranslationConversationRouting: AnyObject {
    func prepareInput(for speaker: TranslationSpeaker) async throws -> String
    func prepareOutput(for speaker: TranslationSpeaker) async throws
    func inputIsCurrent() -> Bool
    func release()
}

/// Exactly one input is selected. Bluetooth disappearance never falls back to the phone silently.
@MainActor
final class TranslationConversationAudioRouter: TranslationConversationRouting {
    private let session = AVAudioSession.sharedInstance()
    private var inputUID: String?
    private var bluetoothUID: String?
    private var ownsSession = false

    func prepareInput(for speaker: TranslationSpeaker) async throws -> String {
        try Task.checkCancellation()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
        ownsSession = true
        try session.setActive(true)
        let ports = session.availableInputs ?? []
        let port: AVAudioSessionPortDescription?
        if speaker == .me {
            port = ports.first { $0.portType == .bluetoothHFP && $0.uid == bluetoothUID }
                ?? ports.first { $0.portType == .bluetoothHFP && $0.uid == session.currentRoute.inputs.first?.uid }
                ?? ports.first { $0.portType == .bluetoothHFP }
        } else {
            port = ports.first { $0.portType == .builtInMic }
        }
        guard let port else { throw speaker == .me ? TranslationError.headsetUnavailable : .phoneMicrophoneUnavailable }
        try session.overrideOutputAudioPort(.none)
        try session.setPreferredInput(port)
        // The OS may finish changing the HFP route asynchronously. Verify before starting the tap.
        for _ in 0..<30 {
            try Task.checkCancellation()
            if session.currentRoute.inputs.contains(where: { $0.uid == port.uid }) {
                inputUID = port.uid
                if speaker == .me { bluetoothUID = port.uid }
                return port.portName
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw TranslationError.microphoneRouteChanged
    }

    func prepareOutput(for speaker: TranslationSpeaker) async throws {
        // Partner translations go to the wearer's headset; optional playback of our words goes to the phone.
        _ = try await prepareInput(for: speaker == .partner ? .me : .partner)
        if speaker == .partner {
            guard session.currentRoute.outputs.contains(where: { $0.portType == .bluetoothHFP }) else {
                throw TranslationError.headsetUnavailable
            }
        } else {
            try session.overrideOutputAudioPort(.speaker)
        }
        // There is no recording engine while speaking, even though HFP selects a paired input/output route.
    }

    func inputIsCurrent() -> Bool {
        guard let inputUID else { return false }
        return session.currentRoute.inputs.contains { $0.uid == inputUID }
    }

    func release() {
        inputUID = nil
        guard ownsSession else { return }
        ownsSession = false
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
protocol TranslationConversationRecording: AnyObject {
    var onProgress: ((TranslationRecordingProgress) -> Void)? { get set }
    var onAutomaticFinish: ((Result<RecordedTranslationSpeech, TranslationError>) -> Void)? { get set }
    func start(speaker: TranslationSpeaker, silenceDuration: TimeInterval) async throws -> String
    func finish() throws -> RecordedTranslationSpeech
    func cancel()
}

/// Bounded, in-memory PCM only. No temporary files and no audio upload while the microphone is open.
final class TranslationPCMBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pcm = Data()
    private var peakDecibels: Float = -160
    let sampleRate: Int
    private let maximumBytes: Int

    init(sampleRate: Int) {
        self.sampleRate = sampleRate
        maximumBytes = sampleRate * 2 * Int(TranslationSilenceDetector.maximumRecordingDuration)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
        guard count > 0, channelCount > 0 else { return }
        var data = Data(capacity: count * 2)
        var squareSum: Float = 0
        for frame in 0..<count {
            var sample: Float = 0
            for channel in 0..<channelCount {
                sample += buffer.format.isInterleaved ? channels[0][frame * channelCount + channel] : channels[channel][frame]
            }
            sample /= Float(channelCount)
            if !sample.isFinite { sample = 0 }
            squareSum += sample * sample
            var value = Int16(max(-1, min(1, sample)) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        let db = 20 * log10(max(0.00000001, sqrt(squareSum / Float(count))))
        lock.lock()
        pcm.append(data.prefix(max(0, maximumBytes - pcm.count)))
        peakDecibels = max(peakDecibels, db)
        lock.unlock()
    }

    func progress() -> (elapsed: TimeInterval, decibels: Float) {
        lock.lock()
        defer { lock.unlock() }
        let result = (Double(pcm.count) / Double(sampleRate * 2), peakDecibels)
        peakDecibels = -160
        return result
    }

    func recording() -> RecordedTranslationSpeech {
        lock.lock()
        defer { lock.unlock() }
        var wave = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wave.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count))
        wave.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        wave.append(Data("data".utf8)); append(UInt32(pcm.count)); wave.append(pcm)
        return .init(wav: wave, duration: Double(pcm.count) / Double(sampleRate * 2))
    }
}

@MainActor
final class TranslationConversationRecorder: TranslationConversationRecording {
    var onProgress: ((TranslationRecordingProgress) -> Void)?
    var onAutomaticFinish: ((Result<RecordedTranslationSpeech, TranslationError>) -> Void)?
    private let router: any TranslationConversationRouting
    private var engine: AVAudioEngine?
    private var buffer: TranslationPCMBuffer?
    private var timer: Task<Void, Never>?
    private var generation = UUID()
    private var detector = TranslationSilenceDetector(silenceDuration: 5)
    private var speaker = TranslationSpeaker.me
    private var lastAudioTime: TimeInterval = 0
    private var previousElapsed: TimeInterval = 0
    private var waitingForManualFinish = false

    init(router: any TranslationConversationRouting) { self.router = router }

    func start(speaker: TranslationSpeaker, silenceDuration: TimeInterval) async throws -> String {
        cancel()
        let id = generation
        guard await AVAudioApplication.requestRecordPermission() else { throw TranslationError.microphonePermission }
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        do {
            let name = try await router.prepareInput(for: speaker)
            try Task.checkCancellation()
            guard generation == id else { throw CancellationError() }
            let engine = AVAudioEngine()
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.commonFormat == .pcmFormatFloat32, format.channelCount > 0,
                  (8_000...48_000).contains(format.sampleRate) else { throw TranslationError.invalidRecording }
            let buffer = TranslationPCMBuffer(sampleRate: Int(format.sampleRate))
            if LMCatchException({
                node.installTap(onBus: 0, bufferSize: 1_024, format: format) { captured, _ in buffer.append(captured) }
            }) != nil { throw TranslationError.recordingFailed }
            self.engine = engine
            self.buffer = buffer
            self.speaker = speaker
            detector = TranslationSilenceDetector(silenceDuration: silenceDuration)
            engine.prepare()
            try engine.start()
            lastAudioTime = ProcessInfo.processInfo.systemUptime
            previousElapsed = 0
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self, self.generation == id else { return }
                    self.tick()
                }
            }
            return name
        } catch {
            if generation == id { cancel() }
            if error is CancellationError { throw error }
            throw (error as? TranslationError) ?? .recordingFailed
        }
    }

    private func tick() {
        guard let buffer else { return }
        guard router.inputIsCurrent() else { automaticFailure(.microphoneRouteChanged); return }
        let sample = buffer.progress()
        let now = ProcessInfo.processInfo.systemUptime
        if sample.elapsed > previousElapsed { lastAudioTime = now; previousElapsed = sample.elapsed }
        if now - lastAudioTime > 3 { automaticFailure(.recordingFailed); return }
        detector.observe(decibels: sample.decibels, elapsed: sample.elapsed)
        onProgress?(.init(elapsed: sample.elapsed, hasSpeech: detector.hasSpeech,
                          silenceRemaining: speaker == .me ? detector.remainingSilence(at: sample.elapsed) : nil))
        if !detector.hasSpeech && sample.elapsed >= TranslationSilenceDetector.noSpeechTimeout {
            automaticFailure(.noSpeech)
        } else if speaker == .partner && sample.elapsed >= TranslationSilenceDetector.maximumRecordingDuration {
            // Bound memory and recording time, but never submit the partner's speech automatically.
            engine?.stop()
            timer?.cancel(); timer = nil
            waitingForManualFinish = true
            router.release()
        } else if detector.shouldFinish(speaker: speaker, elapsed: sample.elapsed) {
            let callback = onAutomaticFinish
            do { callback?(.success(try finish())) }
            catch { callback?(.failure((error as? TranslationError) ?? .recordingFailed)) }
        }
    }

    func finish() throws -> RecordedTranslationSpeech {
        guard let buffer, engine != nil else { throw TranslationError.noSpeech }
        guard waitingForManualFinish || router.inputIsCurrent() else { cancel(); throw TranslationError.microphoneRouteChanged }
        let sample = buffer.progress()
        detector.observe(decibels: sample.decibels, elapsed: sample.elapsed)
        engine?.stop()
        let recording = buffer.recording()
        let hasSpeech = detector.hasSpeech
        cancel()
        guard hasSpeech, recording.duration >= 0.15 else { throw TranslationError.noSpeech }
        return recording
    }

    func cancel() {
        generation = UUID()
        timer?.cancel(); timer = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        buffer = nil
        waitingForManualFinish = false
        router.release()
    }

    private func automaticFailure(_ error: TranslationError) {
        let callback = onAutomaticFinish
        cancel()
        callback?(.failure(error))
    }
}
