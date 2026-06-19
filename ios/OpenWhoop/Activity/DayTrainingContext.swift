import Foundation

// MARK: - DayTrainingContext
// Entreno efectivo de un día calendario: plan manual + PRVN de referencia (puede ser otro día).

struct DayTrainingContext: Equatable {
    let calendarDayKey: String
    let resolved: ResolvedDayWorkout
    /// PRVN usado para movilidad y bloques por defecto (puede ≠ calendario).
    let effectivePrvnDay: PRVNDayProgram?
    let movementPatterns: Set<MobilityMovementPattern>
    let isRestDay: Bool
    /// Etiqueta corta para UI («Calendario», «Sáb 14 jun», «Descanso»).
    let sourceLabel: String

    var blocksDone: [ProgramBlockKind] { resolved.blocksDone }
    var note: String? { resolved.note }
}

enum PRVNReferenceMode: String, Codable, CaseIterable, Identifiable {
    case calendar
    case otherWeekDay
    case rest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calendar:     return "Programa del calendario"
        case .otherWeekDay: return "Otro día de la semana"
        case .rest:         return "Descanso / sin entreno"
        }
    }
}

extension WorkoutDayPlanStore {

    func trainingContext(
        dayKey: String,
        calendarDate: Date,
        workouts: [Workout],
        labelStore: ActivityLabelStore,
        prvnStore: PRVNProgramStore,
        isTrainingBout: (Workout) -> Bool,
        calendar: Calendar = .current
    ) -> DayTrainingContext {
        let calendarPrvn = prvnStore.program(for: calendarDate, calendar: calendar)
        let plan = plans[dayKey]

        let isRestDay = plan?.isRestDay == true
        let referenceKey = plan?.prvnReferenceDayKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let effectivePrvn: PRVNDayProgram? = {
            if isRestDay { return nil }
            if let referenceKey {
                return prvnStore.program(forDayKey: referenceKey) ?? calendarPrvn
            }
            return calendarPrvn
        }()

        let resolved = resolve(
            dayKey: dayKey,
            workouts: workouts,
            labelStore: labelStore,
            prvnDay: effectivePrvn,
            isTrainingBout: isTrainingBout
        )

        let blocksForPatterns: [ProgramBlockKind] = {
            if let plan, !plan.blocksDone.isEmpty { return plan.blocksDone }
            return resolved.blocksDone
        }()

        let patterns = PRVNMovementPatternParser.patterns(
            from: effectivePrvn,
            blocksDone: blocksForPatterns
        )

        let sourceLabel: String = {
            if isRestDay { return "Descanso" }
            if let referenceKey, referenceKey != dayKey,
               let date = MetricsRepository.parseLocalDay(referenceKey, calendar: calendar) {
                return prvnDayLabel(date: date, calendar: calendar)
            }
            if calendarPrvn != nil {
                return "Calendario · \(prvnDayLabel(date: calendarDate, calendar: calendar))"
            }
            return "Sin programa PRVN"
        }()

        return DayTrainingContext(
            calendarDayKey: dayKey,
            resolved: resolved,
            effectivePrvnDay: effectivePrvn,
            movementPatterns: patterns,
            isRestDay: isRestDay,
            sourceLabel: sourceLabel
        )
    }

    private func prvnDayLabel(date: Date, calendar: Calendar) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale(identifier: "es_ES")
        fmt.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return fmt.string(from: date).capitalized
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
