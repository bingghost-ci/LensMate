import AVFoundation
import SwiftUI

struct ConversationTranslationView: View {
    @ObservedObject var model: ConversationTranslationViewModel
    let isSelected: Bool
    @ObservedObject private var configuration = TranslationConfiguration.shared
    @StateObject private var textModel = TranslationViewModel()
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case settings, text
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if model.turns.isEmpty { introduction }
                        ForEach(model.turns) { turn in turnCard(turn) }
                        Color.clear.frame(height: 1).id("conversationBottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .onChange(of: model.turns) { _, _ in
                    withAnimation { proxy.scrollTo("conversationBottom", anchor: .bottom) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { controls }
                .background(Color(.systemGroupedBackground))
            }
            .localizedNavigationTitle("Conversation Translation")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.isConversationRunning || model.phase != .idle && model.phase != .paused {
                        Button("End Conversation", systemImage: "stop.circle") { model.stop() }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Type Instead", systemImage: "keyboard") {
                            model.suspend()
                            textModel.selectSource(model.myLanguage)
                            textModel.selectTarget(model.partnerLanguage)
                            sheet = .text
                        }
                        Button("Translation Settings", systemImage: "gearshape") {
                            model.suspend()
                            sheet = .settings
                        }
                        Button("Clear Conversation", systemImage: "trash", role: .destructive) { model.clearConversation() }
                            .disabled(model.turns.isEmpty)
                    } label: {
                        Label("Translation Options", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $sheet, onDismiss: {
                textModel.suspend()
                if isSelected && scenePhase == .active { model.activate() }
            }) { selected in
                switch selected {
                case .settings:
                    NavigationStack {
                        TranslationSettingsView()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } }
                            }
                    }
                case .text:
                    TextTranslationView(model: textModel, isSelected: true, onClose: { sheet = nil })
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && isSelected && sheet == nil { model.activate() }
                else { model.suspend() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   AVAudioSession.InterruptionType(rawValue: raw) == .began { model.stop() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { model.audioDeviceChanged() }
            }
        }
    }

    private var introduction: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.wave.2").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("Take Turns Speaking").font(.title2.bold())
            Text("You speak through your glasses. Your partner speaks only when you open the phone microphone.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Label("Your words appear in both languages for your partner to read.", systemImage: "eyeglasses")
                Label("Tap to record your partner, then tap Stop. Their translation plays through your glasses.", systemImage: "mic")
            }
            .font(.subheadline)
            Text("Recordings are sent after each turn ends. This conversation is kept only in memory.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 8)
    }

    private func turnCard(_ turn: ConversationTranslationTurn) -> some View {
        let mine = turn.speaker == .me
        return HStack {
            if mine { Spacer(minLength: 28) }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text(turn.speaker.title, locale: locale)).fontWeight(.semibold)
                    Text(verbatim: L10n.text(turn.source.title, locale: locale) + " → " + L10n.text(turn.target.title, locale: locale))
                    Spacer(minLength: 0)
                }
                .font(.caption).opacity(0.7)
                if !turn.original.isEmpty {
                    Text(verbatim: turn.original).font(.body).textSelection(.enabled)
                    Divider().overlay(mine ? Color.white.opacity(0.2) : Color.clear)
                }
                if !turn.translation.isEmpty {
                    Text(verbatim: turn.translation).font(.title3.weight(.semibold)).textSelection(.enabled)
                }
                switch turn.status {
                case .recognizing: ProgressView("Recognizing Speech…").tint(mine ? .white : .primary)
                case .translating: ProgressView("Translating…").tint(mine ? .white : .primary)
                case .cancelled: Text("Turn Cancelled").font(.caption).opacity(0.7)
                case .failed:
                    Text("This turn could not be completed.").font(.caption)
                    if !turn.original.isEmpty {
                        Button("Retry Translation") { model.retryTranslation(turn.id) }
                    }
                case .complete:
                    Button { model.replay(turn.id) } label: {
                        Label(mine ? "Read to Partner" : "Replay in Glasses", systemImage: "speaker.wave.2")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .tint(mine ? .white : Theme.accent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(mine ? Color.white : Color.primary)
            .background(mine ? Color(white: 0.16) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            if !mine { Spacer(minLength: 28) }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            status
            if let error = model.error {
                Text(L10n.text(error.message, locale: locale))
                    .font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("conversationTranslationError")
            }
            HStack(spacing: 12) {
                languagePicker(mine: false)
                Button { model.swapLanguages() } label: { Image(systemName: "arrow.left.arrow.right") }
                    .accessibilityLabel("Swap Languages")
                languagePicker(mine: true)
            }
            actionButtons
            Text("Each turn is limited to 60 seconds. No recording during translation or playback.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(16)
        .background(.bar)
    }

    private var status: some View {
        VStack(spacing: 4) {
            switch model.phase {
            case .idle: Text("Ready to Start").fontWeight(.medium)
            case .paused: Text("Conversation Paused · Microphones Off").fontWeight(.medium)
            case .waitingForPartner: Text("Show Your Translation · Wait for Your Partner").fontWeight(.medium)
            case .preparing: ProgressView("Preparing Audio…")
            case .recording(let speaker):
                if speaker == .partner && (model.recordingProgress?.elapsed ?? 0) >= 60 {
                    Label("60 s Reached · Tap Stop to Translate", systemImage: "mic.slash")
                        .fontWeight(.semibold)
                } else {
                    Label(speaker == .me ? "Listening Through Glasses" : "Recording Your Partner", systemImage: speaker == .me ? "eyeglasses" : "mic.fill")
                        .foregroundStyle(.red).fontWeight(.semibold)
                }
                if !model.inputDevice.isEmpty { Text(verbatim: model.inputDevice).font(.caption).foregroundStyle(.secondary) }
                if speaker == .me {
                    Text("Translates after a \(Int(configuration.silenceDuration)) s pause")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Tap Stop when your partner finishes.").font(.caption).foregroundStyle(.secondary)
                }
                if let progress = model.recordingProgress {
                    Text("\(Int(progress.elapsed)) / 60 s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            case .recognizing: ProgressView("Recognizing Speech…")
            case .translating: ProgressView("Translating…")
            case .speaking: Label("Playing Translation · Microphones Off", systemImage: "speaker.wave.2.fill")
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func languagePicker(mine: Bool) -> some View {
        Menu {
            ForEach(TranslationLanguage.allCases) { language in
                Button(L10n.text(language.title, locale: locale)) {
                    if mine { model.selectMyLanguage(language) } else { model.selectPartnerLanguage(language) }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Text(mine ? "I Speak" : "Partner Speaks").font(.caption).foregroundStyle(.secondary)
                Label(L10n.text((mine ? model.myLanguage : model.partnerLanguage).title, locale: locale), systemImage: mine ? "eyeglasses" : "iphone")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder private var actionButtons: some View {
        switch model.phase {
        case .recording(let speaker):
            mainButton(speaker == .me ? "I'm Done Speaking" : "Stop Recording and Translate", icon: "stop.fill", tint: .red) { model.finishRecording() }
        case .preparing, .recognizing, .translating:
            mainButton("Cancel This Turn", icon: "xmark", tint: .secondary) { model.stop() }
        case .speaking:
            mainButton("Stop Playback", icon: "stop.fill", tint: Theme.accent) { model.stop() }
        case .waitingForPartner:
            mainButton("Let Partner Speak", icon: "mic.fill", tint: Theme.accent) { model.beginSpeaking(.partner) }
            Button("I Have More to Say") { model.beginSpeaking(.me) }.font(.subheadline)
        case .idle, .paused:
            mainButton("Start My Turn", icon: "eyeglasses", tint: Theme.accent) { model.beginSpeaking(.me) }
            Button("Let Partner Speak First") { model.beginSpeaking(.partner) }.font(.subheadline)
        }
    }

    private func mainButton(_ title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .clipShape(Capsule())
        .accessibilityIdentifier("conversationPrimaryAction")
    }
}
