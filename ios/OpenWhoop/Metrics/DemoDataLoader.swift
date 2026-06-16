import Foundation
import WhoopStore

// MARK: - DemoDataLoader
// Inyecta métricas de vista previa en la caché local (GRDB) para poblar la UI sin depender
// del volcado BLE + servidor. Valores tomados de la app oficial WHOOP del usuario (jun 2026).
// NO son datos del strap en OpenWhoop — solo para diseño y comparación visual.

enum DemoDataLoader {

    static let activeKey = "com.openwhoop.demoPreviewActive"

    struct Payload {
        let daily: [DailyMetric]
        let sessions: [CachedSleepSession]
    }

    /// Métricas de referencia (app oficial, noche ~2:31 → 9:04, sáb 13 jun 2026).
    static func make(deviceId: String, referenceDate: Date = Date()) -> Payload {
        let cal = Calendar.current
        let utc = Calendar(identifier: .gregorian)
        var utcFmt = DateFormatter()
        utcFmt.calendar = utc
        utcFmt.timeZone = TimeZone(identifier: "UTC")
        utcFmt.dateFormat = "yyyy-MM-dd"

        let todayDay = utcFmt.string(from: referenceDate)

        // Sueño local: 02:31 → 09:04 del mismo día calendario.
        var startComps = cal.dateComponents([.year, .month, .day], from: referenceDate)
        startComps.hour = 2; startComps.minute = 31; startComps.second = 0
        var endComps = startComps
        endComps.hour = 9; endComps.minute = 4
        let startDate = cal.date(from: startComps) ?? referenceDate
        let endDate = cal.date(from: endComps) ?? referenceDate
        let startTs = Int(startDate.timeIntervalSince1970)
        let endTs = Int(endDate.timeIntervalSince1970)

        // Etapas (oficial): Despierto 32m, Ligero 191m, Profundo 112m, REM 57m → 6h dormido, 6h32 en cama
        let stagesJSON = makeStagesJSON(startTs: startTs,
                                        awakeMin: 32, lightMin: 191, deepMin: 112, remMin: 57)

        let lastNight = CachedSleepSession(
            startTs: startTs,
            endTs: endTs,
            efficiency: 0.82,      // calificación del sueño 82%
            restingHr: 64,
            avgHrv: 22,
            stagesJSON: stagesJSON
        )

        // Hoy (oficial): recovery 20%, strain 2.8, HRV 22, RHR 64, sueño 6h, eficiencia 92%
        let today = DailyMetric(
            day: todayDay,
            totalSleepMin: 360,
            efficiency: 0.92,
            deepMin: 112,
            remMin: 57,
            lightMin: 191,
            disturbances: 4,
            restingHr: 64,
            avgHrv: 22,
            recovery: 0.20,
            strain: 2.8,
            exerciseCount: 0,
            spo2Pct: 94,
            skinTempDevC: nil,
            respRateBpm: 14.2
        )

        // 7 días de esfuerzo (capturas: vie 2.0, sáb 2.8; días previos bajos)
        var weekDaily: [DailyMetric] = [today]
        let strainByOffset: [Int: Double] = [0: 2.8, -1: 2.0, -2: 1.2, -3: 0.8, -4: 0.5, -5: 0.3, -6: 0.0]
        for offset in -6...(-1) {
            guard let dayDate = cal.date(byAdding: .day, value: offset, to: referenceDate) else { continue }
            let day = utcFmt.string(from: dayDate)
            let strain = strainByOffset[offset] ?? 0
            weekDaily.append(DailyMetric(
                day: day,
                totalSleepMin: offset == -1 ? 350 : (offset >= -3 ? 340 : nil),
                efficiency: offset == -1 ? 0.88 : (offset == -2 ? 0.85 : nil),
                deepMin: offset >= -3 ? 105 : nil,
                remMin: offset >= -3 ? 52 : nil,
                lightMin: offset >= -3 ? 175 : nil,
                disturbances: nil,
                restingHr: offset >= -2 ? 63 : nil,
                avgHrv: offset >= -2 ? 24 : nil,
                recovery: offset == -1 ? 0.35 : (offset == -2 ? 0.42 : nil),
                strain: strain > 0 ? strain : nil,
                exerciseCount: 0,
                spo2Pct: offset >= -4 ? 93.5 + Double(offset + 4) * 0.15 : nil,
                skinTempDevC: offset >= -3 ? Double(offset + 3) * 0.08 : nil,
                respRateBpm: offset >= -4 ? 14.0 + Double(-offset) * 0.1 : nil
            ))
        }

        weekDaily.sort { $0.day < $1.day }

        // 7 noches para gráfico horario + regularidad (leve variación en hora de acostarse).
        var sessions: [CachedSleepSession] = []
        for offset in -6...0 {
            guard let dayDate = cal.date(byAdding: .day, value: offset, to: referenceDate) else { continue }
            var startComps = cal.dateComponents([.year, .month, .day], from: dayDate)
            let bedMin = 31 + (offset + 6) * 8 - (offset == 0 ? 0 : (offset % 3) * 12)
            startComps.hour = 2; startComps.minute = max(5, min(55, bedMin))
            var endComps = startComps
            endComps.hour = 9; endComps.minute = 4
            let sDate = cal.date(from: startComps) ?? dayDate
            let eDate = cal.date(from: endComps) ?? dayDate
            let sTs = Int(sDate.timeIntervalSince1970)
            let eTs = Int(eDate.timeIntervalSince1970)
            let eff = offset == 0 ? 0.82 : (0.78 + Double(offset + 6) * 0.01)
            sessions.append(CachedSleepSession(
                startTs: sTs, endTs: eTs,
                efficiency: min(0.95, eff),
                restingHr: 63 + (offset + 6) % 3,
                avgHrv: 20 + Double(offset + 6),
                stagesJSON: offset == 0 ? stagesJSON : "[]"
            ))
        }
        sessions.sort { $0.startTs < $1.startTs }

        return Payload(daily: weekDaily, sessions: sessions)
    }

    /// Entrenos de vista previa (solo simulador): bouts genéricos detectados, SIN `kind`.
    /// Reflejan la realidad: la banda detecta el esfuerzo pero no nombra el deporte. Aparecen
    /// como "Toca para asignar" hasta que el usuario los etiqueta (igual que en uso real).
    static func demoWorkouts(deviceId: String, referenceDate: Date = Date()) -> [Workout] {
        let cal = Calendar.current
        func at(_ dayOffset: Int, hour: Int, minute: Int) -> Date {
            var c = cal.dateComponents([.year, .month, .day], from: referenceDate)
            c.hour = hour; c.minute = minute
            let base = cal.date(from: c) ?? referenceDate
            return cal.date(byAdding: .day, value: dayOffset, to: base) ?? base
        }
        let cfZones: [Int: Double] = [0: 4, 1: 9, 2: 18, 3: 24, 4: 28, 5: 17]
        let runZones: [Int: Double] = [0: 5, 1: 16, 2: 36, 3: 33, 4: 8, 5: 2]
        // Rutina matutina: FC sube al despertar pero sin esfuerzo acumulado (falso positivo típico).
        let morningZones: [Int: Double] = [0: 42, 1: 38, 2: 14, 3: 4, 4: 2, 5: 0]
        let morningRoutine: [Workout] = (0...4).map { offset in
            makeWorkout(deviceId: deviceId, start: at(-offset, hour: 7, minute: 5 + offset),
                        durationMin: 12, kind: nil, avgHr: 98, peakHr: 190, strain: 2.1,
                        zones: morningZones, kcal: 45, motionVar: 0.08, hrPeaks: 0.22)
        }
        // CrossFit: movimiento bursty + muchos picos de FC; carrera: estable.
        return morningRoutine + [
            makeWorkout(deviceId: deviceId, start: at(0, hour: 13, minute: 30), durationMin: 52, kind: nil, avgHr: 148, peakHr: 182, strain: 12.4, zones: cfZones, kcal: 520, motionVar: 0.62, hrPeaks: 0.48),
            makeWorkout(deviceId: deviceId, start: at(-2, hour: 19, minute: 30), durationMin: 47, kind: nil, avgHr: 152, peakHr: 186, strain: 13.1, zones: cfZones, kcal: 498, motionVar: 0.58, hrPeaks: 0.52),
            makeWorkout(deviceId: deviceId, start: at(-3, hour: 8, minute: 15),  durationMin: 34, kind: nil, avgHr: 139, peakHr: 168, strain: 8.6,  zones: runZones, kcal: 360, motionVar: 0.14, hrPeaks: 0.06),
            makeWorkout(deviceId: deviceId, start: at(-5, hour: 18, minute: 50), durationMin: 61, kind: nil, avgHr: 150, peakHr: 188, strain: 14.0, zones: cfZones, kcal: 612, motionVar: 0.66, hrPeaks: 0.50),
        ]
    }

    /// Muestras de referencia CrossFit (solo para verificar la sugerencia k-NN en simulador).
    /// IDs sintéticos: NO corresponden a entrenos visibles, solo pueblan el dataset.
    static func demoCrossfitSamples(referenceDate: Date = Date()) -> [ActivitySample] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: referenceDate)
        let cfZones: [Double] = [4, 9, 18, 24, 28, 17]
        let variants: [(hour: Int, dur: Double, avg: Double, peak: Double)] = [
            (7, 50, 149, 183), (8, 47, 151, 185), (7, 55, 148, 181), (19, 46, 152, 187), (8, 52, 150, 184),
        ]
        return variants.enumerated().map { idx, v in
            ActivitySample(
                workoutId: "demo-seed-\(idx)",
                label: ActivityType.crossfit.rawValue,
                recordedTs: Int(referenceDate.timeIntervalSince1970),
                startHour: v.hour,
                weekday: weekday,
                durationMin: v.dur,
                avgHr: v.avg,
                peakHr: v.peak,
                avgHrrPct: 62,
                zonePct: cfZones,
                motionVar: 0.60,
                hrPeaksPerMin: 0.50
            )
        }
    }

    private static func makeWorkout(deviceId: String, start: Date, durationMin: Int, kind: String?,
                                    avgHr: Double, peakHr: Int, strain: Double,
                                    zones: [Int: Double], kcal: Double,
                                    motionVar: Double?, hrPeaks: Double?) -> Workout {
        let startTs = Int(start.timeIntervalSince1970)
        let durationS = durationMin * 60
        return Workout(
            id: "\(deviceId)|\(startTs)",
            deviceId: deviceId,
            startTs: startTs,
            endTs: startTs + durationS,
            avgHr: avgHr,
            peakHr: peakHr,
            strain: strain,
            kind: kind,
            durationS: durationS,
            zoneTimePct: zones,
            avgHrrPct: 62,
            hrmax: 190,
            hrmaxSource: "tanaka",
            caloriesKcal: kcal,
            caloriesKj: kcal * 4.184,
            motionVar: motionVar,
            hrPeaksPerMin: hrPeaks
        )
    }

    private static func makeStagesJSON(startTs: Int,
                                       awakeMin: Double, lightMin: Double,
                                       deepMin: Double, remMin: Double) -> String {
        var segments: [[String: Any]] = []
        var t = Double(startTs)
        func append(_ stage: String, minutes: Double) {
            guard minutes > 0 else { return }
            let dur = minutes * 60
            segments.append(["start": t, "end": t + dur, "stage": stage])
            t += dur
        }
        append("wake", minutes: 10)
        append("light", minutes: lightMin * 0.35)
        append("deep", minutes: deepMin * 0.4)
        append("light", minutes: lightMin * 0.25)
        append("rem", minutes: remMin * 0.5)
        append("light", minutes: lightMin * 0.4)
        append("deep", minutes: deepMin * 0.6)
        append("rem", minutes: remMin * 0.5)
        append("light", minutes: lightMin * 0.25)
        append("wake", minutes: awakeMin - 10)
        guard let data = try? JSONSerialization.data(withJSONObject: segments),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Serie sintética de FC para gráficos en vista previa (sin servidor).
    static func demoHrSeries(fromEpoch: Int, toEpoch: Int, maxPoints: Int) -> [TrendPoint] {
        guard toEpoch > fromEpoch, maxPoints > 1 else { return [] }
        let span = toEpoch - fromEpoch
        let step = max(30, span / maxPoints)
        var points: [TrendPoint] = []
        var ts = fromEpoch
        while ts <= toEpoch {
            let hour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(ts)))
            let minute = Calendar.current.component(.minute, from: Date(timeIntervalSince1970: TimeInterval(ts)))
            // Línea base ~62–68 lpm; pico matutino ~7:00–7:15; esfuerzo tarde ~13:30–14:30.
            var bpm = 64.0 + sin(Double(ts) / 900.0) * 4
            if hour == 7 && minute >= 0 && minute <= 20 {
                let spike = exp(-pow(Double(minute - 8) / 4.0, 2))
                bpm += spike * 120
            } else if hour == 13 && minute >= 20 && minute <= 90 {
                bpm += 55 + sin(Double(minute) / 8.0) * 18
            } else if hour >= 18 && hour <= 20 {
                bpm += 40 + sin(Double(minute) / 6.0) * 12
            }
            points.append(TrendPoint(
                id: "\(ts)",
                date: Date(timeIntervalSince1970: TimeInterval(ts)),
                value: min(195, max(52, bpm))
            ))
            ts += step
        }
        return points
    }
}
