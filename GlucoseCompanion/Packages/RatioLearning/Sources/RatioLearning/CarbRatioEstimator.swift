import Foundation
import GlucoseCore

/// Learns a carb ratio (grams of carbohydrate covered per unit of insulin)
/// from historical meal events.
public enum CarbRatioEstimator {

    /// Only events whose pre-meal glucose was already close to target
    /// qualify: if the person was high or low beforehand, some of the bolus
    /// they took was doing correction work, not carb-covering work, and
    /// mixing that into a carbs-vs-units regression would bias the slope.
    /// Restricting to near-target starting points isolates the carb-only
    /// relationship at the cost of using fewer events -- an intentional
    /// trade favoring correctness over sample size.
    private static let preGlucoseToleranceMgdl: Double = 15.0

    /// - Parameters:
    ///   - events: All extracted meal events (confounded and clean). This
    ///     function does the confound/target filtering itself.
    ///   - targetMidpointMgdl: The person's target glucose (e.g. midpoint of
    ///     their target range), used both to select "was near target
    ///     beforehand" events.
    ///   - minimumDataPoints: Fewer qualifying events than this and we
    ///     refuse to produce a number at all -- see `RatioEstimate`.
    public static func estimate(
        events: [MealEvent],
        targetMidpointMgdl: Double,
        minimumDataPoints: Int = 8
    ) -> RatioEstimate? {
        let qualifying = events.filter { event in
            guard !event.isConfounded else { return false }
            guard let pre = event.preGlucoseMgdl else { return false }
            return abs(pre - targetMidpointMgdl) <= preGlucoseToleranceMgdl
        }

        guard qualifying.count >= minimumDataPoints else { return nil }

        let grams = qualifying.map(\.carbEntry.grams)
        let units = qualifying.map(\.bolusDose.units)

        // units = slope * grams, forced through the origin (see
        // LinearRegression for why); carb ratio is grams-per-unit, i.e. the
        // reciprocal of units-per-gram.
        guard let fit = LinearRegression.fitThroughOrigin(x: grams, y: units), fit.slope > 0 else {
            return nil
        }

        let gramsPerUnit = 1.0 / fit.slope
        return RatioEstimate(
            value: gramsPerUnit,
            dataPointCount: qualifying.count,
            rSquared: fit.rSquared,
            confidence: RatioEstimate.confidence(forDataPointCount: qualifying.count)
        )
    }
}
