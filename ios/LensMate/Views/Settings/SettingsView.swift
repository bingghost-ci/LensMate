// LensMate - SettingsView.swift
// Main settings menu with navigation to configuration panels

import SwiftUI

struct SettingsView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @AppStorage(AppLanguage.defaultsKey) private var appLanguage: AppLanguage = .system

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("App Language", selection: $appLanguage) {
                        Text("Follow System").tag(AppLanguage.system)
                        Text(verbatim: "English").tag(AppLanguage.english)
                        Text(verbatim: "简体中文").tag(AppLanguage.chinese)
                    }
                    .accessibilityIdentifier("appLanguagePicker")
                } header: {
                    Text("Language")
                } footer: {
                    Text("Follow System uses your device's primary language. Unsupported languages use English.")
                }

                Section {
                    NavigationLink {
                        TranslationSettingsView()
                    } label: {
                        Label("Translation Settings", systemImage: "character.bubble")
                    }
                }

                // AI Backend Section
                Section {
                    NavigationLink {
                        AIBackendSettingsView()
                    } label: {
                        HStack {
                            Label("AI Backend", systemImage: "cpu")
                            Spacer()
                            Text(LocalizedStringKey(settingsManager.settings.aiBackend.displayName))
                                .foregroundColor(.secondary)
                            if !settingsManager.settings.isCurrentBackendConfigured {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    NavigationLink {
                        WebSearchSettingsView()
                    } label: {
                        HStack {
                            Label("Web Search", systemImage: "magnifyingglass")
                            Spacer()
                            Text(settingsManager.settings.tavilyAPIKey.isEmpty ? LocalizedStringKey("DuckDuckGo") : LocalizedStringKey("Tavily"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Only show for Gemini Live (OpenClaw has its own system prompt & memories)
                    if settingsManager.settings.aiBackend == .geminiLive {
                        NavigationLink {
                            AdditionalInstructionsView()
                        } label: {
                            Label("Custom Instructions", systemImage: "text.quote")
                        }

                        NavigationLink {
                            MemoriesView()
                        } label: {
                            HStack {
                                Label("Memories", systemImage: "brain")
                                Spacer()
                                Text("\(settingsManager.settings.memories.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("AI")
                }

                // Hardware Section
                Section {
                    NavigationLink {
                        GlassesSettingsView()
                    } label: {
                        HStack {
                            Label("Glasses", systemImage: "eyeglasses")
                            Spacer()
                            if glassesManager.isRegistered {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Hardware")
                }

                // Voice Section
                Section {
                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        HStack {
                            Label("Voice Control", systemImage: "mic.fill")
                            Spacer()
                            if settingsManager.settings.wakeWordEnabled {
                                Text(settingsManager.settings.wakeWord)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Off")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Voice")
                }

                // Advanced Section
                Section {
                    NavigationLink {
                        DocumentsSettingsView()
                    } label: {
                        Label("My Documents", systemImage: "books.vertical")
                    }

                    NavigationLink {
                        TelemetrySettingsView()
                    } label: {
                        Label("Telemetry", systemImage: "chart.line.uptrend.xyaxis")
                    }

                    Toggle(isOn: $settingsManager.settings.autoReconnect) {
                        Label("Auto-Reconnect", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Toggle(isOn: $settingsManager.settings.showTranscripts) {
                        Label("Show Transcripts", systemImage: "text.bubble")
                    }
                } header: {
                    Text("Advanced")
                }

                // About Section
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("\(Config.appVersion) (\(Config.buildNumber))")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/bingghost-ci/LensMate")!) {
                        Label("LensMate Repository", systemImage: "link")
                    }

                    Link(destination: URL(string: "https://github.com/openclaw/openclaw")!) {
                        Label("Get OpenClaw", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("LensMate personal build. Third-party license notices are included in the source project.")
                }
            }
            .localizedNavigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
}
