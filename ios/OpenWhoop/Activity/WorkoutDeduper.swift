import Foundation

// MARK: - WorkoutDeduper
// Elimina entrenos solapados (p. ej. ejercicio real + elevación FC de 3h a la misma hora).

enum WorkoutDeduper {

    private static let overlapFrac = 0.35

    static func dedupe(_ workouts: [Workout]) -> [Workout] {
        guard workouts.count > 1 else { return workouts }
        let ranked = workouts.sorted { priority($0) > priority($1) }
        var kept: [Workout] = []
        for w in ranked {
            if kept.contains(where: { overlaps($0, w) }) { continue }
            kept.append(w)
        }
        return kept.sorted { $0.startTs > $1.startTs }
    }

    private static func priority(_ w: Workout) -> Double {
        let motion = (w.kind == "hr_elevation") ? 0.0 : 1.0
        let strain = w.strain ?? 0
        let z2 = w.zoneTimePct
            .filter { (2...5).contains($0.key) }
            .values
            .reduce(0, +) / 100.0
        return motion * 1_000 + strain * 10 + z2
    }

    static func overlaps(_ a: Workout, _ b: Workout) -> Bool {
        let oStart = max(a.startTs, b.startTs)
        let oEnd = min(a.endTs, b.endTs)
        guard oEnd > oStart else { return isNear(a, b) }
        let durA = Double(a.endTs - a.startTs)
        let durB = Double(b.endTs - b.startTs)
        guard durA > 0, durB > 0 else { return isNear(a, b) }
        let overlap = Double(oEnd - oStart)
        return overlap / durA >= overlapFrac || overlap / durB >= overlapFrac
    }

    private static func isNear(_ a: Workout, _ b: Workout) -> Bool {
        abs(a.startTs - b.startTs) < 20 * 60
    }
}
