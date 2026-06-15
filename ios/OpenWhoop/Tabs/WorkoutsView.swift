import SwiftUI
import WhoopStore

// MARK: - WorkoutsView (pestaña Actividad)
// Pantalla de Esfuerzo al estilo WHOOP: anillo de strain del día arriba, acceso destacado a
// CrossFit, tendencia semanal de esfuerzo, y la lista de entrenos auto-detectados debajo.
// Los datos derivados vienen del servidor; las etiquetas de actividad se guardan en local.

enum ActivityRoute: Hashable { case crossfit, suggestDemo }

struct WorkoutsView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @StateObject private var labelStore = ActivityLabelStore()

    // MARK: - State

    @State private var workouts: [Workout] = []
    @State private var weekRows: [DailyMetric] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var path: [ActivityRoute] = []

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                if isLoading {
                    loadingView
                } else {
                    listContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ActivityRoute.self) { route in
                switch route {
                case .crossfit:
                    CrossFitView(workouts: workouts, labelStore: labelStore)
                case .suggestDemo:
                    if let w = workouts.first {
                        WorkoutDetailView(workout: w, labelStore: labelStore)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await reload()
            // Screenshot helper: -deepLink crossfit abre la pantalla CrossFit al arrancar.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-deepLink"), i + 1 < args.count {
                switch args[i + 1] {
                case "crossfit":
                    path = [.crossfit]
                case "suggest":
                    // Verificación: siembra muestras de referencia y abre un entreno sin clasificar.
                    labelStore.seedSamples(DemoDataLoader.demoCrossfitSamples())
                    path = [.suggestDemo]
                default:
                    break
                }
            }
        }
        .refreshable { await reload() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView().tint(WH.Color.textSecondary)
            Text("Cargando actividad…")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WH.Spacing.lg) {
                ScreenHeader("Actividad")

                if let err = errorMessage {
                    errorBanner(err).padding(.horizontal, WH.Spacing.md)
                }

                strainRingSection
                crossFitCard

                if !weekRows.isEmpty || todayStrain != nil {
                    WeeklyBarChart(
                        title: "Esfuerzo",
                        points: WeeklyChartBuilder.last7Days(from: weekRows) { $0.strain },
                        maxValue: 21,
                        barColor: WH.Color.strainBlue
                    )
                    .padding(.horizontal, WH.Spacing.md)
                }

                workoutsSection
            }
            .padding(.bottom, WH.Spacing.xl)
        }
        .background(WH.Color.background)
    }

    // MARK: - Strain ring (esfuerzo del día)

    private var strainRingSection: some View {
        VStack(spacing: WH.Spacing.sm) {
            StrainRing(strain: todayStrain ?? 0, size: 200)
                .opacity(todayStrain == nil ? 0.45 : 1)
            if todayStrain == nil {
                Text("Esfuerzo de hoy aún sin calcular")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, WH.Spacing.sm)
    }

    // MARK: - CrossFit hero card

    private var crossFitCard: some View {
        let cf = workouts.filter { labelStore.effectiveType(for: $0) == .crossfit }
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekCount = cf.filter { Date(timeIntervalSince1970: TimeInterval($0.startTs)) >= weekStart }.count
        let last = cf.max(by: { $0.startTs < $1.startTs })

        return NavigationLink(value: ActivityRoute.crossfit) {
            HStack(spacing: WH.Spacing.md) {
                ZStack {
                    Circle().fill(WH.Color.strainBlue.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: ActivityType.crossfit.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(WH.Color.strainBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("CrossFit")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text(crossFitSubtitle(weekCount: weekCount, last: last))
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
            }
            .padding(WH.Spacing.md)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            .padding(.horizontal, WH.Spacing.md)
        }
        .buttonStyle(.plain)
    }

    private func crossFitSubtitle(weekCount: Int, last: Workout?) -> String {
        if let last {
            let when = relativeDay(last.startTs)
            let base = weekCount > 0 ? "\(weekCount) esta semana" : "Sin sesiones esta semana"
            return "\(base) · última \(when)"
        }
        return "Clasifica un entreno como CrossFit para empezar"
    }

    // MARK: - Workouts list

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("ENTRENOS DETECTADOS")
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
                .padding(.horizontal, WH.Spacing.md)

            if workouts.isEmpty {
                emptyState
            } else {
                summaryStrip
                workoutList
                autoDetectNote
            }
        }
    }

    private var summaryStrip: some View {
        let count = workouts.count
        let totalMin = workouts.reduce(0) { $0 + $1.durationS } / 60
        return HStack(spacing: WH.Spacing.lg) {
            summaryItem(value: "\(count)", unit: count == 1 ? "entreno" : "entrenos", label: "ÚLTIMOS 30 DÍAS")
            summaryItem(value: "\(totalMin)", unit: "min", label: "TIEMPO TOTAL")
            Spacer()
        }
        .padding(.horizontal, WH.Spacing.md)
    }

    private func summaryItem(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(WH.Font.metricMedium(size: 26))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(0.8)
        }
    }

    private var autoDetectNote: some View {
        HStack(spacing: WH.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
            Text("Detectados automáticamente a partir de tu frecuencia cardíaca. Toca uno para clasificarlo.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, WH.Spacing.md)
    }

    private var workoutList: some View {
        VStack(spacing: 1) {
            ForEach(workouts) { workout in
                NavigationLink(destination: WorkoutDetailView(workout: workout, labelStore: labelStore)) {
                    workoutRow(workout)
                }
                .buttonStyle(.plain)
            }
        }
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .padding(.horizontal, WH.Spacing.md)
    }

    private func workoutRow(_ w: Workout) -> some View {
        let type = labelStore.effectiveType(for: w)
        return HStack(spacing: WH.Spacing.sm) {
            Image(systemName: type?.symbol ?? "bolt.fill")
                .font(.system(size: 15))
                .foregroundStyle(type != nil ? WH.Color.strainBlue : WH.Color.textSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(type?.displayName ?? rowDate(w.startTs))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text(type != nil ? "\(rowDate(w.startTs)) · \(rowTime(w.startTs))" : rowTime(w.startTs))
                    .font(.system(size: 12))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            .frame(width: 120, alignment: .leading)

            Text(formatDuration(w.durationS))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(WH.Color.textSecondary)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f", w.avgHr))
                    .font(.system(size: 14, weight: .semibold))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                Text("lpm")
                    .font(.system(size: 10))
                    .foregroundStyle(WH.Color.textSecondary)
            }
            .frame(width: 40, alignment: .trailing)

            strainBadge(w.strain)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.sm)
    }

    private func strainBadge(_ strain: Double?) -> some View {
        Group {
            if let s = strain {
                Text(String(format: "%.1f", s))
                    .font(.system(size: 13, weight: .bold))
                    .fontWidth(.condensed)
                    .foregroundStyle(WH.Color.strainBlue)
                    .monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(WH.Color.strainBlue.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
            } else {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundStyle(WH.Color.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
            }
        }
        .frame(width: 48, alignment: .center)
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(spacing: WH.Spacing.sm) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(WH.Color.textSecondary)
            Text("Aún no se detectan entrenamientos")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Text("Los entrenamientos se detectan automáticamente a partir de tu frecuencia cardíaca. Desliza hacia abajo para actualizar.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WH.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WH.Spacing.xxl)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WH.Color.recoveryYellow)
            Text(message)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    // MARK: - Data

    private var todayStrain: Double? {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        return weekRows.first { $0.day == today }?.strain ?? metrics.today?.strain
    }

    private func reload() async {
        errorMessage = nil
        let (from, to) = dateRange(daysBack: 30)
        workouts = await metrics.workouts(from: from, to: to)
        let (weekFrom, weekTo) = dateRange(daysBack: 7)
        weekRows = await metrics.daily(fromDay: weekFrom, toDay: weekTo)
        if isLoading { isLoading = false }
    }

    private func dateRange(daysBack: Int) -> (from: String, to: String) {
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let from = cal.date(byAdding: .day, value: -daysBack, to: today) ?? today
        return (fmt.string(from: from), fmt.string(from: today))
    }

    // MARK: - Formatting

    private func rowDate(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "EEE d/M"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func rowTime(_ ts: Int) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func relativeDay(_ ts: Int) -> String {
        let cal = Calendar.current
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        if cal.isDateInToday(d) { return "hoy" }
        if cal.isDateInYesterday(d) { return "ayer" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "EEE d/M"
        return fmt.string(from: d)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let totalMin = seconds / 60
        let h = totalMin / 60
        let m = totalMin % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Preview

#Preview("Actividad — vacío") {
    WorkoutsView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
}
