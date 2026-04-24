import XCTest
@testable import DictImporter

final class SM2SchedulerTests: XCTestCase {

    func testFirstGoodYieldsOneDay() {
        let srs = DevSRS()
        let next = DevSM2.update(srs: srs, grade: .good)
        XCTAssertEqual(next.repetitions, 1)
        XCTAssertEqual(next.intervalDays, 1)
        XCTAssertEqual(next.ease, 2.5, accuracy: 1e-9)
    }

    func testSecondGoodYieldsSixDays() {
        var srs = DevSRS()
        srs = DevSM2.update(srs: srs, grade: .good)
        srs = DevSM2.update(srs: srs, grade: .good)
        XCTAssertEqual(srs.repetitions, 2)
        XCTAssertEqual(srs.intervalDays, 6)
    }

    func testThirdGoodMultipliesByEase() {
        var srs = DevSRS()
        srs = DevSM2.update(srs: srs, grade: .good) // 1
        srs = DevSM2.update(srs: srs, grade: .good) // 6
        srs = DevSM2.update(srs: srs, grade: .good) // 6 * 2.5 = 15
        XCTAssertEqual(srs.intervalDays, 15)
    }

    func testAgainResetsAndReducesEase() {
        var srs = DevSRS()
        srs = DevSM2.update(srs: srs, grade: .good)
        srs = DevSM2.update(srs: srs, grade: .good)
        let before = srs
        srs = DevSM2.update(srs: srs, grade: .again)
        XCTAssertEqual(srs.repetitions, 0)
        XCTAssertEqual(srs.intervalDays, 1)
        XCTAssertEqual(srs.lapses, before.lapses + 1)
        XCTAssertEqual(srs.ease, max(DevSM2.minEase, before.ease - 0.2), accuracy: 1e-9)
    }

    func testEaseFloor() {
        var srs = DevSRS(ease: 1.35)
        srs = DevSM2.update(srs: srs, grade: .again) // 1.35 - 0.2 = floor 1.3
        XCTAssertEqual(srs.ease, DevSM2.minEase, accuracy: 1e-9)
    }

    func testEasyIncreasesEase() {
        var srs = DevSRS()
        srs = DevSM2.update(srs: srs, grade: .good)
        let prevEase = srs.ease
        srs = DevSM2.update(srs: srs, grade: .easy)
        XCTAssertEqual(srs.ease, prevEase + 0.15, accuracy: 1e-9)
    }

    func testDueAtIsNowPlusIntervalDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var srs = DevSRS()
        srs = DevSM2.update(srs: srs, grade: .good, now: now)
        let expected = now.addingTimeInterval(1 * 86_400)
        XCTAssertEqual(srs.dueAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }
}
