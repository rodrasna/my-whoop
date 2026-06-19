import Foundation

// MARK: - Spanish copy for deterministic coach insight IDs

enum TrainingCoachCopy {

    static func lines(for report: TrainingDayCoachReport) -> [String] {
        var out: [String] = []
        if report.inferredPlan {
            out.append("Plan del día no sincronizado — análisis basado solo en el bout detectado.")
        }
        if report.dataQuality == "thin_baseline" {
            out.append("Pocos entrenos comparables en el histórico; las comparaciones son orientativas.")
        }
        if let note = report.trainingContext?.userNote, !note.isEmpty {
            out.append("Nota: \(note)")
        }
        for id in report.insights {
            if let line = phrase(for: id, report: report) {
                out.append(line)
            }
        }
        if out.isEmpty, report.summary.verdict == "typical" {
            out.append("Rendimiento dentro de tu media reciente para sesiones similares.")
        }
        return out
    }

    static func headline(for report: TrainingDayCoachReport) -> String {
        switch report.summary.verdict {
        case "harder_than_usual": return "Más duro de lo habitual"
        case "easier_than_usual": return "Más ligero de lo habitual"
        case "no_workout": return "Sin entreno detectado"
        case "rest_day": return "Descanso planificado"
        default: return "Dentro de lo habitual"
        }
    }

    private static func phrase(for id: String, report: TrainingDayCoachReport) -> String? {
        let s = report.summary
        switch id {
        case "no_day_plan":
            return nil
        case "thin_baseline":
            return nil
        case "no_workout_detected":
            return "No hay bout de entreno este día para analizar."
        case "rest_day_planned":
            return "Descanso planificado — no se esperaba entreno."
        case "activity_on_rest_day":
            return "Entrenaste aunque marcaste el día como descanso."
        case "prvn_reference_day":
            if let ref = report.trainingContext?.prvnReferenceDayKey {
                return "Programa de referencia: PRVN del \(ref)."
            }
            return "Seguiste el programa de otro día PRVN."
        case "strain_above_baseline":
            let pct = s.strainVsBaselinePct.map { formatPct($0) } ?? "—"
            return "Strain \(pct) por encima de tu media en sesiones similares."
        case "strain_below_baseline":
            let pct = s.strainVsBaselinePct.map { formatPct(abs($0)) } ?? "—"
            return "Strain \(pct) por debajo de tu media en sesiones similares."
        case "avg_hr_above_baseline":
            let pct = s.avgHrVsBaselinePct.map { formatPct($0) } ?? "—"
            return "FC media \(pct) más alta que tu habitual en este tipo de sesión."
        case "time_in_zone_4_above_baseline":
            return "Más tiempo en zona 4–5 que en tus entrenos comparables — pacing exigente."
        case "hard_session_on_low_recovery":
            let rec = s.recoveryPct.map { String(format: "%.0f", $0) } ?? "—"
            return "Recuperación \(rec) % — sesión dura para el estado en el que llegaste."
        default:
            return nil
        }
    }

    private static func formatPct(_ v: Double) -> String {
        String(format: "%.0f%%", v).replacingOccurrences(of: ".", with: ",")
    }
}
