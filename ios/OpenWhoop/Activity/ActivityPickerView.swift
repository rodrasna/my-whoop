import SwiftUI

// MARK: - ActivityPickerView
// Hoja modal para asignar tipo de entreno o marcar como actividad cotidiana (sin contar como entreno).

struct ActivityPickerView: View {
    let workout: Workout
    @ObservedObject var labelStore: ActivityLabelStore
    @Environment(\.dismiss) private var dismiss

    private var current: ActivityType? { labelStore.manualLabel(for: workout.id) }
    private var activityOnly: ActivityType? { labelStore.activityOnlyType(for: workout) }
    private var crossfitStyle: CrossFitSessionStyle? { labelStore.sessionStyle(for: workout) }

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                        workoutSection
                        if current == .crossfit { crossfitStyleSection }
                        activityOnlySection
                        dismissSection
                    }
                    .padding(WH.Spacing.md)
                }
            }
            .navigationTitle("Clasificar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Entrenos

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("ES UN ENTRENO")
            VStack(spacing: 1) {
                ForEach(ActivityType.allCases.filter { !ActivityType.activityOnlyCases.contains($0) }) { type in
                    Button {
                        labelStore.set(type, for: workout)
                        if type != .crossfit { dismiss() }
                    } label: {
                        row(type, selected: current == type)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))

            if current != nil {
                Button {
                    labelStore.set(nil, for: workout)
                    labelStore.setSessionStyle(nil, for: workout)
                    dismiss()
                } label: {
                    Text("Quitar clasificación de entreno")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WH.Color.recoveryRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Estilo CrossFit

    private var crossfitStyleSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("ESTILO CROSSFIT")
            VStack(spacing: 1) {
                ForEach(CrossFitSessionStyle.allCases) { style in
                    Button {
                        labelStore.setSessionStyle(style, for: workout)
                        if style != .regular { dismiss() }
                    } label: {
                        HStack(spacing: WH.Spacing.md) {
                            Image(systemName: style.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(style == .qualifier ? WH.Color.recoveryYellow : WH.Color.strainBlue)
                                .frame(width: 28)
                            Text(style.displayName)
                                .font(.system(size: 16))
                                .foregroundStyle(WH.Color.textPrimary)
                            Spacer()
                            if crossfitStyle == style || (crossfitStyle == nil && style == .regular) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(WH.Color.strainBlue)
                            }
                        }
                        .padding(.horizontal, WH.Spacing.md)
                        .padding(.vertical, WH.Spacing.sm + 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    // MARK: - Actividad (no entreno)

    private var activityOnlySection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            sectionLabel("ACTIVIDAD, NO ENTRENO")
            Text("Sigue visible con su gráfico de FC, pero no suma en entrenos ni resumen deportivo.")
                .font(.system(size: 11))
                .foregroundStyle(WH.Color.textSecondary)
            VStack(spacing: 1) {
                ForEach(ActivityType.activityOnlyCases) { type in
                    Button {
                        labelStore.markAsActivityOnly(workout, type: type)
                        dismiss()
                    } label: {
                        row(type, selected: activityOnly == type)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    labelStore.markAsActivityOnly(workout, type: nil)
                    dismiss()
                } label: {
                    HStack(spacing: WH.Spacing.md) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 18))
                            .foregroundStyle(WH.Color.textSecondary)
                            .frame(width: 28)
                        Text("Actividad sin etiqueta")
                            .font(.system(size: 16))
                            .foregroundStyle(WH.Color.textPrimary)
                        Spacer()
                        if labelStore.isDismissed(workout.id) && activityOnly == nil {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(WH.Color.strainBlue)
                        }
                    }
                    .padding(.horizontal, WH.Spacing.md)
                    .padding(.vertical, WH.Spacing.sm + 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private var dismissSection: some View {
        Group {
            if labelStore.isDismissed(workout.id) {
                Button {
                    labelStore.restoreAsWorkoutCandidate(workout.id)
                    dismiss()
                } label: {
                    Text("Volver a considerar como entreno")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WH.Color.strainBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.md)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(WH.Font.cardTitle)
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.2)
    }

    private func row(_ type: ActivityType, selected: Bool) -> some View {
        HStack(spacing: WH.Spacing.md) {
            Image(systemName: type.symbol)
                .font(.system(size: 18))
                .foregroundStyle(type == .crossfit ? WH.Color.strainBlue : WH.Color.textPrimary)
                .frame(width: 28)
            Text(type.displayName)
                .font(.system(size: 16, weight: type == .crossfit ? .semibold : .regular))
                .foregroundStyle(WH.Color.textPrimary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WH.Color.strainBlue)
            }
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.sm + 2)
        .contentShape(Rectangle())
    }
}
