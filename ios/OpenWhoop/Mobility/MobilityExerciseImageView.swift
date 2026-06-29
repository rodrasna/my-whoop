import SwiftUI
import UIKit

// MARK: - MobilityExerciseImageView
// Imagen del ejercicio (bundle local) con fallback al monigote.

struct MobilityExerciseImageView: View {
    let exercise: MobilityExercise
    var size: CGFloat = 88

    var body: some View {
        Group {
            if let uiImage = MobilityExerciseImageLoader.bundleImage(for: exercise) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = exercise.imageURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        MobilityStickFigureView(pose: exercise.pose)
                    default:
                        ProgressView()
                            .tint(WH.Color.textSecondary)
                    }
                }
            } else {
                MobilityStickFigureView(pose: exercise.pose)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
        .accessibilityLabel(exercise.name)
    }
}

enum MobilityExerciseImageLoader {

    private static let subdirectories = [
        "ExerciseImages",
        "Mobility/ExerciseImages",
        nil as String?,
    ]

    static func bundleImage(for exercise: MobilityExercise) -> UIImage? {
        if let asset = exercise.imageAsset?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            if let img = UIImage(named: asset) { return img }
            if let img = loadJPG(named: asset) { return img }
        }
        return loadJPG(named: exercise.id)
    }

    private static func loadJPG(named name: String) -> UIImage? {
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: subdirectory),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                return img
            }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
