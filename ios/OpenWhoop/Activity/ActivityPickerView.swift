import SwiftUI

// MARK: - ActivityPickerView
// Hoja modal para asignar (o cambiar) el tipo de actividad de un entreno detectado.
// Replica el flujo "SELECCIONAR ACTIVIDAD" de la app oficial, con CrossFit destacado.

struct ActivityPickerView: View {
    let workout: Workout
    @ObservedObject var labelStore: ActivityLabelStore
    @Environment(\.dismiss) private var dismiss

    private var current: ActivityType? { labelStore.manualLabel(for: workout.id) }

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(ActivityType.allCases) { type in
                            Button {
                                labelStore.set(type, for: workout)
                                dismiss()
                            } label: {
                                row(type)
                            }
                            .buttonStyle(.plain)
                        }

                        if current != nil {
                            Button {
                                labelStore.set(nil, for: workout)
                                dismiss()
                            } label: {
                                Text("Quitar clasificación")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(WH.Color.recoveryRed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, WH.Spacing.md)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, WH.Spacing.md)
                        }
                    }
                    .background(WH.Color.surface,
                                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
                    .padding(WH.Spacing.md)
                }
            }
            .navigationTitle("Tipo de actividad")
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

    private func row(_ type: ActivityType) -> some View {
        HStack(spacing: WH.Spacing.md) {
            Image(systemName: type.symbol)
                .font(.system(size: 18))
                .foregroundStyle(type == .crossfit ? WH.Color.strainBlue : WH.Color.textPrimary)
                .frame(width: 28)
            Text(type.displayName)
                .font(.system(size: 16, weight: type == .crossfit ? .semibold : .regular))
                .foregroundStyle(WH.Color.textPrimary)
            Spacer()
            if current == type {
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
