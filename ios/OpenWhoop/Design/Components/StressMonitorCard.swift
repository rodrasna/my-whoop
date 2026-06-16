import SwiftUI

// MARK: - StressMonitorCard
// Placeholder honesto: el estrés diurno (HRV continuo) aún no está implementado.
// La recuperación nocturna sí usa VFC del sueño; esto es otra métrica (fase posterior).

struct StressMonitorCard: View {
  var completedNights: Int
  var requiredNights: Int = 4
  /// Epoch seconds for last night's sleep window (blue band on the chart).
  var sleepStartTs: Int?
  var sleepEndTs: Int?

  /// Noches con sueño importadas — informativo; no desbloquea estrés hasta tener pipeline HRV.
  private var hasSleepBaseline: Bool { completedNights >= requiredNights }

  var body: some View {
    VStack(alignment: .leading, spacing: WH.Spacing.sm) {
      HStack {
        Text("MONITOR DE ESTRÉS")
          .font(WH.Font.cardTitle)
          .foregroundStyle(WH.Color.textSecondary)
          .tracking(1.2)
        Spacer()
        Text("Próximamente")
          .font(WH.Font.caption)
          .foregroundStyle(WH.Color.textSecondary)
      }

      ZStack(alignment: .bottomLeading) {
        stressZoneBands
        sleepBandOverlay
        chartContent
      }
      .frame(height: 120)
      .clipShape(RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))

      statusBanner
    }
  }

  private var statusBanner: some View {
    VStack(alignment: .leading, spacing: WH.Spacing.sm) {
      Text("Estrés diurno aún no disponible")
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(WH.Color.textPrimary)

      Text(statusMessage)
        .font(WH.Font.caption)
        .foregroundStyle(WH.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(WH.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(WH.Color.surface2,
                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
  }

  private var statusMessage: String {
    if hasSleepBaseline {
      return "Ya tienes \(completedNights) noches de sueño en OpenWhoop. "
        + "La recuperación de la mañana usa esa VFC; el monitor de estrés (HRV continuo de día) "
        + "todavía no está conectado — verás la curva aquí cuando lo implementemos."
    }
    return "Necesitas unas \(requiredNights) noches de sueño sincronizadas para la base de referencia. "
      + "Llevas \(completedNights)/\(requiredNights). "
      + "Aun así, el gráfico de estrés diurno aún no está activo en esta versión."
  }

  private var stressZoneBands: some View {
    VStack(spacing: 0) {
      band(height: 40, color: WH.Color.stressHigh.opacity(0.12))
      band(height: 40, color: WH.Color.stressMedium.opacity(0.10))
      band(height: 40, color: WH.Color.stressLow.opacity(0.14))
    }
  }

  private func band(height: CGFloat, color: Color) -> some View {
    Rectangle().fill(color).frame(height: height)
  }

  @ViewBuilder
  private var sleepBandOverlay: some View {
    if let start = sleepStartTs, let end = sleepEndTs, end > start {
      GeometryReader { geo in
        let (x, w) = sleepBandFraction(start: start, end: end, width: geo.size.width)
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(WH.Color.sleepBlue.opacity(0.22))
            .frame(width: w, height: geo.size.height - 8)
            .offset(x: x, y: 4)
          Image(systemName: "moon.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WH.Color.sleepBlue.opacity(0.9))
            .offset(x: x + 6, y: 8)
        }
      }
    }
  }

  private var chartContent: some View {
    VStack {
      Spacer()
      HStack(spacing: WH.Spacing.sm) {
        Image(systemName: "waveform.path.ecg")
          .font(.system(size: 22, weight: .light))
          .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
        Text("Sin lecturas de estrés en esta versión")
          .font(WH.Font.caption)
          .foregroundStyle(WH.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(WH.Spacing.md)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  /// Map sleep window onto a 24h day chart (simplified: local calendar day of sleep end).
  private func sleepBandFraction(start: Int, end: Int, width: CGFloat) -> (x: CGFloat, w: CGFloat) {
    let cal = Calendar.current
    let endDate = Date(timeIntervalSince1970: TimeInterval(end))
    let dayStart = cal.startOfDay(for: endDate)
    let dayStartTs = dayStart.timeIntervalSince1970
    let daySpan: CGFloat = 86_400
    let xFrac = CGFloat(max(0, Double(start) - dayStartTs) / Double(daySpan))
    let wFrac = CGFloat(min(1, Double(end - start) / Double(daySpan)))
    return (xFrac * width, max(8, wFrac * width))
  }
}

#Preview {
  StressMonitorCard(completedNights: 2, sleepStartTs: 1_700_000_000, sleepEndTs: 1_700_026_000)
    .padding()
    .background(WH.Color.background)
}
