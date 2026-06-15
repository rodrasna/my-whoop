import SwiftUI

// MARK: - RecoveryRing
// Circular progress ring showing a recovery percentage.
// Ring stroke is colored by the recovery band (green/yellow/red).
// The integer % is rendered large+bold in the center with a caption label below.

struct RecoveryRing: View {

    /// Recovery percentage 0–100
    var percent: Double
    var size: CGFloat = 180
    var strokeWidth: CGFloat = 14

    // Clamp to valid range
    private var clamped: Double { min(100, max(0, percent)) }
    private var progress: Double { clamped / 100 }
    private var bandColor: Color { WH.Color.recoveryColor(forPercent: clamped) }

    var body: some View {
        ZStack {
            // --- Track (faint ring) ---
            Circle()
                .stroke(WH.Color.ringTrack, lineWidth: strokeWidth)

            // --- Filled arc ---
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    bandColor,
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)

            // --- Glow effect (subtle) ---
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    bandColor.opacity(0.25),
                    style: StrokeStyle(lineWidth: strokeWidth + 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 6)
                .animation(.easeInOut(duration: 0.6), value: progress)

            // --- Center content ---
            VStack(spacing: 2) {
                Text("\(Int(clamped.rounded()))")
                    .font(WH.Font.metricHero(size: size * 0.32))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()

                Text("RECOVERY")
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.5)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - MiniRing
// Small outline progress ring with a value in the center and a caption label below.
// Used by TriRingHeader to mirror the official app's Sleep / Recovery / Strain header.

struct MiniRing: View {

    /// Fill fraction 0…1 (nil → empty "calibrating" ring with an em-dash).
    var progress: Double?
    var color: Color
    var centerText: String
    var label: String
    var size: CGFloat = 64
    var strokeWidth: CGFloat = 5.5

    private var clamped: Double { min(1, max(0, progress ?? 0)) }

    var body: some View {
        VStack(spacing: WH.Spacing.xs) {
            ZStack {
                Circle()
                    .stroke(WH.Color.ringTrack, lineWidth: strokeWidth)

                if progress != nil {
                    Circle()
                        .trim(from: 0, to: clamped)
                        .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: clamped)
                }

                Text(centerText)
                    .font(.system(size: size * 0.28, weight: .bold, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(progress == nil ? WH.Color.textSecondary : WH.Color.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: size, height: size)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.0)
        }
    }
}

// MARK: - TriRingHeader
// The official app's top header: three small rings — Sleep, Recovery, Strain.
// Each value is optional; a nil value renders a faint "calibrating" ring.

struct TriRingHeader: View {

    /// Sleep performance 0…1 (calificación del sueño).
    var sleepFraction: Double?
    /// Recovery 0…1.
    var recoveryFraction: Double?
    /// Day strain 0…21.
    var strain: Double?
    var ringSize: CGFloat = 96
    var onSleepTap: (() -> Void)? = nil
    var onRecoveryTap: (() -> Void)? = nil
    var onStrainTap: (() -> Void)? = nil

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
                         color: recoveryFraction.map { WH.Color.recoveryColor(forPercent: $0 * 100) } ?? WH.Color.textSecondary,
                         value: recoveryFraction.map { "\(Int(($0 * 100).rounded()))%" },
                         label: "Recuperación")
            }

            tappableRing(onTap: onStrainTap) {
                ringItem(progress: strain.map { $0 / 21 },
                         color: WH.Color.strainBlue,
                         value: strain.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") },
                         label: "Esfuerzo")
            }
        }
    }

    /// One large ring (official-style): bold value centered inside the arc, uppercase
    /// label below. Stacked vertically so each ring reads as a prominent hero like the
    /// official app's top header, not a tiny inline chip.
    private func ringItem(progress: Double?, color: Color, value: String?, label: String) -> some View {
        VStack(spacing: WH.Spacing.xs) {
            ZStack {
                Circle()
                    .stroke(WH.Color.ringTrack, lineWidth: 7)
                if let p = progress {
                    Circle()
                        .trim(from: 0, to: min(1, max(0, p)))
                        .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: p)
                }
                Text(value ?? "—")
                    .font(.system(size: ringSize * 0.30, weight: .heavy, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(progress == nil ? WH.Color.textSecondary : WH.Color.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 4)
            }
            .frame(width: ringSize, height: ringSize)

            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
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
// Anillo hero de esfuerzo diario (0–21).

struct StrainRing: View {
    var strain: Double
    var size: CGFloat = 220
    var strokeWidth: CGFloat = 16

    private var clamped: Double { min(21, max(0, strain)) }
    private var progress: Double { clamped / 21 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(WH.Color.ringTrack, lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(WH.Color.strainBlue,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(String(format: "%.1f", clamped).replacingOccurrences(of: ".", with: ","))
                    .font(WH.Font.metricHero(size: size * 0.26))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                Text("ESFUERZO")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - SleepPerformanceRing
// Anillo hero de calificación de sueño (pantalla detalle / cabecera Sueño).

struct SleepPerformanceRing: View {
    var scorePercent: Double
    var size: CGFloat = 220
    var strokeWidth: CGFloat = 16

    private var clamped: Double { min(100, max(0, scorePercent)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(WH.Color.ringTrack, lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: clamped / 100)
                .stroke(WH.Color.sleepBlue,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text("\(Int(clamped.rounded()))%")
                    .font(WH.Font.metricHero(size: size * 0.26))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                Text("RENDIMIENTO DEL SUEÑO")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview("Tri-ring header") {
    VStack(spacing: WH.Spacing.xl) {
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
