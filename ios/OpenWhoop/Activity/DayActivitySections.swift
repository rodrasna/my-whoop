import Foundation

// MARK: - DayActivitySections
// Agrupa las actividades de un día para la lista de Actividad.
// Los entrenos van arriba; las señales de FC sin movimiento quedan aparte y con contexto.

enum DayActivitySection: String, CaseIterable, Identifiable {
    case workouts
    case life
    case dailyRhythm
    case hrSignals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workouts:     return "ENTRENOS"
        case .life:         return "ACTIVIDAD COTIDIANA"
        case .dailyRhythm:  return "RITMO DEL DÍA"
        case .hrSignals:    return "SEÑALES DE FC"
        }
    }

    var subtitle: String {
        switch self {
        case .workouts:
            return "Movimiento + FC o confirmado por ti — cuentan en tu resumen"
        case .life:
            return "Etiquetado como vida diaria — no cuenta como entreno"
        case .dailyRhythm:
            return "Despertar, desplazamientos u horarios que se repiten"
        case .hrSignals:
            return "Subidas de FC sin movimiento claro — revisa el gráfico"
        }
    }

    /// Solo las señales de FC ruidosas empiezan colapsadas; el resto debe verse al abrir el día.
    var collapsedByDefault: Bool {
        self == .hrSignals
    }
}

enum DayActivitySections {

  struct Grouped: Equatable {
    let section: DayActivitySection
    let items: [Workout]
  }

  /// Clasifica cada bout en una sola sección (prioridad: entreno confirmado > vida > ritmo > señal FC).
  static func classify(
    _ workout: Workout,
    assessment: BoutAssessment,
    isConfirmed: Bool,
    isDismissed: Bool,
    hasActivityOnlyLabel: Bool
  ) -> DayActivitySection {
    if isDismissed || hasActivityOnlyLabel { return .life }
    if isConfirmed { return .workouts }

    switch assessment.category {
    case .likelyWorkout:
      return .workouts
    case .lifeActivity:
      return .life
    case .dailyRoutine:
      return .dailyRhythm
        case .hrSpike:
            return .hrSignals
    }
  }

  static func group(
    workouts: [Workout],
    assess: (Workout) -> BoutAssessment,
    isConfirmed: (Workout) -> Bool,
    isDismissed: (Workout) -> Bool,
    hasActivityOnlyLabel: (Workout) -> Bool
  ) -> [Grouped] {
    var buckets: [DayActivitySection: [Workout]] = [:]
    for w in workouts {
      let section = classify(
        w,
        assessment: assess(w),
        isConfirmed: isConfirmed(w),
        isDismissed: isDismissed(w),
        hasActivityOnlyLabel: hasActivityOnlyLabel(w)
      )
      buckets[section, default: []].append(w)
    }
    return DayActivitySection.allCases.compactMap { section in
      guard let items = buckets[section], !items.isEmpty else { return nil }
      let sorted = items.sorted { $0.startTs > $1.startTs }
      return Grouped(section: section, items: sorted)
    }
  }
}
