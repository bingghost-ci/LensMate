// LensMate - MainTabView.swift
// Main tab navigation: Voice Agent, Translation, History, Settings

import SwiftUI

struct MainTabView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @EnvironmentObject var conversationManager: ConversationManager

    // MARK: - State

    @State private var selectedTab: Tab = .voice
    @StateObject private var translation = ConversationTranslationViewModel()

    // MARK: - Tab Enum

    enum Tab: String, CaseIterable {
        case voice = "Voice"
        case translation = "Translation"
        case history = "History"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .voice: return "waveform.circle.fill"
            case .translation: return "character.bubble.fill"
            case .history: return "clock.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var selectedIcon: String {
            switch self {
            case .voice: return "waveform.circle.fill"
            case .translation: return "character.bubble.fill"
            case .history: return "clock.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: Binding(get: { selectedTab }, set: { tab in
            // Handoff before SwiftUI delivers appear/disappear callbacks in either order.
            if tab == .translation { translation.activate() }
            else if selectedTab == .translation { translation.leave() }
            selectedTab = tab
        })) {
            // Voice Agent Tab
            VoiceAgentView()
                .tabItem {
                    Label(LocalizedStringKey(Tab.voice.rawValue), systemImage: Tab.voice.icon)
                }
                .tag(Tab.voice)

            ConversationTranslationView(model: translation, isSelected: selectedTab == .translation)
                .tabItem {
                    Label(LocalizedStringKey(Tab.translation.rawValue), systemImage: Tab.translation.icon)
                }
                .tag(Tab.translation)

            // History Tab
            ConversationListView()
                .tabItem {
                    Label(LocalizedStringKey(Tab.history.rawValue), systemImage: Tab.history.icon)
                }
                .tag(Tab.history)

            // Settings Tab
            SettingsView()
                .tabItem {
                    Label(LocalizedStringKey(Tab.settings.rawValue), systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
        .onDisappear { translation.leave() }
        .onAppear {
            // Customize tab bar appearance for dark mode
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(white: 0.05, alpha: 0.95)

            // Normal state
            appearance.stackedLayoutAppearance.normal.iconColor = .gray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]

            // Selected state — emerald accent (matches Theme.accent)
            let accent = UIColor(red: 0.16, green: 0.85, blue: 0.47, alpha: 1)
            appearance.stackedLayoutAppearance.selected.iconColor = accent
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .environmentObject(ConversationManager.shared)
        .preferredColorScheme(.dark)
}
