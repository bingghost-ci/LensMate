import SwiftUI

struct TranslationSettingsView: View {
    @ObservedObject private var configuration = TranslationConfiguration.shared
    @Environment(\.locale) private var locale
    @State private var region: TranslationRegion?
    @State private var key = ""
    @State private var hasSavedKey = false
    @State private var error: TranslationError?
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Maximum Recording Duration") {
                    Text("\(Int(configuration.maximumRecordingDuration)) s").monospacedDigit()
                }
                Slider(value: Binding(get: { configuration.maximumRecordingDuration }, set: configuration.setMaximumRecordingDuration),
                       in: TranslationRecordingOptions.durationRange, step: 30) {
                    Text("Maximum Recording Duration")
                }
                .accessibilityIdentifier("translationRecordingLimit")
                Toggle("End My Turn After a Pause", isOn: Binding(
                    get: { configuration.automaticallyEndsMyTurn }, set: configuration.setAutomaticallyEndsMyTurn))
                    .accessibilityIdentifier("translationAutomaticFinish")
                LabeledContent("My Pause Duration") {
                    Text("\(Int(configuration.silenceDuration)) s").monospacedDigit()
                }
                Slider(value: Binding(get: { configuration.silenceDuration }, set: configuration.setSilenceDuration), in: 1...10, step: 1) {
                    Text("My Pause Duration")
                }
                .accessibilityIdentifier("translationSilenceDuration")
                .disabled(!configuration.automaticallyEndsMyTurn)
            } header: {
                Text("Conversation Rhythm")
            } footer: {
                Text("Tap either language's button to start and stop recording. Set a limit from 30 to 300 seconds. At the limit, recording stops and waits for your tap to translate. Optionally end your own turn after a pause (default: 5 seconds); this also submits at the limit. Your partner always taps to finish. Changes are saved automatically.")
            }
            Section {
                Picker("Aliyun Region", selection: $region) {
                    Text("Choose a Region").tag(TranslationRegion?.none)
                    ForEach(TranslationRegion.allCases) { region in
                        Text(L10n.text(region.title, locale: locale)).tag(Optional(region))
                    }
                }
                .accessibilityIdentifier("translationRegion")
                if let region {
                    LabeledContent("Endpoint") { Text(verbatim: region.endpoint.host ?? "").font(.caption) }
                }
                LabeledContent("Speech Recognition Model") { Text(verbatim: AliyunSpeechRecognitionClient.model) }
                LabeledContent("Translation Model") { Text(verbatim: AliyunTranslationClient.model) }
            } footer: {
                Text("Use a Model Studio API key from the selected region with access to qwen-mt-flash and qwen3-asr-flash. Beijing and Singapore keys are not interchangeable.")
            }

            Section {
                SecureField("Translation API Key", text: Binding(get: { key }, set: {
                    key = $0
                    saved = false
                    error = nil
                }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("translationAPIKey")
                Text(hasSavedKey ? "An API key is saved for this region. Leave the field empty to keep it." : "No API key is saved for this region.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save Translation Settings") { save() }
                    .disabled(region == nil)
                if hasSavedKey {
                    Button("Remove Saved API Key", role: .destructive) { removeKey() }
                }
            } footer: {
                Text("API keys are stored only in this iPhone's Keychain. They are never saved to ordinary settings files. Saving does not test the connection.")
            }
            if saved { Text("Translation settings saved. Translate a short text to check the connection.").foregroundStyle(.secondary) }
            if let error { Text(L10n.text(error.message, locale: locale)).foregroundStyle(.red) }
        }
        .localizedNavigationTitle("Translation Settings")
        .onAppear {
            region = configuration.region
            refreshKeyStatus()
        }
        .onChange(of: region) { _, _ in
            key = ""
            saved = false
            error = nil
            refreshKeyStatus()
        }
        .onDisappear { key = "" }
    }

    private func refreshKeyStatus() {
        hasSavedKey = false
        guard let region else { return }
        do { hasSavedKey = try configuration.hasKey(for: region) }
        catch { self.error = (error as? TranslationError) ?? .credentialRead }
    }

    private func save() {
        guard let region else { return }
        error = nil
        saved = false
        do {
            try configuration.save(region: region, key: key)
            key = ""
            saved = true
            refreshKeyStatus()
        } catch { self.error = (error as? TranslationError) ?? .credentialSave }
    }

    private func removeKey() {
        guard let region else { return }
        error = nil
        saved = false
        do {
            try configuration.removeKey(for: region)
            key = ""
            refreshKeyStatus()
        } catch { self.error = (error as? TranslationError) ?? .credentialDelete }
    }
}
