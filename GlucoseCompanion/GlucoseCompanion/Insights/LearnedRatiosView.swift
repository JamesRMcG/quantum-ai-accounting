import SwiftUI
import SwiftData
import GlucoseCore
import RatioLearning

struct LearnedRatiosView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TimeOfDayProfile.startHour) private var profiles: [TimeOfDayProfile]
    @Query private var carbEntries: [CarbEntry]
    @Query private var insulinDoses: [InsulinDose]
    @Query private var glucoseReadings: [GlucoseReading]
    @Query private var settingsRows: [UserSettings]
    @Query private var workouts: [WorkoutSession]

    @State private var isRecalculating = false
    @State private var recalculationError: String?

    var body: some View {
        List {
            Section {
                Button(action: recalculate) {
                    HStack {
                        Label("Recalculate Learned Ratios", systemImage: "arrow.clockwise")
                        if isRecalculating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRecalculating || settingsRows.first == nil)

                if let recalculationError {
                    Text(recalculationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            ForEach(profiles, id: \.id) { profile in
                Section(profile.blockName) {
                    ProfileCard(profile: profile)
                }
            }
        }
        .navigationTitle("Insights")
    }

    private func recalculate() {
        guard let settings = settingsRows.first else { return }
        isRecalculating = true
        recalculationError = nil

        // Meals that overlap a workout can't be attributed to diet/insulin
        // alone -- exercise itself shifts glucose independent of the carb
        // ratio being learned, so those windows are excluded from the fit
        // rather than silently treated as clean data.
        let workoutWindows = workouts.map(\.interval)

        let snapshots = RatioLearningEngine.recompute(
            profiles: profiles,
            carbEntries: carbEntries,
            insulinDoses: insulinDoses,
            glucoseReadings: glucoseReadings,
            targetMidpointMgdl: settings.targetMidpointMgdl,
            excludeWindows: workoutWindows
        )

        // RatioLearningEngine never persists -- it returns brand-new snapshot
        // instances carrying the freshly computed values. We must copy just
        // those fields onto the live managed `TimeOfDayProfile` objects
        // (matched by `id`) and save ourselves; the snapshots themselves are
        // never inserted into the context, and `userOverride*` fields (user-
        // owned) are never touched here.
        for snapshot in snapshots {
            guard let live = profiles.first(where: { $0.id == snapshot.id }) else { continue }
            live.learnedCarbRatio = snapshot.learnedCarbRatio
            live.learnedCorrectionFactor = snapshot.learnedCorrectionFactor
            live.dataPointCount = snapshot.dataPointCount
            live.confidence = snapshot.confidence
            live.lastComputedAt = snapshot.lastComputedAt
        }

        do {
            try modelContext.save()
        } catch {
            recalculationError = "Couldn't save recalculated ratios: \(error.localizedDescription)"
        }

        isRecalculating = false
    }
}

private struct ProfileCard: View {
    let profile: TimeOfDayProfile

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    @State private var carbOverrideText: String = ""
    @State private var correctionOverrideText: String = ""

    private var glucoseUnit: GlucoseUnit { settingsRows.first?.glucoseUnit ?? .mgdl }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(hourLabel(profile.startHour)) - \(hourLabel(profile.endHour))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                confidenceBadge
            }

            valueRow(
                title: "Carb Ratio",
                learned: profile.learnedCarbRatio,
                override: profile.userOverrideCarbRatio,
                unitLabel: "g/u",
                format: { String(format: "%.1f", $0) }
            )

            valueRow(
                title: "Correction Factor",
                learned: profile.learnedCorrectionFactor,
                override: profile.userOverrideCorrectionFactor,
                unitLabel: GlucoseFormatting.perUnitLabel(glucoseUnit),
                format: { GlucoseFormatting.perUnitValueString(mgdlPerUnit: $0, unit: glucoseUnit) }
            )

            if profile.confidence == .insufficientData {
                Text("Not enough data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(profile.dataPointCount) meals \u{00B7} \(confidenceLabel(profile.confidence)) confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastComputedAt = profile.lastComputedAt {
                Text("Last recalculated \(lastComputedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Care team override")
                .font(.caption)
                .foregroundStyle(.secondary)

            overrideRow(
                placeholder: "Carb ratio override (g/u)",
                text: $carbOverrideText,
                hasOverride: profile.userOverrideCarbRatio != nil,
                onSet: applyCarbOverride,
                onClear: clearCarbOverride
            )

            overrideRow(
                placeholder: "Correction override (\(GlucoseFormatting.perUnitLabel(glucoseUnit)))",
                text: $correctionOverrideText,
                hasOverride: profile.userOverrideCorrectionFactor != nil,
                onSet: applyCorrectionOverride,
                onClear: clearCorrectionOverride
            )
        }
        .padding(.vertical, 4)
    }

    private var confidenceBadge: some View {
        Text(confidenceLabel(profile.confidence))
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(confidenceColor(profile.confidence).opacity(0.2), in: Capsule())
            .foregroundStyle(confidenceColor(profile.confidence))
    }

    /// Always names where the effective value came from, and -- whenever an
    /// override is active -- always shows the learned value alongside it
    /// (or explicitly notes there isn't one yet), never just the effective
    /// number. This is a hard transparency requirement: overrides silently
    /// masking a different learned value would be exactly the kind of hidden
    /// provenance this app must avoid.
    private func valueRow(
        title: String,
        learned: Double?,
        override: Double?,
        unitLabel: String,
        format: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                if let override {
                    Text("\(format(override)) \(unitLabel)")
                        .font(.subheadline.bold())
                    Text("override")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                } else if let learned {
                    Text("\(format(learned)) \(unitLabel)")
                        .font(.subheadline.bold())
                } else {
                    Text("Not set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if override != nil {
                if let learned {
                    Text("Learned value: \(format(learned)) \(unitLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No learned value yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func overrideRow(
        placeholder: String,
        text: Binding<String>,
        hasOverride: Bool,
        onSet: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
            Button("Set", action: onSet)
                .disabled(Double(text.wrappedValue) == nil)
            if hasOverride {
                Button("Clear", action: onClear)
                    .foregroundStyle(.red)
            }
        }
    }

    private func applyCarbOverride() {
        guard let value = Double(carbOverrideText), value > 0 else { return }
        profile.userOverrideCarbRatio = value
        carbOverrideText = ""
        save()
    }

    private func clearCarbOverride() {
        profile.userOverrideCarbRatio = nil
        carbOverrideText = ""
        save()
    }

    private func applyCorrectionOverride() {
        guard let value = Double(correctionOverrideText), value > 0 else { return }
        // The field is entered in whatever unit is currently displayed, but
        // the model always stores mg/dL per unit -- convert before saving.
        let mgdlPerUnit = glucoseUnit == .mmolL ? value * GlucoseFormatting.mgdlPerMmol : value
        profile.userOverrideCorrectionFactor = mgdlPerUnit
        correctionOverrideText = ""
        save()
    }

    private func clearCorrectionOverride() {
        profile.userOverrideCorrectionFactor = nil
        correctionOverrideText = ""
        save()
    }

    private func save() {
        try? modelContext.save()
    }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let period = normalized < 12 ? "AM" : "PM"
        var hour12 = normalized % 12
        if hour12 == 0 { hour12 = 12 }
        return "\(hour12) \(period)"
    }

    private func confidenceLabel(_ confidence: ConfidenceLevel) -> String {
        switch confidence {
        case .insufficientData: return "insufficient data"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    private func confidenceColor(_ confidence: ConfidenceLevel) -> Color {
        switch confidence {
        case .insufficientData: return .gray
        case .low: return .orange
        case .medium: return .blue
        case .high: return .green
        }
    }
}

#Preview {
    NavigationStack {
        LearnedRatiosView()
    }
}
