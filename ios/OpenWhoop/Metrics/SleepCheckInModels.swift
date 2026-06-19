import Foundation

// MARK: - Sleep check-in (subjective morning questionnaire)

/// Cómo te sientes al levantarte (1 = muy mal … 5 = muy bien).
enum MorningFeeling: Int, Codable, CaseIterable, Identifiable {
    case veryBad = 1, bad = 2, ok = 3, good = 4, great = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .veryBad: return "Muy mal"
        case .bad:     return "Mal"
        case .ok:      return "Regular"
        case .good:    return "Bien"
        case .great:   return "Muy bien"
        }
    }

    var shortLabel: String {
        switch self {
        case .veryBad: return "😫"
        case .bad:     return "😕"
        case .ok:      return "😐"
        case .good:    return "🙂"
        case .great:   return "😊"
        }
    }
}

/// ¿Te costó conciliar el sueño?
enum SleepOnset: String, Codable, CaseIterable, Identifiable {
    case easy, normal, hard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy:   return "Me dormí con facilidad"
        case .normal: return "Normal"
        case .hard:   return "Me costó dormir"
        }
    }
}

/// Factores que el usuario marca como influyentes (positivos o negativos).
enum SleepFactor: String, Codable, CaseIterable, Identifiable {
    case heat, cold, alcohol, anxiety, lateSport, lateDinner, stayedUpLate, noise, nightWakings
    case goodTemperature, quiet, fellAsleepFast, feelRecovered

    var id: String { rawValue }

    var isPositive: Bool {
        switch self {
        case .goodTemperature, .quiet, .fellAsleepFast, .feelRecovered: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .heat:            return "Calor"
        case .cold:            return "Frío"
        case .alcohol:         return "Alcohol o sustancias"
        case .anxiety:         return "Ansiedad o preocupación"
        case .lateSport:       return "Deporte o actividad intensa tarde"
        case .lateDinner:      return "Cena tarde o pesada"
        case .stayedUpLate:    return "Te quedaste despierto tarde"
        case .noise:           return "Ruido"
        case .nightWakings:    return "Despertares durante la noche"
        case .goodTemperature: return "Temperatura agradable"
        case .quiet:           return "Ambiente silencioso"
        case .fellAsleepFast:  return "Conciliar el sueño rápido"
        case .feelRecovered:   return "Sensación de recuperación al despertar"
        }
    }

    static var negativeFactors: [SleepFactor] {
        allCases.filter { !$0.isPositive }
    }

    static var positiveFactors: [SleepFactor] {
        allCases.filter(\.isPositive)
    }
}

struct SleepCheckIn: Codable, Equatable {
    /// Día local de despertar (`yyyy-MM-dd`).
    let dayKey: String
    var morningFeeling: MorningFeeling
    var onset: SleepOnset
    var factors: Set<SleepFactor>
    var note: String?
    let savedAt: Date
    /// Instantánea de métricas de pulsera al guardar (para contrastar sensación vs datos).
    var recoveryPct: Double?
    var sleepEfficiencyPct: Double?
    /// Transcripción del comentario de voz (si se usó el micrófono).
    var voiceTranscript: String?
    /// Análisis estructurado del servidor (sensación + causas + contraste con pulsera).
    var analysis: SleepCheckInAnalysis?

    var negativeFactors: [SleepFactor] {
        factors.filter { !$0.isPositive }.sorted { $0.label < $1.label }
    }

    var positiveFactors: [SleepFactor] {
        factors.filter(\.isPositive).sorted { $0.label < $1.label }
    }

    /// Sensación en escala 0–100 para comparar con recovery en gráficos.
    var feelingScore: Double { Double(morningFeeling.rawValue) * 20.0 }

    /// Recovery en % (0–100) si está guardado como fracción 0–1.
    var recoveryPercent: Double? {
        guard let r = recoveryPct else { return nil }
        return r <= 1.0 ? r * 100.0 : r
    }
}

/// Resultado del análisis en servidor: parte subjetiva + contraste con métricas.
struct SleepCheckInAnalysis: Codable, Equatable {
    var sleepQualitySummary: String
    var perceivedCauses: [String]
    var subjectiveRecoveryPct: Double?
    var strapRecoveryPct: Double?
    /// aligned | strap_higher | body_higher | unknown
    var alignment: String
    var conclusion: String

    private enum CodingKeys: String, CodingKey {
        case sleepQualitySummary = "sleep_quality_summary"
        case perceivedCauses = "perceived_causes"
        case subjectiveRecoveryPct = "subjective_recovery_pct"
        case strapRecoveryPct = "strap_recovery_pct"
        case alignment
        case conclusion
    }
}

/// Respuesta de POST /v1/sleep-check-in/analyze — incluye campos sugeridos para guardar.
struct SleepCheckInAnalyzeResult: Codable, Equatable {
    var morningFeeling: MorningFeeling
    var onset: SleepOnset
    var factors: Set<SleepFactor>
    var voiceTranscript: String
    var analysis: SleepCheckInAnalysis

    private enum CodingKeys: String, CodingKey {
        case morningFeeling = "morning_feeling"
        case onset
        case factors
        case voiceTranscript = "voice_transcript"
        case analysis
        case sleepQualitySummary = "sleep_quality_summary"
        case perceivedCauses = "perceived_causes"
        case subjectiveRecoveryPct = "subjective_recovery_pct"
        case strapRecoveryPct = "strap_recovery_pct"
        case alignment
        case conclusion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let feelingRaw = try c.decode(Int.self, forKey: .morningFeeling)
        guard let feeling = MorningFeeling(rawValue: feelingRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .morningFeeling, in: c, debugDescription: "invalid feeling")
        }
        morningFeeling = feeling
        onset = try c.decode(SleepOnset.self, forKey: .onset)
        let factorRaw = try c.decode([String].self, forKey: .factors)
        factors = Set(factorRaw.compactMap(SleepFactor.init(rawValue:)))
        voiceTranscript = try c.decode(String.self, forKey: .voiceTranscript)
        analysis = SleepCheckInAnalysis(
            sleepQualitySummary: try c.decode(String.self, forKey: .sleepQualitySummary),
            perceivedCauses: try c.decode([String].self, forKey: .perceivedCauses),
            subjectiveRecoveryPct: try c.decodeIfPresent(Double.self, forKey: .subjectiveRecoveryPct),
            strapRecoveryPct: try c.decodeIfPresent(Double.self, forKey: .strapRecoveryPct),
            alignment: try c.decode(String.self, forKey: .alignment),
            conclusion: try c.decode(String.self, forKey: .conclusion)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(morningFeeling.rawValue, forKey: .morningFeeling)
        try c.encode(onset, forKey: .onset)
        try c.encode(factors.map(\.rawValue).sorted(), forKey: .factors)
        try c.encode(voiceTranscript, forKey: .voiceTranscript)
        try c.encode(analysis.sleepQualitySummary, forKey: .sleepQualitySummary)
        try c.encode(analysis.perceivedCauses, forKey: .perceivedCauses)
        try c.encodeIfPresent(analysis.subjectiveRecoveryPct, forKey: .subjectiveRecoveryPct)
        try c.encodeIfPresent(analysis.strapRecoveryPct, forKey: .strapRecoveryPct)
        try c.encode(analysis.alignment, forKey: .alignment)
        try c.encode(analysis.conclusion, forKey: .conclusion)
    }
}
