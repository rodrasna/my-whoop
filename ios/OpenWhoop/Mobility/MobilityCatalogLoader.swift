import Foundation

// MARK: - MobilityCatalogLoader

enum MobilityCatalogLoader {
    private static let resourceName = "mobility_catalog"

    static func load(bundle: Bundle = .main) throws -> MobilityCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoaderError.missingResource
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(MobilityCatalog.self, from: data)
        } catch {
            throw LoaderError.decodeFailed(error.localizedDescription)
        }
    }

    static func loadExercises(bundle: Bundle = .main) -> [MobilityExercise] {
        (try? load(bundle: bundle).exercises) ?? []
    }

    enum LoaderError: LocalizedError {
        case missingResource
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingResource:
                return "No se encontró mobility_catalog.json en el bundle."
            case .decodeFailed(let msg):
                return "Catálogo de movilidad corrupto: \(msg)"
            }
        }
    }
}
