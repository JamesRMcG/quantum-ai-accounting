import Foundation
import GlucoseCore

/// Learns a correction (sensitivity) factor -- mg/dL of glucose drop per
/// unit of insulin -- from historical meal events where the person started
/// above target.
public enum CorrectionFactorEstimator {

    /// - Parameters:
    ///   - events: All extracted meal events (confounded and clean). This
    ///     function does the confound/target filtering itself.
    ///   - carbRatio: The already-learned (or user-set) carb ratio for this
    ///     block, used to subtract out the carb-covering portion of each
    ///     dose so only the correction component remains. If `nil` (no carb
    ///     ratio known yet for this block), the full dose is treated as
    ///     correction, which is only reasonable when the block's meals carry
    ///     little carb weight -- callers should prefer supplying a real
    ///     carb ratio when one is available.
    ///   - targetMidpointMgdl: The person's target glucose.
    ///   - minimumDataPoints: Fewer qualifying events than this and we
    ///     refuse to produce a number at all -- see `RatioEstimate`.
    public static func estimate(
        events: [MealEvent],
        carbRatio: Double?,
        targetMidpointMgdl: Double,
        minimumDataPoints: Int = 8
    ) -> RatioEstimate? {
        // Only events that started above target carry a meaningful
        // correction signal -- at or below target there was (by
        // definition) nothing to correct, so including them would just add
        // zero-or-noisy x values without any corresponding "correction
        // work" in the dose.
        let qualifying = events.filter { event in
            guard !event.isConfounded else { return false }
            guard let pre = event.preGlucoseMgdl else { return false }
            return pre > targetMidpointMgdl
        }

        guard qualifying.count >= minimumDataPoints else { return nil }

        let excessGlucose = qualifying.map { $0.preGlucoseMgdl! - targetMidpointMgdl }
        let correctionUnits = qualifying.map { event -> Double in
            let carbCoveringUnits = carbRatio.map { event.carbEntry.grams / $0 } ?? 0
            return event.bolusDose.units - carbCoveringUnits
        }

        // correctionUnits = slope * excessGlucose, forced through the
        // origin (see LinearRegression): zero glucose above target should
        // mean zero correction units, by definition of "correction".
        guard let fit = LinearRegression.fitThroughOrigin(x: excessGlucose, y: correctionUnits), fit.slope > 0 else {
            return nil
        }

        let mgdlPerUnit = 1.0 / fit.slope
        return RatioEstimate(
            value: mgdlPerUnit,
            dataPointCount: qualifying.count,
            rSquared: fit.rSquared,
            confidence: RatioEstimate.confidence(forDataPointCount: qualifying.count)
        )
    }
}
