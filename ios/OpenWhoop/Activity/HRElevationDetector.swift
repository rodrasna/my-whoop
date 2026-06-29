import Foundation

// MARK: - HRElevationDetector
// Detecta subidas de FC sostenidas sin exigir movimiento (despertar ~7:00, estrés, etc.).
// Complementa los entrenos del servidor hasta que `compute_day` vuelva a correr con la
// detección HR-only persistida.

enum HRElevationDetector {

  private static let minDurationS = 180.0
  private static let marginBpm = 15.0
  private static let peakMin = 125
  private static let mergeGapS = 90.0
  private static let overlapFrac = 0.35
  /// Subidas FC >2h se subdividen en segmentos (picos / valles) en lugar de descartarse.
  private static let maxDurationS = 120.0 * 60.0
  private static let subdividePeakMin = 130
  private static let subdividePeakGapS = 20.0 * 60.0
  private static let subdividePeakHalfWindowS = 25.0 * 60.0
  private static let subdivideValleyGapS = 10.0 * 60.0
  private static let subdivideValleyMarginBpm = 5.0

  static func detect(
    points: [TrendPoint],
    restingHr: Int?,
    deviceId: String
  ) -> [Workout] {
    let sorted = points.sorted { $0.date < $1.date }
    guard sorted.count >= 3 else { return [] }

    let interval = medianSampleInterval(sorted)
    let resting = Double(restingHr ?? estimateRestingHr(sorted))
    let floor = resting + marginBpm

    var elevated: [(ts: Int, bpm: Int)] = []
    for p in sorted {
      let bpm = Int(p.value.rounded())
      if Double(bpm) > floor {
        elevated.append((Int(p.date.timeIntervalSince1970), bpm))
      }
    }
    guard !elevated.isEmpty else { return [] }

    var runs: [(start: Int, end: Int)] = []
    var runStart = elevated[0].ts
    var prev = elevated[0].ts
    for sample in elevated.dropFirst() {
      if Double(sample.ts - prev) > mergeGapS {
        runs.append((runStart, prev))
        runStart = sample.ts
      }
      prev = sample.ts
    }
    runs.append((runStart, prev))

    return runs.flatMap { run -> [Workout] in
      let span = Double(run.end - run.start) + interval
      let subRuns: [(start: Int, end: Int)]
      if span > maxDurationS {
        subRuns = subdivideLongRun(
          run,
          elevated: elevated,
          floor: floor,
          interval: interval
        )
      } else {
        subRuns = [run]
      }
      return subRuns.compactMap { sub in
        makeWorkout(
          sub,
          elevated: elevated,
          interval: interval,
          deviceId: deviceId,
          suffix: span > maxDurationS ? "sub" : "hr"
        )
      }
    }
  }

  private static func subdivideLongRun(
    _ run: (start: Int, end: Int),
    elevated: [(ts: Int, bpm: Int)],
    floor: Double,
    interval: Double
  ) -> [(start: Int, end: Int)] {
    let window = elevated.filter { $0.ts >= run.start && $0.ts <= run.end }
    let peakSegments = hrPeakSegments(in: window, run: run)
    if peakSegments.count >= 2 { return peakSegments }

    let valleySplits = hrValleySplitPoints(in: window, floor: floor)
    if !valleySplits.isEmpty {
      return segmentsFromSplits(run.start, run.end, valleySplits)
    }
    return forceSplit(run.start, run.end)
  }

  private static func hrPeakSegments(
    in window: [(ts: Int, bpm: Int)],
    run: (start: Int, end: Int)
  ) -> [(start: Int, end: Int)] {
    guard window.count >= 5 else { return [] }
    var peakTs: [Int] = []
    for i in 2..<(window.count - 2) {
      let bpm = window[i].bpm
      guard bpm >= subdividePeakMin else { continue }
      if bpm >= window[i - 1].bpm && bpm >= window[i + 1].bpm
          && bpm >= window[i - 2].bpm && bpm >= window[i + 2].bpm {
        if let last = peakTs.last, window[i].ts - last < Int(subdividePeakGapS) { continue }
        peakTs.append(window[i].ts)
      }
    }
    return peakTs.map { peak in
      (
        start: max(run.start, peak - Int(subdividePeakHalfWindowS)),
        end: min(run.end, peak + Int(subdividePeakHalfWindowS))
      )
    }
  }

  private static func hrValleySplitPoints(
    in window: [(ts: Int, bpm: Int)],
    floor: Double
  ) -> [Int] {
    let valleyFloor = floor - subdivideValleyMarginBpm
    var splits: [Int] = []
    var valleyStart: Int?
    for sample in window {
      if Double(sample.bpm) < valleyFloor {
        if valleyStart == nil { valleyStart = sample.ts }
      } else if let start = valleyStart {
        if Double(sample.ts - start) >= subdivideValleyGapS {
          splits.append((start + sample.ts) / 2)
        }
        valleyStart = nil
      }
    }
    return splits
  }

  private static func segmentsFromSplits(
    _ start: Int,
    _ end: Int,
    _ splits: [Int]
  ) -> [(start: Int, end: Int)] {
    let bounds = [start] + splits.filter { $0 > start && $0 < end }.sorted() + [end]
    return zip(bounds, bounds.dropFirst()).map { ($0, $1) }
  }

  private static func forceSplit(_ start: Int, _ end: Int) -> [(start: Int, end: Int)] {
    let chunk = Int(maxDurationS)
    var segments: [(start: Int, end: Int)] = []
    var cursor = start
    while cursor < end {
      let chunkEnd = min(end, cursor + chunk)
      if chunkEnd - cursor < Int(minDurationS) { break }
      segments.append((cursor, chunkEnd))
      cursor = chunkEnd
    }
    return segments
  }

  private static func makeWorkout(
    _ run: (start: Int, end: Int),
    elevated: [(ts: Int, bpm: Int)],
    interval: Double,
    deviceId: String,
    suffix: String
  ) -> Workout? {
    let window = elevated.filter { $0.ts >= run.start && $0.ts <= run.end }
    guard !window.isEmpty else { return nil }
    let peak = window.map(\.bpm).max() ?? 0
    let span = Double(run.end - run.start) + interval
    guard span <= maxDurationS else { return nil }
    guard peak >= peakMin else { return nil }
    guard span >= minDurationS || (peak >= 140 && span >= 45) || (peak >= 150 && window.count >= 2) else {
      return nil
    }

    let avg = Double(window.map(\.bpm).reduce(0, +)) / Double(window.count)
    let startTs = run.start
    let endTs = run.end + Int(interval.rounded())
    return Workout(
      id: "\(deviceId)|\(suffix)|\(startTs)",
      deviceId: deviceId,
      startTs: startTs,
      endTs: endTs,
      avgHr: avg,
      peakHr: peak,
      strain: nil,
      kind: "hr_elevation",
      durationS: max(1, endTs - startTs),
      zoneTimePct: [:],
      avgHrrPct: nil,
      hrmax: nil,
      hrmaxSource: "",
      caloriesKcal: nil,
      caloriesKj: nil,
      motionVar: nil,
      hrPeaksPerMin: nil
    )
  }

  /// Picos locales pronunciados (despertar ~7:00) que no forman un tramo sostenido en datos muestreados.
  static func detectPeaks(
    points: [TrendPoint],
    restingHr: Int?,
    deviceId: String,
    existing: [Workout]
  ) -> [Workout] {
    let sorted = points.sorted { $0.date < $1.date }
    guard sorted.count >= 5 else { return [] }

    let interval = medianSampleInterval(sorted)
    let resting = Double(restingHr ?? estimateRestingHr(sorted))
    let floor = resting + 15
    let halfWindow = Int(max(interval * 4, 240).rounded())

    var peaks: [(ts: Int, bpm: Int)] = []
    for i in 1..<(sorted.count - 1) {
      let prev = Int(sorted[i - 1].value.rounded())
      let cur = Int(sorted[i].value.rounded())
      let next = Int(sorted[i + 1].value.rounded())
      guard cur >= prev, cur >= next else { continue }
      guard Double(cur) > floor, cur >= 130 else { continue }
      peaks.append((Int(sorted[i].date.timeIntervalSince1970), cur))
    }

    var workouts: [Workout] = []
    for peak in peaks.sorted(by: { $0.bpm > $1.bpm }) {
      let startTs = peak.ts - halfWindow
      let endTs = peak.ts + halfWindow
      let slice = sorted.filter {
        let ts = Int($0.date.timeIntervalSince1970)
        return ts >= startTs && ts <= endTs
      }
      let avg = slice.isEmpty ? Double(peak.bpm)
        : slice.map(\.value).reduce(0, +) / Double(slice.count)
      let w = Workout(
        id: "\(deviceId)|hr-peak|\(peak.ts)",
        deviceId: deviceId,
        startTs: startTs,
        endTs: endTs,
        avgHr: avg,
        peakHr: peak.bpm,
        strain: nil,
        kind: "hr_elevation",
        durationS: max(1, endTs - startTs),
        zoneTimePct: [:],
        avgHrrPct: nil,
        hrmax: nil,
        hrmaxSource: "",
        caloriesKcal: nil,
        caloriesKj: nil,
        motionVar: nil,
        hrPeaksPerMin: nil
      )
      let blocked = (existing + workouts).contains { overlaps($0, w) || isNear($0, w) }
      guard !blocked else { continue }
      workouts.append(w)
    }
    return workouts
  }

  /// Despertar matutino: pico de FC entre 5:00–10:30 local (p. ej. alarma / levantarse y volver a dormir).
  static func detectMorningWake(
    points: [TrendPoint],
    for day: Date,
    restingHr: Int?,
    deviceId: String,
    existing: [Workout]
  ) -> [Workout] {
    let cal = Calendar.current
    guard cal.isDate(day, inSameDayAs: Date()) || cal.startOfDay(for: day) < cal.startOfDay(for: Date()) else {
      return []
    }
    var startComps = cal.dateComponents([.year, .month, .day], from: day)
    startComps.hour = 5
    startComps.minute = 0
    var endComps = startComps
    endComps.hour = 10
    endComps.minute = 30
    guard let windowStart = cal.date(from: startComps),
          let windowEnd = cal.date(from: endComps) else { return [] }

    let morning = points.filter { $0.date >= windowStart && $0.date <= windowEnd }
    guard morning.count >= 3 else { return [] }

    let resting = Double(restingHr ?? estimateRestingHr(points))
    guard let peakPoint = morning.max(by: { $0.value < $1.value }) else { return [] }
    let peak = Int(peakPoint.value.rounded())
    guard peak >= max(115, Int(resting) + 30) else { return [] }

    let peakTs = Int(peakPoint.date.timeIntervalSince1970)
    let interval = medianSampleInterval(morning)
    let half = Int(max(interval * 6, 300).rounded())
    let startTs = peakTs - half
    let endTs = peakTs + half
    let slice = morning.filter {
      let ts = Int($0.date.timeIntervalSince1970)
      return ts >= startTs && ts <= endTs
    }
    let avg = slice.isEmpty ? Double(peak)
      : slice.map(\.value).reduce(0, +) / Double(slice.count)

    let w = Workout(
      id: "\(deviceId)|wake|\(peakTs)",
      deviceId: deviceId,
      startTs: startTs,
      endTs: endTs,
      avgHr: avg,
      peakHr: peak,
      strain: nil,
      kind: "hr_elevation",
      durationS: max(1, endTs - startTs),
      zoneTimePct: [:],
      avgHrrPct: nil,
      hrmax: nil,
      hrmaxSource: "",
      caloriesKcal: nil,
      caloriesKj: nil,
      motionVar: nil,
      hrPeaksPerMin: nil
    )
    let blocked = existing.contains { overlaps($0, w) || isNear($0, w) }
    return blocked ? [] : [w]
  }

  static func merge(into workouts: [Workout], supplements: [Workout]) -> [Workout] {
    let base = WorkoutDeduper.dedupe(workouts)
    let extra = supplements.filter { sup in
      !base.contains { WorkoutDeduper.overlaps($0, sup) }
    }
    return WorkoutDeduper.dedupe(base + extra)
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

  private static func estimateRestingHr(_ points: [TrendPoint]) -> Int {
    let bpms = points.map { Int($0.value.rounded()) }.sorted()
    let rank = max(1, Int(ceil(0.10 * Double(bpms.count))))
    return bpms[rank - 1]
  }

  private static func medianSampleInterval(_ points: [TrendPoint]) -> Double {
    guard points.count >= 2 else { return 1 }
    let deltas = zip(points, points.dropFirst()).map { $1.date.timeIntervalSince($0.date) }
      .filter { $0 > 0 && $0 < 120 }
    guard !deltas.isEmpty else { return 1 }
    return deltas.sorted()[deltas.count / 2]
  }
}
