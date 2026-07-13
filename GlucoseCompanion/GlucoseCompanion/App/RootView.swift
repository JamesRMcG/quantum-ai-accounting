import SwiftUI
import SwiftData
import GlucoseCore

/// Branches between onboarding and the main app based on `UserSettings`.
/// `AppBootstrap.ensureSeeded` runs asynchronously right after this view
/// first appears (see `GlucoseCompanionApp`), so there's a brief instant
/// before the singleton row exists -- handled below with a plain loading
/// state rather than assuming it's already there.
struct RootView: View {
    @Query private var settings: [UserSettings]

    var body: some View {
        Group {
            if let userSettings = settings.first {
                if userSettings.hasAcceptedDisclaimer {
                    MainTabView()
                } else {
                    OnboardingFlow()
                }
            } else {
                ProgressView()
            }
        }
    }
}
