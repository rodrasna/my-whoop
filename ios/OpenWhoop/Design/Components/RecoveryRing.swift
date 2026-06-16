import SwiftUI

// MARK: - ProgressRing
// Shared arc renderer for all rings — track, soft glow, colored stroke (official WHOOP feel).

struct ProgressRing: View {
    var progress: Double          // 0…1
    var color: Color
    var diameter: CGFloat
    var strokeWidth: CGFloat? = nil
    var showGlow: Bool = true
    var animated: Bool = true

    private var clamped: Double { min(1, max(0, progress)) }
    private var lineWidth: CGFloat { strokeWidth ?? WH.Ring.headerStroke(diameter: diameter) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(WH.Color.ringTrackOuter, lineWidth: lineWidth + 2)

            Circle()
                .stroke(WH.Color.ringTrack, lineWidth: lineWidth)

            if showGlow, clamped > 0.01 {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(color.opacity(WH.Ring.glowOpacity),
                            style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .blur(radius: WH.Ring.glowBlur)
                    .animation(animated ? .easeInOut(duration: 0.55) : nil, value: clamped)
            }

            if clamped > 0 {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(animated ? .easeInOut(duration: 0.55) : nil, value: clamped)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - RecoveryRing
// Circular progress ring showing a recovery percentage.

struct RecoveryRing: View {

    var percent: Double
    var size: CGFloat = 180
    var strokeWidth: CGFloat? = nil
    /// True during the first nights (<4): score uses population baseline, ring is dimmed.
    var provisional: Bool = false

    private var clamped: Double { min(100, max(0, percent)) }
    private var progress: Double { clamped / 100 }
    private var bandColor: Color {
        provisional ? WH.Color.calibrationAccent.opacity(0.85) : WH.Color.recoveryColor(forPercent: clamped)
    }
    private var lineWidth: CGFloat { strokeWidth ?? WH.Ring.heroStroke(diameter: size) }

    var body: some View {
        VStack(spacing: WH.Spacing.md) {
            ZStack {
                ProgressRing(progress: progress,
                             color: bandColor,
                             diameter: size,
                             strokeWidth: lineWidth,
                             showGlow: !provisional)
                Text("\(Int(clamped.rounded()))%")
                    .font(WH.Font.ringValue(size: size * 0.30, weight: .black))
                    .foregroundStyle(provisional ? WH.Color.textSecondary : WH.Color.textPrimary)
                    .monospacedDigit()
                    .frame(width: size * 0.62)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Text(provisional ? "RECUPERACIÓN · CALIBRANDO" : "RECUPERACIÓN")
                .font(WH.Font.ringLabel())
                .foregroundStyle(provisional ? WH.Color.calibrationAccent : WH.Color.textSecondary)
                .tracking(provisional ? 0.6 : 1.2)
                .multilineTextAlignment(.center)
                .padding(.top, WH.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - MiniRing
// Small outline progress ring (legacy helper; prefer TriRingHeader).

struct MiniRing: View {

    var progress: Double?
    var color: Color
    var centerText: String
    var label: String
    var size: CGFloat = 64
    var strokeWidth: CGFloat = 5.5

    private var clamped: Double { min(1, max(0, progress ?? 0)) }

    var body: some View {
        VStack(spacing: WH.Spacing.sm) {
            ZStack {
                ProgressRing(progress: progress ?? 0,
                             color: color,
                             diameter: size,
                             strokeWidth: strokeWidth,
                             showGlow: progress != nil)
                Text(centerText)
                    .font(WH.Font.ringValue(size: size * 0.28, weight: .bold))
                    .foregroundStyle(progress == nil ? WH.Color.textSecondary : WH.Color.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            Text(label.uppercased())
                .font(WH.Font.ringLabel(size: 9))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(0.8)
        }
    }
}

// MARK: - TriRingHeader
// Three header rings — Sleep, Recovery, Strain.

struct TriRingHeader: View {

    var sleepFraction: Double?
    var recoveryFraction: Double?
    var recoveryProvisional: Bool = false
    var strain: Double?
    var ringSize: CGFloat = 100
    var onSleepTap: (() -> Void)? = nil
    var onRecoveryTap: (() -> Void)? = nil
    var onStrainTap: (() -> Void)? = nil

    private var stroke: CGFloat { WH.Ring.headerStroke(diameter: ringSize) }

    var body: some View {
        HStack(alignment: .top, spacing: WH.Spacing.sm) {
            tappableRing(onTap: onSleepTap) {
                ringItem(progress: sleepFraction,
                         color: WH.Color.sleepBlue,
                         value: sleepFraction.map { "\(Int(($0 * 100).rounded()))%" },
                         label: "Sueño")
            }

            tappableRing(onTap: onRecoveryTap) {
                ringItem(progress: recoveryFraction,
                         color: recoveryRingColor,
                         value: recoveryFraction.map { "\(Int(($0 * 100).rounded()))%" },
                         label: recoveryProvisional ? "Recup. · cal." : "Recuperación",
                         dimmed: recoveryProvisional)
            }

            tappableRing(onTap: onStrainTap) {
                ringItem(progress: strain.map { $0 / 21 },
                         color: WH.Color.strainBlue,
                         value: strain.map { "\(WH.Ring.strainPercent($0))%" },
                         label: "Esfuerzo")
            }
        }
    }

    private var recoveryRingColor: Color {
        guard let r = recoveryFraction else { return WH.Color.textSecondary }
        if recoveryProvisional { return WH.Color.calibrationAccent }
        return WH.Color.recoveryColor(forPercent: r * 100)
    }

    private func ringItem(progress: Double?, color: Color, value: String?, label: String,
                          dimmed: Bool = false) -> some View {
        VStack(spacing: WH.Spacing.md) {
            ZStack {
                ProgressRing(progress: progress ?? 0,
                             color: color,
                             diameter: ringSize,
                             strokeWidth: stroke,
                             showGlow: progress != nil && !dimmed)
                Text(value ?? "—")
                    .font(WH.Font.ringValue(size: ringSize * 0.27, weight: .heavy))
                    .foregroundStyle(progress == nil ? WH.Color.textSecondary
                                     : (dimmed ? WH.Color.textSecondary : WH.Color.textPrimary))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 8)
            }
            .opacity(dimmed ? 0.88 : 1)

            Text(label.uppercased())
                .font(WH.Font.ringLabel())
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tappableRing<Content: View>(onTap: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        if let onTap {
            Button(action: onTap) { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }
}

// MARK: - StrainRing

struct StrainRing: View {
    var strain: Double
    var size: CGFloat = 200
    var strokeWidth: CGFloat? = nil
    /// When true, shows raw strain (e.g. tri-ring header). Detail screens use percentage.
    var showRawStrain: Bool = false

    private var clamped: Double { min(21, max(0, strain)) }
    private var progress: Double { clamped / 21 }
    private var lineWidth: CGFloat { strokeWidth ?? WH.Ring.heroStroke(diameter: size) }
    private var pct: Int { WH.Ring.strainPercent(clamped) }

    var body: some View {
        VStack(spacing: WH.Spacing.md) {
            ZStack {
                ProgressRing(progress: progress,
                             color: WH.Color.strainBlue,
                             diameter: size,
                             strokeWidth: lineWidth)
                if showRawStrain {
                    Text(String(format: "%.1f", clamped).replacingOccurrences(of: ".", with: ","))
                        .font(WH.Font.ringValue(size: size * 0.30, weight: .black))
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()
                        .frame(width: size * 0.62)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 2) {
                        Text("\(pct)%")
                            .font(WH.Font.ringValue(size: size * 0.30, weight: .black))
                            .foregroundStyle(WH.Color.textPrimary)
                            .monospacedDigit()
                        Text(String(format: "%.1f / 21", clamped).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: max(11, size * 0.075), weight: .semibold, design: .default))
                            .fontWidth(.condensed)
                            .foregroundStyle(WH.Color.textSecondary)
                            .monospacedDigit()
                    }
                    .frame(width: size * 0.62)
                    .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)

            Text("ESFUERZO")
                .font(WH.Font.ringLabel())
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.0)
                .padding(.top, WH.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SleepPerformanceRing

struct SleepPerformanceRing: View {
    var scorePercent: Double
    var size: CGFloat = 200
    var strokeWidth: CGFloat? = nil

    private var clamped: Double { min(100, max(0, scorePercent)) }
    private var lineWidth: CGFloat { strokeWidth ?? WH.Ring.heroStroke(diameter: size) }

    var body: some View {
        VStack(spacing: WH.Spacing.md) {
            ZStack {
                ProgressRing(progress: clamped / 100,
                             color: WH.Color.sleepBlue,
                             diameter: size,
                             strokeWidth: lineWidth)
                Text("\(Int(clamped.rounded()))%")
                    .font(WH.Font.ringValue(size: size * 0.30, weight: .black))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                    .frame(width: size * 0.62)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Text("RENDIMIENTO DEL SUEÑO")
                .font(WH.Font.ringLabel())
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(0.8)
                .multilineTextAlignment(.center)
                .padding(.top, WH.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview("Tri-ring header") {
    VStack(spacing: WH.Spacing.xl) {
        TriRingHeader(sleepFraction: 0.95, recoveryFraction: 0.20, strain: 2.8)
        TriRingHeader(sleepFraction: 0.73, recoveryFraction: 0.51, strain: 12.4)
        TriRingHeader(sleepFraction: nil, recoveryFraction: nil, strain: nil)
    }
    .padding(WH.Spacing.lg)
    .background(WH.Color.background)
}

#Preview("Recovery Ring — all bands") {
    HStack(spacing: WH.Spacing.xl) {
        RecoveryRing(percent: 82, size: 140)
        RecoveryRing(percent: 51, size: 140)
        RecoveryRing(percent: 18, size: 140)
    }
    .padding(WH.Spacing.xl)
    .background(WH.Color.background)
}
