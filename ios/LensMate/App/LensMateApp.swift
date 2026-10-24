// LensMate - LensMateApp.swift
// App entry point with URL scheme handling for Meta AI registration

import SwiftUI
import MWDATCore

@main
struct LensMateApp: App {
    // MARK: - State Objects

    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var glassesManager = GlassesManager.shared
    @StateObject private var conversationManager = ConversationManager.shared

    // MARK: - App Storage

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(AppLanguage.defaultsKey) private var appLanguage: AppLanguage = .system
    @Environment(\.scenePhase) private var scenePhase
    @State private var systemLanguages = Locale.preferredLanguages

    // MARK: - Initialization

    init() {
        // Show timer/alarm notifications even when the app is in the foreground.
        NotificationForegroundPresenter.shared.register()
        // Create the location manager on the main thread + warm the cache for contextual notes.
        LocationHelper.shared.prewarm()

        // Move the model store OUT of Caches before anything touches the hub. iOS may purge
        // Caches under storage pressure, which silently deleted downloaded model weights (the app
        // then re-downloaded ~GBs at "connecting…" time). Must run before any HubClient exists.
        GemmaLocalService.bootstrapModelStore()

        // Initialize Meta Wearables SDK
        do {
            try Wearables.configure()
            print("[LensMateApp] Wearables SDK configured")
        } catch {
            print("[LensMateApp] Failed to configure Wearables SDK: \(error)")
        }
        print("[LensMateApp] Initialized")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                        .environmentObject(settingsManager)
                        .environmentObject(glassesManager)
                        .environmentObject(conversationManager)
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .environment(\.locale, Locale(identifier: appLanguage.resolvedIdentifier(preferredLanguages: systemLanguages)))
            .preferredColorScheme(.dark)
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                systemLanguages = Locale.preferredLanguages
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { systemLanguages = Locale.preferredLanguages }
            }
            .task {
                // Telemetry settings persist, but the sink lives in memory — without this a
                // relaunch (or a jetsam kill during a model switch) silently stopped pushing.
                MetricsCollector.shared.restoreAtLaunch()
            }
            .onOpenURL { url in
                handleURL(url)
            }
        }
    }

    // MARK: - URL Handling

    /// Handle URL callback from Meta AI app for glasses registration
    private func handleURL(_ url: URL) {
        print("[LensMateApp] Received URL: \(url)")

        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
                print("[LensMateApp] URL handled successfully")
            } catch {
                print("[LensMateApp] Error handling URL: \(error)")
            }
        }
    }
}
