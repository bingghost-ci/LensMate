import AVFoundation
import SwiftUI

struct TextTranslationView: View {
    @ObservedObject var model: TranslationViewModel
    let isSelected: Bool
    var onClose: (() -> Void)? = nil
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @FocusState private var editingText: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source Language", selection: Binding(get: { model.source }, set: model.selectSource)) {
                        languages
                    }
                    Picker("Target Language", selection: Binding(get: { model.target }, set: model.selectTarget)) {
                        languages
                    }
                    Button { model.swapDirection() } label: {
                        Label("Swap Languages", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("translationSwap")
                }

                Section {
                    TextEditor(text: $model.inputText)
                        .frame(minHeight: 110)
                        .focused($editingText)
                        .accessibilityLabel(Text("Text to Translate"))
                        .accessibilityIdentifier("translationInput")
                    Button {
                        editingText = false
                        model.translate()
                    } label: {
                        Label("Translate Text", systemImage: "character.bubble")
                    }
                    .disabled(model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("translationSubmit")
                    if model.isTranslating { ProgressView("Translating…") }
                } header: {
                    Text("Text to Translate")
                } footer: {
                    Text("Up to 2,000 characters. Only this text and the selected languages are sent to Aliyun. Translation text is not saved to history.")
                }

                if let result = model.result {
                    Section("Original Text") {
                        Text(verbatim: result.input.text).textSelection(.enabled)
                    }
                    Section("Translated Text") {
                        Text(verbatim: result.text)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("translationResult")
                    }
                }

                Section {
                    Toggle("Read Translation Aloud", isOn: $model.automaticallySpeak)
                    Button { model.replay() } label: {
                        Label("Replay Last Translation", systemImage: "speaker.wave.2")
                    }
                    .disabled(model.result == nil || model.isTranslating)
                    Button { model.stop() } label: {
                        Label("Stop Translation and Speech", systemImage: "stop.circle")
                    }
                    .disabled(!model.isTranslating && !model.isSpeaking)
                    if model.isSpeaking { Text("Reading Translation…").foregroundStyle(.secondary) }
                } footer: {
                    Text("Speech uses an installed iPhone system voice and the current system audio output.")
                }
                if let error = model.error {
                    Section {
                        Text(L10n.text(error.message, locale: locale))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("translationError")
                    }
                }
            }
            .localizedNavigationTitle("Translation")
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) { Button("Done", action: onClose) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.suspend()
                        showingSettings = true
                    } label: {
                        Label("Translation Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingText = false }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                if scenePhase == .active && isSelected { model.activate() }
            }) {
                NavigationStack {
                    TranslationSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingSettings = false }
                            }
                        }
                }
            }
            .onAppear { if isSelected { model.activate() } }
            .onDisappear { model.suspend() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !showingSettings && isSelected { model.activate() }
                else { model.suspend() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   AVAudioSession.InterruptionType(rawValue: raw) == .began { model.stop() }
            }
        }
    }

    private var languages: some View {
        ForEach(TranslationLanguage.allCases) { language in
            Text(L10n.text(language.title, locale: locale)).tag(language)
        }
    }
}
