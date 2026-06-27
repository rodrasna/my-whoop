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

    func testSelectedDateStartsAtTodayMidnight() {
        let router = RootTabRouter()
        XCTAssertTrue(Calendar.current.isDateInToday(router.selectedDate))
        XCTAssertEqual(
            router.selectedDate,
            Calendar.current.startOfDay(for: Date())
        )
    }

    func testSelectedDateSharedAcrossBinding() {
        let router = RootTabRouter()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        router.selectedDate = yesterday
        XCTAssertTrue(Calendar.current.isDateInYesterday(router.selectedDate))
    }
}
