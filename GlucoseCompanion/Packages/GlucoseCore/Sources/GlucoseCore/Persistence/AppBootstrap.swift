import Foundation
import SwiftData

/// First-run seeding: ensures exactly one UserSettings row and the default
/// time-of-day blocks exist. Safe to call on every launch.
public enum AppBootstrap {
    @MainActor
    public static func ensureSeeded(in context: ModelContext) throws {
        var settingsDescriptor = FetchDescriptor<UserSettings>()
        settingsDescriptor.fetchLimit = 1
        if try context.fetch(settingsDescriptor).isEmpty {
            context.insert(UserSettings())
        }

        let profileDescriptor = FetchDescriptor<TimeOfDayProfile>()
        if try context.fetch(profileDescriptor).isEmpty {
            for block in TimeOfDayProfile.defaultBlocks() {
                context.insert(block)
            }
        }

        try context.save()
    }
}
