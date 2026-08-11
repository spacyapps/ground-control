// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import SkinTerminal

final class ElapsedFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func ago(_ seconds: TimeInterval) -> String {
        ElapsedFormatter.short(since: now.addingTimeInterval(-seconds), now: now)
    }

    func testSubTenSecondsReadsAsNow() {
        XCTAssertEqual(ago(0), "now")
        XCTAssertEqual(ago(9), "now")
    }

    func testSecondsMinutesHoursDays() {
        XCTAssertEqual(ago(10), "10s")
        XCTAssertEqual(ago(59), "59s")
        XCTAssertEqual(ago(60), "1m")
        XCTAssertEqual(ago(3599), "59m")
        XCTAssertEqual(ago(3600), "1h")
        XCTAssertEqual(ago(86_399), "23h")
        XCTAssertEqual(ago(86_400), "1d")
    }

    /// Hook lines carry the CLI's own timestamp, so a line can be a moment
    /// ahead of us. That must read as "now", not as a negative age.
    func testFutureTimestampsDoNotProduceNonsense() {
        XCTAssertEqual(ElapsedFormatter.short(since: now.addingTimeInterval(30), now: now), "now")
    }

    func testStalenessThresholdIsHalfAnHour() {
        XCTAssertFalse(ElapsedFormatter.isStale(since: now.addingTimeInterval(-29 * 60), now: now))
        XCTAssertTrue(ElapsedFormatter.isStale(since: now.addingTimeInterval(-31 * 60), now: now))
    }
}
