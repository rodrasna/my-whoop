import XCTest
@testable import OpenWhoop

@MainActor
final class RootTabRouterTests: XCTestCase {

    func testOpenMobilitySetsTabAndPendingSession() {
        let router = RootTabRouter()
        router.openMobility(.preWorkout)
        XCTAssertEqual(router.selectedTab, RootTabRouter.Tab.mobility.rawValue)
        XCTAssertEqual(router.consumeMobilitySession(), .preWorkout)
    }

    func testConsumeMobilitySessionClearsPending() {
        let router = RootTabRouter()
        router.openMobility(.preSleep)
        _ = router.consumeMobilitySession()
        XCTAssertNil(router.consumeMobilitySession())
    }

    func testOpenMobilityPostWorkout() {
        let router = RootTabRouter()
        router.openMobility(.postWorkout)
        XCTAssertEqual(router.consumeMobilitySession(), .postWorkout)
    }
}
