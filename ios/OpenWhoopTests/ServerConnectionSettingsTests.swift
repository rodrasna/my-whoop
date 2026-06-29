import XCTest
@testable import OpenWhoop

@MainActor
final class ServerConnectionSettingsTests: XCTestCase {

    func testValidDeviceIdSlug() {
        XCTAssertTrue(ServerConnectionSettings.isValidDeviceId("rodri"))
        XCTAssertTrue(ServerConnectionSettings.isValidDeviceId("maria-whoop"))
        XCTAssertTrue(ServerConnectionSettings.isValidDeviceId("a1"))
        XCTAssertFalse(ServerConnectionSettings.isValidDeviceId(""))
        XCTAssertFalse(ServerConnectionSettings.isValidDeviceId("A"))
        XCTAssertFalse(ServerConnectionSettings.isValidDeviceId("-bad"))
        XCTAssertFalse(ServerConnectionSettings.isValidDeviceId("bad-"))
    }

    func testEffectiveDeviceIdPrefersUserOverride() {
        let settings = ServerConnectionSettings.shared
        let priorOnboarding = settings.hasCompletedOnboarding
        let priorId = settings.userDeviceId

        defer {
            UserDefaults.standard.set(priorOnboarding, forKey: "com.openwhoop.server.onboardingComplete")
            if priorId.isEmpty {
                UserDefaults.standard.removeObject(forKey: "com.openwhoop.server.deviceId")
            } else {
                UserDefaults.standard.set(priorId, forKey: "com.openwhoop.server.deviceId")
            }
        }

        try? settings.updateDeviceId("test-user-a")
        XCTAssertEqual(settings.effectiveDeviceId, "test-user-a")
    }

    func testTwoDeviceIdsProduceDistinctEffectiveIds() throws {
        let settings = ServerConnectionSettings.shared
        try settings.updateDeviceId("user-alpha")
        let alpha = settings.effectiveDeviceId
        try settings.updateDeviceId("user-beta")
        let beta = settings.effectiveDeviceId
        XCTAssertNotEqual(alpha, beta)
        XCTAssertEqual(beta, "user-beta")
    }
}
