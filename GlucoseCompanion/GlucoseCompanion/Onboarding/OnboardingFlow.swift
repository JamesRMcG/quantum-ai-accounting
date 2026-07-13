import SwiftUI
import SwiftData
import GlucoseCore

/// Steps a first-run user through disclaimer -> HealthKit permission ->
/// target range setup -> optional Dexcom connect.
///
/// This view does not dismiss itself: `RootView` watches
/// `hasAcceptedDisclaimer && isConfigured` on the singleton `UserSettings`
/// row via `@Query` and switches to `MainTabView` automatically once both are
/// true, which happens at the end of the target-range step. The Dexcom step
/// is purely optional and skippable since Dexcom Share is a backup path, not
/// a requirement -- HealthKit alone already covers the primary sync story.
struct OnboardingFlow: View {
    private enum Step {
        case disclaimer
        case healthKit
        case targetRange
        case dexcom
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    @State private var step: Step = .disclaimer

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .disclaimer:
                    DisclaimerView(onAccept: { step = .healthKit })

                case .healthKit:
                    HealthKitPermissionView(onContinue: { step = .targetRange })

                case .targetRange:
                    if let settings = settingsRows.first {
                        // `TargetRangeSettingsView`'s body is bare `Section`s
                        // (see its doc comment) so it can also be folded
                        // directly into `SettingsView`'s own `Form` --
                        // standalone here, it needs this `Form` wrapper.
                        Form {
                            TargetRangeSettingsView(settings: settings, onSave: {
                                step = .dexcom
                            })
                        }
                    } else {
                        ProgressView()
                    }

                case .dexcom:
                    DexcomLoginView(onSkip: { /* Onboarding is already complete by this point. */ })
                }
            }
            .navigationTitle(title(for: step))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func title(for step: Step) -> String {
        switch step {
        case .disclaimer: return ""
        case .healthKit: return "Health Access"
        case .targetRange: return "Target Range"
        case .dexcom: return "Connect Dexcom"
        }
    }
}

#Preview {
    OnboardingFlow()
        .modelContainer(for: UserSettings.self, inMemory: true)
        .environment(AppContainer())
}
