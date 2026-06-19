import Foundation

// MARK: - Training coach report (GET/POST /v1/coach/day)

struct TrainingCoachTrainingContext: Codable, Equatable {
    let isRestDay: Bool
    let prvnReferenceDayKey: String?
    let userNote: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case source
        case isRestDay = "is_rest_day"
        case prvnReferenceDayKey = "prvn_reference_day_key"
        case userNote = "user_note"
    }
}

struct TrainingDayCoachReport: Codable, Equatable {
    let day: String
    let style: String?
    let activityType: String?
    let primaryWorkoutId: String?
    let summary: TrainingCoachSummary
    let blocks: [TrainingCoachBlock]
    let insights: [String]
    let dataQuality: String
    let inferredPlan: Bool
    let trainingContext: TrainingCoachTrainingContext?

    enum CodingKeys: String, CodingKey {
        case day, style, blocks, insights, summary
        case activityType = "activity_type"
        case primaryWorkoutId = "primary_workout_id"
        case dataQuality = "data_quality"
        case inferredPlan = "inferred_plan"
        case trainingContext = "training_context"
    }
}

struct TrainingCoachSummary: Codable, Equatable {
    let strainVsBaselinePct: Double?
    let avgHrVsBaselinePct: Double?
    let z4plusVsBaselinePct: Double?
    let verdict: String
    let recoveryPct: Double?
    let baselineSessionCount: Int?

    enum CodingKeys: String, CodingKey {
        case verdict
        case strainVsBaselinePct = "strain_vs_baseline_pct"
        case avgHrVsBaselinePct = "avg_hr_vs_baseline_pct"
        case z4plusVsBaselinePct = "z4plus_vs_baseline_pct"
        case recoveryPct = "recovery_pct"
        case baselineSessionCount = "baseline_session_count"
    }
}

struct TrainingCoachBlock: Codable, Equatable, Identifiable {
    var id: String { kind }
    let kind: String
    let label: String
    let metrics: TrainingCoachBlockMetrics
    let vsBaseline: TrainingCoachVsBaseline
    let insights: [String]

    enum CodingKeys: String, CodingKey {
        case kind, label, metrics, insights
        case vsBaseline = "vs_baseline"
    }
}

struct TrainingCoachBlockMetrics: Codable, Equatable {
    let durationS: Int?
    let avgHr: Double?
    let peakHr: Int?
    let strain: Double?
    let z2plusPct: Double?
    let z4plusPct: Double?

    enum CodingKeys: String, CodingKey {
        case strain
        case durationS = "duration_s"
        case avgHr = "avg_hr"
        case peakHr = "peak_hr"
        case z2plusPct = "z2plus_pct"
        case z4plusPct = "z4plus_pct"
    }
}

struct TrainingCoachVsBaseline: Codable, Equatable {
    let strainPct: Double?
    let avgHrPct: Double?
    let z4MinutesPct: Double?

    enum CodingKeys: String, CodingKey {
        case strainPct = "strain_pct"
        case avgHrPct = "avg_hr_pct"
        case z4MinutesPct = "z4_minutes_pct"
    }
}
