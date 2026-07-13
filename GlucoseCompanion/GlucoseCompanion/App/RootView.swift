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
                // Both must be true: accepting the disclaimer alone isn't
                // enough to unlock the app -- target range / max dose setup
                // (`isConfigured`) still gates the bolus suggestion feature,
                // and staying in OnboardingFlow until both are set keeps the
                // guided tour from being torn down partway through.
                if userSettings.hasAcceptedDisclaimer && userSettings.isConfigured {
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
