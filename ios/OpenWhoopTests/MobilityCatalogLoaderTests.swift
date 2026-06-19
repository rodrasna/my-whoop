import XCTest
@testable import OpenWhoop

final class MobilityCatalogLoaderTests: XCTestCase {

    private var fixturesBundle: Bundle {
        Bundle(for: MobilityCatalogLoaderTests.self)
    }

    func testLoadFromAppBundle() throws {
        let catalog = try MobilityCatalogLoader.load(bundle: .main)
        XCTAssertGreaterThanOrEqual(catalog.exercises.count, 25)
    }

    func testCatalogUniqueIdsAndRequiredFields() throws {
        let catalog = try MobilityCatalogLoader.load(bundle: .main)
        let ids = catalog.exercises.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "IDs de ejercicio deben ser únicos")
        for ex in catalog.exercises {
            XCTAssertFalse(ex.id.isEmpty)
            XCTAssertFalse(ex.name.isEmpty)
            XCTAssertFalse(ex.description.isEmpty)
            XCTAssertFalse(ex.sessionKinds.isEmpty)
            XCTAssertFalse(ex.youtubeURL.isEmpty)
        }
    }

    func testMissingResourceThrows() {
        XCTAssertThrowsError(try MobilityCatalogLoader.load(bundle: fixturesBundle)) { error in
            guard case MobilityCatalogLoader.LoaderError.missingResource = error else {
                return XCTFail("Expected missingResource, got \(error)")
            }
        }
    }

    func testInvalidCatalogJSONFailsDecode() throws {
        guard let url = fixturesBundle.url(forResource: "mobility_catalog_invalid", withExtension: "json") else {
            throw XCTSkip("Fixture mobility_catalog_invalid.json no está en el bundle de tests")
        }
        let data = try Data(contentsOf: url)
        XCTAssertThrowsError(try JSONDecoder().decode(MobilityCatalog.self, from: data))
    }

    func testLoadExercisesReturnsEmptyOnFailure() {
        let exercises = MobilityCatalogLoader.loadExercises(bundle: fixturesBundle)
        XCTAssertTrue(exercises.isEmpty)
    }
}
